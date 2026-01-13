# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # ---------------------------
  # 基础配置
  # ---------------------------
  config.vm.box = "almalinux/8"
  config.vbguest.auto_update = false
  config.vbguest.no_remote = true

  CLUSTER_NET = "192.168.56"
  NODES       = [201, 202, 203]
  MASTER_ID   = 201
  SSH_USER    = "vagrant"
  SSH_PASS    = "vagrant"

  # ---------------------------
  # 全局关闭 GPG
  # ---------------------------
  config.vm.provision "shell", run: "once", inline: <<-SHELL
    echo "Disabling GPG check globally..."
    sed -i '/^gpgcheck/d' /etc/dnf/dnf.conf
    sed -i '/^localpkg_gpgcheck/d' /etc/dnf/dnf.conf
    sed -i '/^repo_gpgcheck/d' /etc/dnf/dnf.conf
    echo "gpgcheck=0" >> /etc/dnf/dnf.conf
    echo "localpkg_gpgcheck=0" >> /etc/dnf/dnf.conf
    echo "repo_gpgcheck=0" >> /etc/dnf/dnf.conf

    find /etc/yum.repos.d -name "*.repo" -exec \
      sed -i 's/^gpgcheck=.*/gpgcheck=0/' {} \\; || true
  SHELL

  # ---------------------------
  # 定义节点
  # ---------------------------
  NODES.each do |id|
    config.vm.define "centos-#{id}" do |node|
      node.vm.hostname = "centos-#{id}"

      node.vm.network "private_network",
        ip: "#{CLUSTER_NET}.#{id}"

      if id == MASTER_ID
        node.vm.network "forwarded_port",
          guest: 9870,
          host: 9870,
          host_ip: "127.0.0.1",
          auto_correct: true
      end

      node.vm.provider "virtualbox" do |vb|
        vb.name   = "centos-#{id}"
        vb.memory = 2048
        vb.cpus   = 1
        vb.gui    = false
      end

      # ---------------------------
      # 基础系统初始化
      # ---------------------------
      node.vm.provision "shell", inline: <<-SHELL
        set -e

        echo "=== Base setup: centos-#{id} ==="

        # DNS
        cat > /etc/resolv.conf <<EOF
nameserver 223.5.5.5
nameserver 223.6.6.6
EOF

        hostnamectl set-hostname centos-#{id}
        timedatectl set-timezone Asia/Shanghai

        dnf clean all
        dnf install -y \
          vim git curl wget net-tools python3 nc \
          openssh-clients sshpass

        systemctl disable --now firewalld || true
        setenforce 0 || true
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

        # hosts
        sed -i '/centos-20[1-3]/d' /etc/hosts
        cat >> /etc/hosts <<EOF
#{CLUSTER_NET}.201 centos-201
#{CLUSTER_NET}.202 centos-202
#{CLUSTER_NET}.203 centos-203
EOF

        # SSH config
        sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
        systemctl restart sshd
        echo "=== Base setup done: centos-#{id} ==="
      SHELL

      # ---------------------------
      # 每次启动都执行的 SSH 本地配置（关键）
      # ---------------------------
      node.vm.provision "shell", run: "always", inline: <<-SHELL
        set -e

        USER=#{SSH_USER}
        HOME_DIR=/home/$USER
        SSH_DIR=$HOME_DIR/.ssh

        mkdir -p $SSH_DIR
        chown -R $USER:$USER $SSH_DIR
        chmod 700 $SSH_DIR

        if [ ! -f $SSH_DIR/id_rsa ]; then
          su - $USER -c "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
        fi

        su - $USER -c "cat > ~/.ssh/config <<EOF
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
  LogLevel ERROR
EOF"

        su - $USER -c "chmod 600 ~/.ssh/config"
      SHELL

      node.vm.synced_folder ".", "/vagrant", disabled: true
    end
  end

  # ---------------------------
  # reload 后配置集群 SSH（只在 master）
  # ---------------------------
  config.trigger.after :reload do |t|
  t.name = "cluster-ssh"
  t.run_remote = {
    inline: <<-SHELL
      set -e

      USER=vagrant
      PASS=vagrant
      NET=192.168.56

      if [ "$(hostname)" != "centos-201" ]; then
        exit 0
      fi

      echo "=== Configuring SSH cluster (MASTER) ==="

      SSH_DIR=/home/$USER/.ssh
      AUTH_KEYS=$SSH_DIR/authorized_keys
      MASTER_KEY=$(cat $SSH_DIR/id_rsa.pub)

      # ---- 1. 本地 master ----
      echo "-> centos-201 (local)"
      mkdir -p $SSH_DIR
      chmod 700 $SSH_DIR
      grep -qxF "$MASTER_KEY" $AUTH_KEYS 2>/dev/null || echo "$MASTER_KEY" >> $AUTH_KEYS
      chmod 600 $AUTH_KEYS

      # ---- 2. worker：第一次用 sshpass 推 key ----
      for id in 202 203; do
        IP="$NET.$id"
        NODE="centos-$id"

        echo "-> $NODE"

        # 已免密则跳过
        if ssh -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               $USER@$IP "echo ok" >/dev/null 2>&1; then
          echo "   already configured"
          continue
        fi

        echo "   first time, using password auth"

        sshpass -p "$PASS" ssh \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          $USER@$IP "
            mkdir -p ~/.ssh &&
            chmod 700 ~/.ssh &&
            grep -qxF '$MASTER_KEY' ~/.ssh/authorized_keys 2>/dev/null || \
              echo '$MASTER_KEY' >> ~/.ssh/authorized_keys &&
            chmod 600 ~/.ssh/authorized_keys
          "
      done

      echo "=== SSH cluster ready ==="
    SHELL
  }
end

  # ---------------------------
  # VirtualBox 全局
  # ---------------------------
  config.vm.provider "virtualbox" do |vb|
    vb.check_guest_additions = false
    vb.functional_vboxsf = false
  end
end
