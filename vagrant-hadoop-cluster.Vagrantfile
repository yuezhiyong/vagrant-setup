# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "almalinux/8"
  config.vbguest.auto_update = false
  config.vbguest.no_remote = true

  CLUSTER_NET = "192.168.56"
  NODES = [101, 102, 103]
  # 在定义虚拟机之前，先全局禁用 GPG
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
      
      # 导入 GPG 密钥的替代方案：直接信任所有
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
      # Provision 脚本
      # =============================
      node.vm.provision "shell", inline: <<-SHELL
        set -e

        echo "=== Base setup for centos-#{i} ==="

        # ---------- DNS ----------
        cat > /etc/resolv.conf <<EOF
nameserver 223.5.5.5
nameserver 223.6.6.6
EOF

        # ---------- 禁用 GPG ----------
        sed -i 's/^gpgcheck=.*/gpgcheck=0/' /etc/dnf/dnf.conf || true
        echo "gpgcheck=0" >> /etc/dnf/dnf.conf

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

        # ---------- hosts（先清，再写，防止残留） ----------
        sed -i '/centos-10[1-3]/d' /etc/hosts
        cat >> /etc/hosts <<EOF
#{CLUSTER_NET}.101 centos-101
#{CLUSTER_NET}.102 centos-102
#{CLUSTER_NET}.103 centos-103
EOF

        echo "=== Base setup done for centos-#{i} ==="
      SHELL

      # =============================
      # SSH 免密（网络就绪后执行）
      # =============================
      node.vm.provision "shell", run: "always", inline: <<-SHELL
        set -e

        NET=#{CLUSTER_NET}
        USER=vagrant
        PASSWORD=vagrant
        SSH_DIR=/home/$USER/.ssh

        echo "=== SSH mesh setup on $(hostname) ==="

        # --- 等待 Host-Only 网卡 ---
        for i in {1..30}; do
          ip a | grep -q "$NET" && break
          sleep 1
        done

        # --- 初始化 ssh 目录 ---
        sudo -u $USER mkdir -p $SSH_DIR
        sudo -u $USER chmod 700 $SSH_DIR

        # --- 生成 key（只生成一次） ---
        sudo -u $USER bash <<EOF
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi
EOF

        # --- SSH config ---
        sudo -u $USER bash <<EOF
cat > ~/.ssh/config <<CFG
Host $NET.*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
CFG
chmod 600 ~/.ssh/config
EOF

        # --- 仅 master 执行 copy ---
        if ip a | grep -q "$NET.101"; then
          for h in 102 103; do
            echo "Waiting for $NET.$h..."
            for i in {1..60}; do
              ping -c1 -W1 $NET.$h >/dev/null 2>&1 && break
              sleep 2
            done

            echo "Copying SSH key to centos-$h"
            sudo -u $USER sshpass -p "$PASSWORD" \
              ssh-copy-id -o StrictHostKeyChecking=no \
              $USER@$NET.$h || true
          done
        fi

        echo "=== SSH mesh done on $(hostname) ==="
      SHELL

      # --- 同步目录---
      node.vm.synced_folder "./data", "/vagrant", disabled: true
    end
  end

  # ---------- VirtualBox 全局 ----------
  config.vm.provider "virtualbox" do |vb|
    vb.check_guest_additions = false
    vb.functional_vboxsf = false
  end
end
