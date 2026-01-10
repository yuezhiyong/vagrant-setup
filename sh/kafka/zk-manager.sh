#!/bin/bash

# ============================================
# Zookeeper集群启动脚本
# ============================================

source $SCRIPTS_BASE/common/common.sh

setup_zookeeper() {
    print_step "设置Zookeeper"
    
    # 创建数据目录
    run_on_cluster "mkdir -p $ZK_DATA_DIR $ZK_LOG_DIR"
    
    # 设置myid文件
    local id=1
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "在 $host 设置myid=$id"
        run_on_host $host "echo $id > $ZK_DATA_DIR/myid"
        id=$((id + 1))
    done
    
    # 分发配置文件
    local zk_conf_template="
# Zookeeper配置
tickTime=2000
initLimit=10
syncLimit=5
dataDir=$ZK_DATA_DIR
dataLogDir=$ZK_LOG_DIR
clientPort=2181
maxClientCnxns=0
admin.enableServer=false
autopurge.snapRetainCount=3
autopurge.purgeInterval=24
4lw.commands.whitelist=*
"
    
    # 添加集群配置
    local id=1
    for host in "${CLUSTER_HOSTS[@]}"; do
        zk_conf_template+="server.$id=$host:2888:3888"$'\n'
        id=$((id + 1))
    done
    
    # 写入配置文件
    echo "$zk_conf_template" > /tmp/zookeeper.properties
    distribute_file "/tmp/zookeeper.properties" "$ZOOKEEPER_HOME/conf"
    rm -f /tmp/zookeeper.properties
}

start_zookeeper_node() {
    local host=$1
    
    # 检查是否已运行
    local status=$(check_process $host "QuorumPeerMain" "$ZK_PID_FILE")
    if [ "$status" = "running" ]; then
        print_info "$host Zookeeper已在运行"
        return 0
    fi
    
    # 启动Zookeeper
    print_info "在 $host 启动Zookeeper..."
    run_on_host $host "cd $ZOOKEEPER_HOME && nohup bin/zkServer.sh start > $ZK_LOG_DIR/zk-$host.log 2>&1 &"
    
    # 等待启动
    if wait_for_process $host "QuorumPeerMain" "$ZK_PID_FILE" 10; then
        print_success "$host Zookeeper启动成功"
        return 0
    else
        print_error "$host Zookeeper启动失败"
        return 1
    fi
}

start_zookeeper_cluster() {
    print_step "启动Zookeeper集群"
    
    # 检查设置
    if [ ! -f "$ZOOKEEPER_HOME/conf/zookeeper.properties" ]; then
        print_warning "Zookeeper配置文件不存在，正在设置..."
        setup_zookeeper
    fi
    
    # 启动所有节点
    local failed_nodes=0
    for host in "${CLUSTER_HOSTS[@]}"; do
        if ! start_zookeeper_node $host; then
            failed_nodes=$((failed_nodes + 1))
        fi
        sleep 1
    done
    
    # 检查集群状态
    if [ $failed_nodes -eq 0 ]; then
        print_success "Zookeeper集群启动完成"
        check_zookeeper_status
    else
        print_error "$failed_nodes 个节点启动失败"
        return 1
    fi
}

stop_zookeeper_node() {
    local host=$1
    
    print_info "在 $host 停止Zookeeper..."
    run_on_host $host "cd $ZOOKEEPER_HOME && bin/zkServer.sh stop"
    
    # 等待停止
    sleep 3
    local status=$(check_process $host "QuorumPeerMain" "$ZK_PID_FILE")
    if [ "$status" = "stopped" ]; then
        print_success "$host Zookeeper已停止"
        return 0
    else
        print_warning "$host Zookeeper可能仍在运行，尝试强制停止..."
        run_on_host $host "pkill -f 'QuorumPeerMain'"
        return 1
    fi
}

stop_zookeeper_cluster() {
    print_step "停止Zookeeper集群"
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        stop_zookeeper_node $host
    done
    
    print_success "Zookeeper集群已停止"
}

check_zookeeper_status() {
    print_step "Zookeeper集群状态"
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "检查 $host 状态..."
        local status=$(check_process $host "QuorumPeerMain" "$ZK_PID_FILE")
        if [ "$status" = "running" ]; then
            local mode=$(run_on_host $host "echo stat | nc localhost 2181 2>/dev/null | grep Mode | cut -d: -f2")
            if [ -n "$mode" ]; then
                print_success "$host: 运行中 (Mode:$mode)"
            else
                print_warning "$host: 运行中 (无法获取模式)"
            fi
        else
            print_error "$host: 未运行"
        fi
    done
}

case "$1" in
    start)
        start_zookeeper_cluster
        ;;
        
    stop)
        stop_zookeeper_cluster
        ;;
        
    restart)
        stop_zookeeper_cluster
        sleep 3
        start_zookeeper_cluster
        ;;
        
    status)
        check_zookeeper_status
        ;;
        
    setup)
        setup_zookeeper
        ;;
        
    *)
        echo "用法: $0 {start|stop|restart|status|setup}"
        echo ""
        echo "命令说明:"
        echo "  start     启动Zookeeper集群"
        echo "  stop      停止Zookeeper集群"
        echo "  restart   重启Zookeeper集群"
        echo "  status    查看Zookeeper集群状态"
        echo "  setup     设置Zookeeper集群配置"
        exit 1
esac