# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "almalinux/8"
  config.vbguest.auto_update = false
  config.vbguest.no_remote = true

  CLUSTER_NET = "192.168.56"
  NODES = [101, 102, 103]
  
  # 全局禁用 GPG
  config.vm.provision "shell", 
    run: "once",
    inline: <<-SHELL
      echo "Disabling GPG check globally..."
      echo "gpgcheck=0" >> /etc/dnf/dnf.conf
      echo "localpkg_gpgcheck=0" >> /etc/dnf/dnf.conf
      echo "repo_gpgcheck=0" >> /etc/dnf/dnf.conf
      
      # 禁用所有已启用仓库的 GPG 检查
      find /etc/yum.repos.d/ -name "*.repo" -type f | while read repo; do
        sed -i 's/^gpgcheck=.*/gpgcheck=0/g' "$repo"
        sed -i 's/^repo_gpgcheck=.*/repo_gpgcheck=0/g' "$repo"
      done
      
      # 导入 GPG 密钥
      rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-* 2>/dev/null || true
    SHELL

  # =============================
  # 定义集群节点
  # =============================
  NODES.each do |i|
    config.vm.define "centos-#{i}" do |node|
      node.vm.hostname = "centos-#{i}"

      # --- Host-Only 网络（集群内部通信）---
      node.vm.network "private_network",
        ip: "#{CLUSTER_NET}.#{i}"

      # --- 仅 master 节点做端口转发 ---
      if i == 101
        {
          9870 => 9870
        }.each do |guest, host|
          node.vm.network "forwarded_port",
            guest: guest,
            host: host,
            host_ip: "127.0.0.1",
            auto_correct: true
        end
      end

      # --- 虚拟机资源 ---
      node.vm.provider "virtualbox" do |vb|
        vb.name   = "centos-#{i}"
        vb.memory = 1024
        vb.cpus   = 1
        vb.gui    = false
      end

      # =============================
      # Provision 脚本（基础设置）
      # =============================
      node.vm.provision "shell", inline: <<-SHELL
        set -e

        echo "=== Base setup for centos-#{i} ==="

        # ---------- DNS ----------
        cat > /etc/resolv.conf <<EOF
