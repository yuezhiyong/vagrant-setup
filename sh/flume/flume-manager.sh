#!/bin/bash

# ============================================
# Flume管理脚本
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

# Flume Agent配置
declare -A FLUME_AGENTS=(
    ["log-collector"]="log-collector.conf"
    ["kafka-sink"]="kafka-sink.conf"
    ["hdfs-sink"]="hdfs-sink.conf"
)

setup_flume() {
    print_step "设置Flume"
    
    # 创建配置目录
    run_on_cluster "mkdir -p $FLUME_CONF_DIR $FLUME_LOG_DIR"
    
    # 分发基础配置文件
    if [ -d "$SCRIPTS_BASE/flume/conf" ]; then
        sync_directory "$SCRIPTS_BASE/flume/conf" "$FLUME_CONF_DIR"
    fi
    
    print_success "Flume配置完成"
}

start_flume_agent() {
    local host=$1
    local agent_name=$2
    local config_file=$3
    
    # 检查配置文件
    local config_path="$FLUME_CONF_DIR/$config_file"
    if ! run_on_host $host "[ -f '$config_path' ]"; then
        print_error "$host 上不存在配置文件: $config_file"
        return 1
    fi
    
    # 检查是否已运行
    local pid_file="$FLUME_PID_DIR/flume-$agent_name.pid"
    local status=$(check_process $host "flume" "$pid_file")
    if [ "$status" = "running" ]; then
        print_info "$host Flume Agent '$agent_name' 已在运行"
        return 0
    fi
    
    # 启动Flume Agent
    print_info "在 $host 启动Flume Agent: $agent_name"
    run_on_host $host "cd $FLUME_HOME && nohup bin/flume-ng agent \
        --name $agent_name \
        --conf-file $config_path \
        --conf $FLUME_HOME/conf \
        -Dflume.root.logger=INFO,console \
        > $FLUME_LOG_DIR/flume-$agent_name-$host.log 2>&1 & \
        echo \$! > $pid_file"
    
    # 等待启动
    sleep 3
    if wait_for_process $host "flume" "$pid_file" 10; then
        print_success "$host Flume Agent '$agent_name' 启动成功"
        return 0
    else
        print_error "$host Flume Agent '$agent_name' 启动失败"
        return 1
    fi
}

start_flume_cluster() {
    local agent_type=${1:-"all"}
    
    print_step "启动Flume集群"
    
    # 检查配置
    if [ ! -d "$FLUME_CONF_DIR" ] || [ -z "$(ls -A $FLUME_CONF_DIR/*.conf 2>/dev/null)" ]; then
        print_warning "Flume配置文件不存在，正在设置..."
        setup_flume
    fi
    
    # 根据类型启动不同的Agent
    case $agent_type in
        "log-collector")
            # 在所有节点启动日志收集器
            for host in "${CLUSTER_HOSTS[@]}"; do
                start_flume_agent $host "log-collector" "log-collector.conf"
            done
            ;;
            
        "kafka-sink")
            # 在指定节点启动Kafka Sink
            start_flume_agent "${CLUSTER_HOSTS[0]}" "kafka-sink" "kafka-sink.conf"
            ;;
            
        "hdfs-sink")
            # 在指定节点启动HDFS Sink
            start_flume_agent "${CLUSTER_HOSTS[0]}" "hdfs-sink" "hdfs-sink.conf"
            ;;
            
        "all")
            # 启动所有Agent
            for agent in "${!FLUME_AGENTS[@]}"; do
                start_flume_cluster $agent
            done
            ;;
            
        *)
            print_error "未知的Agent类型: $agent_type"
            return 1
            ;;
    esac
    
    check_flume_status
}

stop_flume_agent() {
    local host=$1
    local agent_name=$2
    
    local pid_file="$FLUME_PID_DIR/flume-$agent_name.pid"
    
    print_info "在 $host 停止Flume Agent: $agent_name"
    
    # 尝试正常停止
    if run_on_host $host "[ -f '$pid_file' ]"; then
        local pid=$(run_on_host $host "cat $pid_file")
        run_on_host $host "kill $pid 2>/dev/null"
        
        # 等待停止
        sleep 3
        if [ "$(check_process $host "flume" "$pid_file")" = "stopped" ]; then
            print_success "$host Flume Agent '$agent_name' 已停止"
            run_on_host $host "rm -f $pid_file"
            return 0
        fi
    fi
    
    # 强制停止
    print_warning "$host 强制停止Flume Agent: $agent_name"
    run_on_host $host "pkill -f 'flume.*$agent_name'"
    run_on_host $host "rm -f $pid_file"
    return 1
}

stop_flume_cluster() {
    local agent_type=${1:-"all"}
    
    print_step "停止Flume集群"
    
    case $agent_type in
        "log-collector")
            for host in "${CLUSTER_HOSTS[@]}"; do
                stop_flume_agent $host "log-collector"
            done
            ;;
            
        "kafka-sink")
            stop_flume_agent "${CLUSTER_HOSTS[0]}" "kafka-sink"
            ;;
            
        "hdfs-sink")
            stop_flume_agent "${CLUSTER_HOSTS[0]}" "hdfs-sink"
            ;;
            
        "all")
            for agent in "${!FLUME_AGENTS[@]}"; do
                stop_flume_cluster $agent
            done
            ;;
    esac
    
    print_success "Flume集群已停止"
}

