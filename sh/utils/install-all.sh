#!/bin/bash

# ============================================
# 集群安装脚本
# ============================================

source $SCRIPTS_BASE/common/common.sh

print_install_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                大数据集群安装脚本                        ║"
    echo "║                版本 1.0.0                                ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

setup_ssh_keys() {
    print_step "设置SSH免密登录"
    
    # 生成密钥（如果不存在）
    if [ ! -f ~/.ssh/id_rsa ]; then
        print_info "生成SSH密钥..."
        ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
    fi
    
    # 分发公钥到所有节点
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "设置 $host SSH免密登录..."
        ssh-copy-id -i ~/.ssh/id_rsa.pub $host
        
        # 测试SSH连接
        if check_ssh_connection $host; then
            print_success "$host SSH免密登录配置成功"
        else
            print_error "$host SSH免密登录配置失败"
            return 1
        fi
    done
}

setup_hosts() {
    print_step "设置/etc/hosts文件"
    
    local hosts_content="
# 大数据集群
192.168.100.101 centos-101
192.168.100.102 centos-102
192.168.100.103 centos-103
"
    
    # 更新所有节点的hosts文件
    for host in "${CLUSTER_HOSTS[@]}"; do
        # 备份原有hosts文件
        run_on_host $host "cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d)"
        
        # 添加集群主机名
        echo "$hosts_content" | run_on_host $host "cat >> /etc/hosts"
        
        print_success "$host hosts文件更新完成"
    done
}

setup_environment() {
    print_step "设置环境变量"
    
    local bashrc_content="
# 大数据环境变量
export JAVA_HOME=$JDK_HOME
export HADOOP_HOME=$HADOOP_HOME
export ZOOKEEPER_HOME=$ZOOKEEPER_HOME
export KAFKA_HOME=$KAFKA_HOME
export FLUME_HOME=$FLUME_HOME
export PATH=\$PATH:\$JAVA_HOME/bin:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin:\$ZOOKEEPER_HOME/bin:\$KAFKA_HOME/bin:\$FLUME_HOME/bin

# Hadoop配置
export HDFS_NAMENODE_USER=root
export HDFS_DATANODE_USER=root
export HDFS_SECONDARYNAMENODE_USER=root
export YARN_RESOURCEMANAGER_USER=root
export YARN_NODEMANAGER_USER=root
"
    
    # 设置所有节点的环境变量
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "设置 $host 环境变量..."
        echo "$bashrc_content" | run_on_host $host "cat >> ~/.bashrc"
        run_on_host $host "source ~/.bashrc"
    done
}

create_directories_structure() {
    print_step "创建目录结构"
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "在 $host 创建目录..."
        
        # 软件目录
        run_on_host $host "mkdir -p $MODULE_BASE"
        
        # 数据目录
        run_on_host $host "mkdir -p $ZK_DATA_DIR $ZK_LOG_DIR"
        run_on_host $host "mkdir -p $KAFKA_LOG_DIR $FLUME_LOG_DIR"
        run_on_host $host "mkdir -p $LOG_DIR"
        
        # Hadoop目录
        run_on_host $host "mkdir -p ${HDFS_NAME_DIR[@]} ${HDFS_DATA_DIR[@]} ${HDFS_CHECKPOINT_DIR[@]} ${YARN_NODEMANAGER_DIR[@]}"
        
        # 脚本目录
        run_on_host $host "mkdir -p $SCRIPTS_BASE"
        
        print_success "$host 目录创建完成"
    done
}

install_cluster() {
    print_install_banner
    
    print_warning "此脚本将设置大数据集群基础环境"
    print_warning "请确保所有节点已安装: JDK, Hadoop, Zookeeper, Kafka, Flume"
    read -p "继续安装？(y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        print_info "安装取消"
        exit 0
    fi
    
    # 1. 设置SSH免密登录
    setup_ssh_keys || exit 1
    
    # 2. 设置hosts文件
    setup_hosts
    
    # 3. 创建目录结构
    create_directories_structure
    
    # 4. 设置环境变量
    setup_environment
    
    # 5. 同步配置
    $SCRIPTS_BASE/utils/sync-config.sh all
    
    # 6. 检查环境
    $SCRIPTS_BASE/utils/check-env.sh
    
    print_step "安装完成"
    print_success "大数据集群基础环境设置完成！"
    
    echo ""
    echo -e "${GREEN}使用说明:${NC}"
    echo "1. 启动集群: $SCRIPTS_BASE/cluster/start-all.sh"
    echo "2. 停止集群: $SCRIPTS_BASE/cluster/stop-all.sh"
    echo "3. 查看状态: $SCRIPTS_BASE/cluster/status-all.sh"
    echo "4. 重启集群: $SCRIPTS_BASE/cluster/restart-all.sh"
    echo ""
    echo -e "${YELLOW}请确保所有软件已正确安装到 $MODULE_BASE 目录${NC}"
}

install_cluster