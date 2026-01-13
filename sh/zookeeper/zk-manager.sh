#!/bin/bash

# ============================================
# Zookeeper集群启动脚本
# ============================================

# Dynamically calculate SCRIPTS_BASE based on script location
SCRIPTS_BASE=$(cd "$(dirname "$0")/.." && pwd)

# Temporarily set SCRIPTS_BASE for loading config files
export SCRIPTS_BASE
source $SCRIPTS_BASE/common/config.sh
source $SCRIPTS_BASE/common/color.sh

# Override SCRIPTS_BASE with the actual script location
unset SCRIPTS_BASE
SCRIPTS_BASE=$(cd "$(dirname "$0")/.." && pwd)
export SCRIPTS_BASE

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
    
    # 写入配置文件为标准的zoo.cfg
    echo "$zk_conf_template" > /tmp/zoo.cfg
    distribute_file "/tmp/zoo.cfg" "$ZOOKEEPER_HOME/conf"
    rm -f /tmp/zoo.cfg
}

start_zookeeper_node() {
    local host=$1

    local port_status=$(CAPTURE_OUTPUT=true run_on_host $host "nc -z localhost 2181 >/dev/null 2>&1 && echo 'open' || echo 'closed'")
    if [ "$port_status" = "open" ]; then
        print_info "$host Zookeeper已在运行 (2181端口开放)"
        return 0
    fi

    print_info "在 $host 启动Zookeeper..."
    run_on_host $host "cd $ZOOKEEPER_HOME && nohup bin/zkServer.sh start conf/zoo.cfg > $ZK_LOG_DIR/zk-$host.log 2>&1 &"

    local retries=15
    while (( retries-- > 0 )); do
        port_status=$(CAPTURE_OUTPUT=true run_on_host $host "nc -z localhost 2181 >/dev/null 2>&1 && echo 'open' || echo 'closed'")
        if [ "$port_status" = "open" ]; then
            print_success "$host Zookeeper启动成功"
            return 0
        fi
        sleep 2
    done

    print_error "$host Zookeeper启动失败"
    return 1
}

start_zookeeper_cluster() {
    print_step "启动Zookeeper集群"
    
    # 检查设置
    if [ ! -f "$ZOOKEEPER_HOME/conf/zoo.cfg" ]; then
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
    local port_status=$(CAPTURE_OUTPUT=true run_on_host $host  "nc -z localhost 2181 >/dev/null 2>&1 && echo 'open' || echo 'closed'")
    if [ "$port_status" = "closed" ]; then
        print_info "$host Zookeeper已停止"
        return 0
    fi
    print_info "在 $host 停止Zookeeper..."
    run_on_host $host "cd $ZOOKEEPER_HOME && bin/zkServer.sh stop"
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
        local port_status=$(CAPTURE_OUTPUT=true run_on_host $host "nc -z localhost 2181 >/dev/null 2>&1 && echo 'open' || echo 'closed'")
        if [ "$port_status" = "open" ]; then
            print_success "$host: 运行中..."
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