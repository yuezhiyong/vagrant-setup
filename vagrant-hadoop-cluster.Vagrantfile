# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # 使用CentOS 8镜像（更稳定）
  config.vm.box = "almalinux/8"
  config.vbguest.auto_update = false
  config.vbguest.no_remote = true
  
  # 全局数据同步目录配置
  # config.vm.synced_folder "./data", "/vagrant_data", 
  #   type: "rsync",
  #   create: true
  config.vm.synced_folder "./data", "/vagrant", disabled: true

  
  # 定义三台虚拟机
  (101..103).each do |i|
    config.vm.define "centos-#{i}" do |node|
      node.vm.hostname = "centos-#{i}"
      # 设置静态IP地址
      node.vm.network "private_network", ip: "192.168.1.#{i}"
      
      # 虚拟机资源分配
      node.vm.provider "virtualbox" do |vb|
        vb.name = "centos-8-#{i}"
        vb.memory = "1024"
        vb.cpus = 1
        vb.gui = false
      end
      
      # Provisioner配置（首次启动时执行）
      node.vm.provision "shell", inline: <<-SHELL
        echo "=== Setting up AlmaLinux 8 - Node #{i} ==="
        echo "Hostname: centos-#{i}"
        echo "IP: 192.168.1.#{i}"
        
        # 配置DNS（使用国内DNS服务器）
        echo "nameserver 223.5.5.5" > /etc/resolv.conf
        echo "nameserver 223.6.6.6" >> /etc/resolv.conf
        
        # 禁用所有仓库的GPG检查
        echo "gpgcheck=0" >> /etc/dnf/dnf.conf
        sed -i 's/^gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/*.repo 2>/dev/null || true
        
        # 设置主机名
        hostnamectl set-hostname centos-#{i}
        
        # 配置时区
        timedatectl set-timezone Asia/Shanghai
        
        # 更新系统并修复仓库
        echo "Updating system and fixing repositories..."
        dnf clean all
        rm -rf /var/cache/dnf/*
        
        
        # 启用PowerTools仓库（在AlmaLinux 8中叫做CRB）
        dnf config-manager --set-enabled powertools
        
        # 安装EPEL仓库（禁用GPG检查）
        dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        sed -i 's/^gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/epel*.repo
        
        # 安装基础工具
        echo "Installing basic tools..."
        dnf install -y vim git wget curl net-tools
        
        # 安装OpenJDK 8
        echo "Installing Java..."
        dnf install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
        
        # 验证Java
        java -version
        javac -version

        echo "=== Configuring JAVA_HOME ==="

        # 获取 java 可执行文件真实路径
        JAVA_BIN=$(readlink -f $(which java))
        JAVA_HOME=$(dirname $(dirname $JAVA_BIN))

        echo "Detected JAVA_HOME: $JAVA_HOME"

        # 写入系统级 profile（对所有用户生效）
        cat > /etc/profile.d/java.sh <<EOF
export JAVA_HOME=$JAVA_HOME
export PATH=\$JAVA_HOME/bin:\$PATH
EOF

chmod +x /etc/profile.d/java.sh
        
        # 禁用防火墙（开发环境）
        echo "Disabling firewall..."
        systemctl stop firewalld
        systemctl disable firewalld
        
        # 关闭SELinux
        echo "Disabling SELinux..."
        setenforce 0
        sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
        
        # 创建数据目录
        echo "Creating data directory..."
        mkdir -p /data
        chmod 777 /data
        
        # 配置hosts文件
        echo "Configuring hosts file..."
        cat >> /etc/hosts <<EOF
192.168.1.101 centos-101
192.168.1.102 centos-102
192.168.1.103 centos-103
EOF

      # 最后更新系统（可选，但建议）
      echo "Final system update..."
      dnf update -y --nogpgcheck
      
      # 显示系统信息
      echo "=== System Info ==="
      hostname
      ip -brief addr
      echo "Setup completed for centos-#{i}!"

      echo "=== Setting up passwordless SSH using ssh-copy-id ==="

      USER=vagrant
      PASSWORD=vagrant
      SSH_DIR=/home/$USER/.ssh

      # 安装 sshpass（EPEL 已启用）
      dnf install -y sshpass openssh-clients

      # 生成 key（只生成一次）
      if [ ! -f $SSH_DIR/id_rsa ]; then
        sudo -u $USER ssh-keygen -t rsa -N "" -f $SSH_DIR/id_rsa
      fi

      # 关闭首次连接确认
      cat >> $SSH_DIR/config <<EOF
Host 192.168.1.*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF

      chown -R $USER:$USER $SSH_DIR
      chmod 700 $SSH_DIR
      chmod 600 $SSH_DIR/*

      # 仅在 master 节点执行
      if [ "$(hostname)" = "centos-101" ]; then
        for h in 101 102 103; do
          echo "Copying SSH key to centos-$h"
          sshpass -p "$PASSWORD" \
            ssh-copy-id -o StrictHostKeyChecking=no \
            $USER@192.168.1.$h
        done
      fi
    SHELL
  end
end
  
  # VirtualBox全局配置
  config.vm.provider "virtualbox" do |vb|
    vb.check_guest_additions = false
    vb.functional_vboxsf = false
  end
  
  # SSH全局配置
end