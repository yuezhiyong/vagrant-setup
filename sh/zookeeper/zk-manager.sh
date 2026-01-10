#!/bin/bash
# Zookeeper集群管理脚本

source /opt/sh/common/config.sh

ZK_PID_FILE="/tmp/zookeeper.pid"
ZK_CONFIG="/opt/sh/zookeeper/config/zookeeper.properties"

# 生成myid文件
generate_myid() {
    local host=$1
    local myid
    
    case $host in
        centos-101) myid=1 ;;
        centos-102) myid=2 ;;
        centos-103) myid=3 ;;
        *) 
            print_error "未知主机: $host"
            return 1
            ;;
    esac
    
    ssh $host "echo $myid > $ZK_DATA_DIR/myid"
    print_info "$host: myid设置为 $myid"
}

# 启动单个节点的Zookeeper
start_zk_node() {
    local host=$1
    
    print_info "在 $host 上启动Zookeeper..."
    
    # 生成myid文件
    generate_myid $host
    
    # 启动Zookeeper
    ssh $host "cd $ZK_HOME && nohup bin/zkServer.sh start > $LOG_HOME/zookeeper/zk-$host.log 2>&1 &"
    
    # 检查是否启动成功
    sleep 3
    if check_remote_service $host "zookeeper" $ZK_PID_FILE; then
        print_success "$host: Zookeeper启动成功"
    else
        print_error "$host: Zookeeper启动失败"
    fi
}

# 停止单个节点的Zookeeper
stop_zk_node() {
    local host=$1
    
    print_info "在 $host 上停止Zookeeper..."
    ssh $host "cd $ZK_HOME && bin/zkServer.sh stop"
    
    sleep 2
    local status=$(check_remote_service $host "zookeeper" $ZK_PID_FILE)
    if [ "$status" = "stopped" ]; then
        print_success "$host: Zookeeper已停止"
    else
        print_warning "$host: Zookeeper停止中..."
        ssh $host "cd $ZK_HOME && bin/zkServer.sh stop"
    fi
}

# 检查节点状态
status_zk_node() {
    local host=$1
    
    ssh $host "cd $ZK_HOME && bin/zkServer.sh status"
}

# 启动整个集群
start_zk_cluster() {
    print_info "启动Zookeeper集群..."
    
    for