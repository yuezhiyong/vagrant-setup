#!/bin/bash

# ============================================
# Kafka集群管理脚本
# ============================================

# Dynamically calculate SCRIPTS_BASE based on script location
SCRIPTS_BASE=$(cd "$(dirname "$0")/.." && pwd)

# Temporarily set SCRIPTS_BASE for loading config files
export SCRIPTS_BASE
source $SCRIPTS_BASE/common/config.sh

# Override SCRIPTS_BASE with the actual script location
unset SCRIPTS_BASE
SCRIPTS_BASE=$(cd "$(dirname "$0")/.." && pwd)
export SCRIPTS_BASE

source $SCRIPTS_BASE/common/common.sh

setup_kafka() {
    print_step "设置Kafka集群"
    
    # 创建日志目录
    run_on_cluster "mkdir -p $KAFKA_LOG_DIR"
    
    # 为每个节点生成配置文件
    local broker_id=1
    for host in "${CLUSTER_HOSTS[@]}"; do
        local kafka_conf=$(cat << EOF
# Kafka Broker配置 - $host
broker.id=$broker_id
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://$host:9092
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

# 日志配置
log.dirs=$KAFKA_LOG_DIR
num.partitions=3
num.recovery.threads.per.data.dir=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

# Zookeeper配置
zookeeper.connect=${CLUSTER_HOSTS[0]}:2181,${CLUSTER_HOSTS[1]}:2181,${CLUSTER_HOSTS[2]}:2181
zookeeper.connection.timeout.ms=18000

# 副本配置
default.replication.factor=3
min.insync.replicas=2

# 其他配置
delete.topic.enable=true
auto.create.topics.enable=false
EOF
)
        
        # 直接将配置写入远程主机
        echo "$kafka_conf" | run_on_host $host "cat > $KAFKA_HOME/config/server.properties"
        
        broker_id=$((broker_id + 1))
    done
    
    print_success "Kafka集群配置完成"
}

check_zookeeper_before_kafka() {
    print_info "检查Zookeeper状态..."
    
    local running_zk=0
    for host in "${CLUSTER_HOSTS[@]}"; do
        if [ "$(check_process $host 'QuorumPeerMain' "$ZK_PID_FILE")" = "running" ]; then
            running_zk=$((running_zk + 1))
        fi
    done
    
    if [ $running_zk -lt 2 ]; then
        print_error "Zookeeper集群未运行或节点不足，请先启动Zookeeper"
        return 1
    fi
    
    print_success "Zookeeper集群正常 (运行节点: $running_zk/3)"
    return 0
}

start_kafka_node() {
    local host=$1
    
    # 检查是否已运行
    if run_on_host $host "pgrep -f 'kafka.Kafka' >/dev/null 2>&1"; then
        print_info "$host Kafka已在运行"
        return 0
    fi
    
    # 启动Kafka
    print_info "在 $host 启动Kafka..."
    run_on_host $host "bash -s" << EOF
set -a
KAFKA_HEAP_OPTS="-Xmx512M -Xms256M"
set +a

cd $KAFKA_HOME
nohup bin/kafka-server-start.sh config/server.properties > $KAFKA_LOG_DIR/kafka-$host.log 2>&1 &
EOF
    
    # 等待启动
    sleep 5
    local count=0
    local max_attempts=30
    local started=0
    
    while [ $count -lt $max_attempts ]; do
        if run_on_host $host "pgrep -f 'kafka.Kafka' >/dev/null 2>&1"; then
            # 额外检查端口是否开放
            if run_on_host $host "timeout 5 bash -c '</dev/tcp/localhost/9092' >/dev/null 2>&1"; then
                started=1
                break
            fi
        fi
        sleep 2
        ((count++))
    done
    
    if [ $started -eq 1 ]; then
        print_success "$host Kafka启动成功"
        return 0
    else
        print_error "$host Kafka启动失败"
        return 1
    fi
}