nameserver 223.5.5.5
nameserver 223.6.6.6
EOF

        # ---------- 主机名 / 时区 ----------
        hostnamectl set-hostname centos-#{i}
        timedatectl set-timezone Asia/Shanghai

        # ---------- 基础工具 ----------
        dnf clean all
        rm -rf /var/cache/dnf/*
        dnf install -y vim git wget curl net-tools openssh-clients sshpass

        # ---------- Java ----------
        dnf install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel

        JAVA_BIN=$(readlink -f $(which java))
        JAVA_HOME=$(dirname $(dirname $JAVA_BIN))
        cat > /etc/profile.d/java.sh <<EOF
export JAVA_HOME=$JAVA_HOME
export PATH=\\$JAVA_HOME/bin:\\$PATH
EOF
        chmod +x /etc/profile.d/java.sh

        # ---------- 防火墙 / SELinux ----------
        systemctl disable --now firewalld || true
        setenforce 0 || true
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

        # ---------- hosts ----------
        sed -i '/centos-10[1-3]/d' /etc/hosts
        cat >> /etc/hosts <<EOF
#{CLUSTER_NET}.101 centos-101
#{CLUSTER_NET}.102 centos-102
#{CLUSTER_NET}.103 centos-103
EOF

        echo "=== Base setup done for centos-#{i} ==="
      SHELL

      # =============================
      # 节点本地 SSH 配置（每次启动都执行）
      # =============================
      node.vm.provision "local-ssh", 
        type: "shell",
        run: "always",
        inline: <<-SHELL
          set -e
          
          NET=#{CLUSTER_NET}
          USER=vagrant
          SSH_DIR=/home/$USER/.ssh
          
          echo "=== Local SSH setup on $(hostname) ==="
          
          # 等待网络接口
          echo "Waiting for network interface..."
          for i in {1..30}; do
            if ip a | grep -q "$NET"; then
              echo "Network interface found."
              break
            fi
            sleep 1
          done
          
          # 创建 SSH 目录（使用 root 权限）
          mkdir -p $SSH_DIR
          chown -R $USER:$USER $SSH_DIR
          chmod 700 $SSH_DIR
          
          # 生成 SSH key（如果不存在）
          if [ ! -f $SSH_DIR/id_rsa ]; then
            echo "Generating SSH key for $USER..."
            # 使用 su 切换用户生成 key
            su - $USER -c "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
          fi
          
          # 配置 SSH config（使用 su 切换用户）
          su - $USER -c "cat > ~/.ssh/config <<'EOF'
      Host $NET.*
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null
        ConnectTimeout=10
      EOF"
          
          # 设置正确的权限
          su - $USER -c "chmod 600 ~/.ssh/config"
          
          echo "=== Local SSH setup done on $(hostname) ==="
        SHELL

      # --- 同步目录（禁用）---
      node.vm.synced_folder "./data", "/vagrant"
    end
  end

  # =============================
  # 触发器：在所有虚拟机启动后配置集群 SSH
  # =============================
  config.trigger.after :reload do |trigger|
    trigger.name = "configure-cluster-ssh"
    trigger.info = "Configuring SSH passwordless access between all cluster nodes"
    
    
    trigger.run_remote = {
      inline: <<-SHELL
        set -e
        
        NET="#{CLUSTER_NET}"
        USER="vagrant"
        PASSWORD="vagrant"
        
        echo "========================================="
        echo "Configuring SSH passwordless cluster access"
        echo "Master node: $(hostname)"
        echo "========================================="
        
        # 只允许在 master 节点执行
        if [ "$(hostname)" != "centos-101" ]; then
          echo "Not master node, skipping cluster SSH setup"
          exit 0
        fi
        
        # 函数：等待节点就绪
        wait_for_node() {
          local node_ip=\$1
          local node_name=\$2
          
          echo -n "Waiting for \$node_name (\$node_ip) to be reachable..."
          
          # 等待 ping 通
          for i in {1..60}; do
            if ping -c1 -W1 \$node_ip >/dev/null 2>&1; then
              echo -n " ping OK..."
              break
            fi
            sleep 2
            echo -n "."
          done
          
          # 等待 SSH 服务
          for i in {1..30}; do
            if nc -z -w5 \$node_ip 22 2>/dev/null; then
              echo " SSH OK"
              return 0
            fi
            sleep 2
            echo -n "."
          done
          
          echo " TIMEOUT"
          return 1
        }
        
        # 函数：配置 SSH 免密到目标节点
        setup_ssh_to_node() {
          local node_ip=\$1
          local node_name=\$2
          
          echo "Setting up SSH to \$node_name (\$node_ip)..."
          
          # 检查是否已经配置过
          if ssh -o ConnectTimeout=5 -o BatchMode=yes \
             \$USER@\$node_ip "echo connected" 2>/dev/null; then
            echo "SSH already configured for \$node_name"
            return 0
          fi
          
          # 使用 sshpass 复制公钥
          echo "Copying SSH key to \$node_name..."
          if sshpass -p "\$PASSWORD" \
             ssh-copy-id -o StrictHostKeyChecking=no \
             -o ConnectTimeout=10 \
             \$USER@\$node_ip 2>/dev/null; then
            echo "✓ SSH key copied to \$node_name"
            return 0
          else
            echo "Warning: ssh-copy-id failed for \$node_name, trying manual method..."
            
            # 手动方法
            local PUB_KEY="\$(cat /home/\$USER/.ssh/id_rsa.pub)"
            
            if sshpass -p "\$PASSWORD" ssh -o StrictHostKeyChecking=no \
               \$USER@\$node_ip "mkdir -p ~/.ssh && chmod 700 ~/.ssh" && \
               sshpass -p "\$PASSWORD" ssh -o StrictHostKeyChecking=no \
               \$USER@\$node_ip "echo '\$PUB_KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"; then
              echo "✓ SSH key manually copied to \$node_name"
              return 0
            else
              echo "✗ Failed to configure SSH for \$node_name"
              return 1
            fi
          fi
        }
        
        # 1. 收集 master 节点的公钥并添加到自己的 authorized_keys
        echo "=== Step 1: Configuring self-access ==="
        MASTER_PUB_KEY="\$(cat /home/\$USER/.ssh/id_rsa.pub)"
        if ! grep -q "\$MASTER_PUB_KEY" /home/\$USER/.ssh/authorized_keys 2>/dev/null; then
          echo "\$MASTER_PUB_KEY" >> /home/\$USER/.ssh/authorized_keys
          chmod 600 /home/\$USER/.ssh/authorized_keys
          echo "✓ Added master key to its own authorized_keys"
        else
          echo "Master key already in authorized_keys"
        fi
        
        # 2. 配置到其他节点的 SSH 免密
        echo ""
        echo "=== Step 2: Configuring access to worker nodes ==="
        
        WORKER_NODES=("102" "103")
        ALL_SUCCESS=true
        
        for node_num in "\${WORKER_NODES[@]}"; do
          NODE_IP="\$NET.\$node_num"
          NODE_NAME="centos-\$node_num"
          
          echo ""
          echo "--- Configuring \$NODE_NAME ---"
          
          # 等待节点就绪
          if ! wait_for_node "\$NODE_IP" "\$NODE_NAME"; then
            echo "Skipping \$NODE_NAME (not reachable)"
            ALL_SUCCESS=false
            continue
          fi
          
          # 配置 SSH 免密
          if setup_ssh_to_node "\$NODE_IP" "\$NODE_NAME"; then
            # 从 worker 节点获取公钥并添加到 master
            WORKER_PUB_KEY="\$(ssh \$USER@\$NODE_IP "cat ~/.ssh/id_rsa.pub" 2>/dev/null)"
            if [ -n "\$WORKER_PUB_KEY" ]; then
              if ! grep -q "\$WORKER_PUB_KEY" /home/\$USER/.ssh/authorized_keys 2>/dev/null; then
                echo "\$WORKER_PUB_KEY" >> /home/\$USER/.ssh/authorized_keys
                echo "✓ Added \$NODE_NAME key to master's authorized_keys"
              fi
            fi
          else
            ALL_SUCCESS=false
          fi
        done
        
        # 3. 分发完整的 authorized_keys 到所有节点
        echo ""
        echo "=== Step 3: Distributing complete authorized_keys ==="
        
        ALL_KEYS="\$(cat /home/\$USER/.ssh/authorized_keys)"
        
        for node_num in "101" "102" "103"; do
          NODE_IP="\$NET.\$node_num"
          NODE_NAME="centos-\$node_num"
          
          echo -n "Updating \$NODE_NAME..."
          
          if ssh \$USER@\$NODE_IP "echo '\$ALL_KEYS' > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null; then
            echo " ✓"
          else
            echo " ✗"
            ALL_SUCCESS=false
          fi
        done
        
        # 4. 测试 SSH 连接
        echo ""
        echo "=== Step 4: Testing SSH connections ==="
        
        echo "Testing from master to all nodes:"
        for node_num in "101" "102" "103"; do
          NODE_IP="\$NET.\$node_num"
          if ssh -o ConnectTimeout=5 \$USER@\$NODE_IP "hostname" 2>/dev/null; then
            echo "  ✓ master → \$NODE_IP"
          else
            echo "  ✗ master → \$NODE_IP"
            ALL_SUCCESS=false
          fi
        done
        
        echo ""
        if [ "\$ALL_SUCCESS" = "true" ]; then
          echo "========================================="
          echo "✓ SSH cluster configuration COMPLETE!"
          echo "All nodes can access each other without password"
          echo "========================================="
        else
          echo "========================================="
          echo "⚠ SSH cluster configuration PARTIALLY COMPLETE"
          echo "Some connections may not work"
          echo "========================================="
        fi
        
        # 显示集群信息
        echo ""
        echo "=== Cluster Information ==="
        echo "Master Node:  centos-101  (#{CLUSTER_NET}.101)"
        echo "Worker Nodes: centos-102  (#{CLUSTER_NET}.102)"
        echo "               centos-103  (#{CLUSTER_NET}.103)"
        echo ""
        echo "Web UI (if Hadoop is installed): http://localhost:9870"
        echo "========================================="
      SHELL
    }
  end
  
 

  # ---------- VirtualBox 全局 ----------
  config.vm.provider "virtualbox" do |vb|
    vb.check_guest_additions = false
    vb.functional_vboxsf = false
  end
end