check_flume_status() {
    print_step "Flume集群状态"
    
    for agent in "${!FLUME_AGENTS[@]}"; do
        print_info "Agent: $agent"
        
        case $agent in
            "log-collector")
                for host in "${CLUSTER_HOSTS[@]}"; do
                    local pid_file="$FLUME_PID_DIR/flume-$agent.pid"
                    local status=$(check_process $host "flume" "$pid_file")
                    echo "  $host: $status"
                done
                ;;
                
            *)
                local host="${CLUSTER_HOSTS[0]}"
                local pid_file="$FLUME_PID_DIR/flume-$agent.pid"
                local status=$(check_process $host "flume" "$pid_file")
                echo "  $host: $status"
                ;;
        esac
    done
}

create_flume_config() {
    local config_type=$1
    local config_name=$2
    
    print_info "创建Flume配置文件: $config_name.conf"
    
    case $config_type in
        "kafka-sink")
            cat > "$FLUME_CONF_DIR/$config_name.conf" << EOF
# Flume Kafka Sink配置
agent.sources = tail-source
agent.channels = file-channel
agent.sinks = kafka-sink

# Source配置 - 监控日志文件
agent.sources.tail-source.type = TAILDIR
agent.sources.tail-source.channels = file-channel
agent.sources.tail-source.positionFile = $FLUME_LOG_DIR/taildir_position.json
agent.sources.tail-source.filegroups = f1
agent.sources.tail-source.filegroups.f1 = /var/log/application/.*\.log

# Channel配置
agent.channels.file-channel.type = file
agent.channels.file-channel.checkpointDir = $FLUME_LOG_DIR/checkpoint
agent.channels.file-channel.dataDirs = $FLUME_LOG_DIR/data
agent.channels.file-channel.capacity = 10000
agent.channels.file-channel.transactionCapacity = 1000

# Sink配置 - Kafka
agent.sinks.kafka-sink.type = org.apache.flume.sink.kafka.KafkaSink
agent.sinks.kafka-sink.channel = file-channel
agent.sinks.kafka-sink.kafka.bootstrap.servers = ${CLUSTER_HOSTS[0]}:9092,${CLUSTER_HOSTS[1]}:9092,${CLUSTER_HOSTS[2]}:9092
agent.sinks.kafka-sink.kafka.topic = flume-logs
agent.sinks.kafka-sink.flumeBatchSize = 100
agent.sinks.kafka-sink.kafka.producer.acks = 1
EOF
            ;;
            
        "hdfs-sink")
            cat > "$FLUME_CONF_DIR/$config_name.conf" << EOF
# Flume HDFS Sink配置
agent.sources = kafka-source
agent.channels = mem-channel
agent.sinks = hdfs-sink

# Source配置 - Kafka Source
agent.sources.kafka-source.type = org.apache.flume.source.kafka.KafkaSource
agent.sources.kafka-source.channels = mem-channel
agent.sources.kafka-source.kafka.bootstrap.servers = ${CLUSTER_HOSTS[0]}:9092,${CLUSTER_HOSTS[1]}:9092,${CLUSTER_HOSTS[2]}:9092
agent.sources.kafka-source.kafka.topics = flume-logs
agent.sources.kafka-source.batchSize = 100
agent.sources.kafka-source.batchDurationMillis = 1000

# Channel配置
agent.channels.mem-channel.type = memory
agent.channels.mem-channel.capacity = 10000
agent.channels.mem-channel.transactionCapacity = 1000

# Sink配置 - HDFS
agent.sinks.hdfs-sink.type = hdfs
agent.sinks.hdfs-sink.channel = mem-channel
agent.sinks.hdfs-sink.hdfs.path = hdfs://${MASTER_NODE}:9000/flume/logs/%Y-%m-%d
agent.sinks.hdfs-sink.hdfs.filePrefix = logs-
agent.sinks.hdfs-sink.hdfs.fileSuffix = .log
agent.sinks.hdfs-sink.hdfs.rollInterval = 3600
agent.sinks.hdfs-sink.hdfs.rollSize = 134217728
agent.sinks.hdfs-sink.hdfs.rollCount = 0
agent.sinks.hdfs-sink.hdfs.fileType = DataStream
agent.sinks.hdfs-sink.hdfs.writeFormat = Text
EOF
            ;;
            
        *)
            print_error "未知的配置类型: $config_type"
            return 1
            ;;
    esac
    
    print_success "配置文件创建完成: $FLUME_CONF_DIR/$config_name.conf"
}

case "$1" in
    start)
        start_flume_cluster "$2"
        ;;
        
    stop)
        stop_flume_cluster "$2"
        ;;
        
    restart)
        stop_flume_cluster "$2"
        sleep 3
        start_flume_cluster "$2"
        ;;
        
    status)
        check_flume_status
        ;;
        
    setup)
        setup_flume
        ;;
        
    create-config)
        create_flume_config "$2" "$3"
        ;;
        
    list-configs)
        print_info "Flume配置文件:"
        for host in "${CLUSTER_HOSTS[@]}"; do
            run_on_host $host "ls -la $FLUME_CONF_DIR/*.conf 2>/dev/null || echo '无配置文件'"
        done
        ;;
        
    *)
        echo "用法: $0 {start|stop|restart|status|setup|create-config|list-configs}"
        echo ""
        echo "命令说明:"
        echo "  start [type]          启动Flume集群，可选类型: log-collector, kafka-sink, hdfs-sink, all"
        echo "  stop [type]           停止Flume集群"
        echo "  restart [type]        重启Flume集群"
        echo "  status                查看Flume集群状态"
        echo "  setup                 设置Flume配置"
        echo "  create-config type name 创建Flume配置文件"
        echo "  list-configs          列出所有配置文件"
        exit 1
esac