start_kafka_cluster() {
    print_step "启动Kafka集群"
    
    # 检查Zookeeper
    if ! check_zookeeper_before_kafka; then
        return 1
    fi
    
    # 检查配置
    if [ ! -f "$KAFKA_HOME/config/server.properties" ]; then
        print_warning "Kafka配置文件不存在，正在设置..."
        setup_kafka
    fi
    
    # 启动所有节点
    local failed_nodes=0
    for host in "${CLUSTER_HOSTS[@]}"; do
        if ! start_kafka_node $host; then
            failed_nodes=$((failed_nodes + 1))
        fi
        sleep 2
    done
    
    # 检查集群状态
    if [ $failed_nodes -eq 0 ]; then
        print_success "Kafka集群启动完成"
        check_kafka_status
    else
        print_error "$failed_nodes 个节点启动失败"
        return 1
    fi
}

stop_kafka_node() {
    local host=$1
    
    print_info "在 $host 停止Kafka..."
    run_on_host $host "cd $KAFKA_HOME && bin/kafka-server-stop.sh"
    
    # 等待停止
    sleep 5
    if ! run_on_host $host "pgrep -f 'kafka.Kafka' >/dev/null 2>&1"; then
        print_success "$host Kafka已停止"
        return 0
    else
        print_warning "$host Kafka可能仍在运行，尝试强制停止..."
        run_on_host $host "pkill -f 'kafka.Kafka'"
        return 1
    fi
}

stop_kafka_cluster() {
    print_step "停止Kafka集群"
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        stop_kafka_node $host
    done
    
    print_success "Kafka集群已停止"
}

check_kafka_status() {
    print_step "Kafka集群状态"
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "检查 $host 状态..."
        
        if run_on_host $host "pgrep -f 'kafka.Kafka' >/dev/null 2>&1"; then
            # 再做一次真正的 Broker 可用性检查
            if run_on_host $host "cd $KAFKA_HOME && bin/kafka-broker-api-versions.sh --bootstrap-server $host:9092 >/dev/null 2>&1"; then
                print_success "$host: 运行中 (健康)"
            else
                print_warning "$host: 进程存在，但 Broker 不可用"
            fi
        else
            print_error "$host: Kafka未运行"
        fi
    done
    
    # 检查主题
    if [ "$1" = "detail" ]; then
        print_info "Kafka主题列表:"
        local first_host="${CLUSTER_HOSTS[0]}"
        run_on_host $first_host "cd $KAFKA_HOME && bin/kafka-topics.sh --list --bootstrap-server $first_host:9092"
    fi
}

create_test_topic() {
    local topic_name=${1:-"test-topic"}
    local partitions=${2:-3}
    local replication=${3:-3}
    
    print_info "创建测试主题: $topic_name"
    local first_host="${CLUSTER_HOSTS[0]}"
    
    run_on_host $first_host "cd $KAFKA_HOME && bin/kafka-topics.sh --create \
        --bootstrap-server $first_host:9092 \
        --replication-factor $replication \
        --partitions $partitions \
        --topic $topic_name"
    
    print_info "主题详情:"
    run_on_host $first_host "cd $KAFKA_HOME && bin/kafka-topics.sh --describe \
        --bootstrap-server $first_host:9092 \
        --topic $topic_name"
}

case "$1" in
    start)
        start_kafka_cluster
        ;;
        
    stop)
        stop_kafka_cluster
        ;;
        
    restart)
        stop_kafka_cluster
        sleep 5
        start_kafka_cluster
        ;;
        
    status)
        check_kafka_status "$2"
        ;;
        
    setup)
        setup_kafka
        ;;
        
    create-topic)
        create_test_topic "$2" "$3" "$4"
        ;;
        
    list-topics)
        run_on_host "${CLUSTER_HOSTS[0]}" "cd $KAFKA_HOME && bin/kafka-topics.sh --list --bootstrap-server ${CLUSTER_HOSTS[0]}:9092"
        ;;
        
    *)
        echo "用法: $0 {start|stop|restart|status|setup|create-topic|list-topics}"
        echo ""
        echo "命令说明:"
        echo "  start                    启动Kafka集群"
        echo "  stop                     停止Kafka集群"
        echo "  restart                  重启Kafka集群"
        echo "  status [detail]          查看Kafka集群状态，可选详细模式"
        echo "  setup                    设置Kafka集群配置"
        echo "  create-topic [name] [partitions] [replication] 创建测试主题"
        echo "  list-topics              列出所有主题"
        exit 1
esac