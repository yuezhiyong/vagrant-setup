#!/bin/bash

# ============================================================
# Flume Manager Script (Hadoop / Kafka Compatible)
# ============================================================

# ---------- Script Base ----------
SCRIPTS_BASE=$(cd "$(dirname "$0")/.." && pwd)
export SCRIPTS_BASE

# ---------- Load Config ----------
source "$SCRIPTS_BASE/common/config.sh"
source "$SCRIPTS_BASE/common/common.sh"

# ---------- Built-in Flume Agents ----------
declare -A FLUME_AGENTS=(
    ["log-collector"]="log-collector.conf"
    ["kafka-sink"]="kafka-sink.conf"
    ["hdfs-sink"]="hdfs-sink.conf"
)

# ============================================================
# Usage
# ============================================================
usage() {
    cat << EOF

用法：
  $0 start [agent_type]
  $0 start <agent_name> <conf_file_path> [host]

  $0 stop [agent_type]
  $0 restart [agent_type]
  $0 status
  $0 setup
  $0 create-config <kafka-sink|hdfs-sink> <name>
  $0 list-configs

示例：
  $0 start log-collector
  $0 start all

  $0 start my-agent /opt/flume/conf/my-agent.conf
  $0 start my-agent /opt/flume/conf/my-agent.conf centos-102

EOF
}

# ============================================================
# Setup
# ============================================================
setup_flume() {
    print_step "设置 Flume 环境"

    run_on_cluster "
        mkdir -p $FLUME_CONF_DIR \
                 $FLUME_LOG_DIR \
                 $FLUME_PID_DIR
    "

    if [ -d "$SCRIPTS_BASE/flume/conf" ]; then
        sync_directory "$SCRIPTS_BASE/flume/conf" "$FLUME_CONF_DIR"
    fi

    print_success "Flume 环境初始化完成"
}

# ============================================================
# Core: Start One Agent
# ============================================================
start_flume_agent() {
    local host=$1
    local agent_name=$2
    local conf_path=$3

    if [[ -z "$host" || -z "$agent_name" || -z "$conf_path" ]]; then
        print_error "start_flume_agent 参数不足"
        return 1
    fi

    if ! run_on_host "$host" "[ -f '$conf_path' ]"; then
        print_error "$host 上不存在配置文件: $conf_path"
        return 1
    fi

    local pid_file="$FLUME_PID_DIR/flume-${agent_name}.pid"

    if [[ "$(check_process "$host" "flume" "$pid_file")" == "running" ]]; then
        print_info "$host Flume Agent [$agent_name] 已在运行"
        return 0
    fi

    print_info "在 $host 启动 Flume Agent [$agent_name]"
    print_info "使用配置文件: $conf_path"

    run_on_host "$host" "
        cd $FLUME_HOME && \
        nohup bin/flume-ng agent \
          --name $agent_name \
          --conf-file $conf_path \
          --conf $FLUME_HOME/conf \
          -Dflume.root.logger=INFO,console \
          > $FLUME_LOG_DIR/flume-${agent_name}-${host}.log 2>&1 & \
        echo \$! > $pid_file
    "

    sleep 3
    if wait_for_process "$host" "flume" "$pid_file" 10; then
        print_success "$host Flume Agent [$agent_name] 启动成功"
    else
        print_error "$host Flume Agent [$agent_name] 启动失败"
        return 1
    fi
}

# ============================================================
# Start Cluster (Built-in)
# ============================================================
start_flume_cluster() {
    local agent_type=${1:-"all"}

    print_step "启动 Flume 集群 ($agent_type)"

    if [ ! -d "$FLUME_CONF_DIR" ]; then
        print_warning "Flume 配置目录不存在，自动 setup"
        setup_flume
    fi

    case "$agent_type" in
        log-collector)
            for host in "${CLUSTER_HOSTS[@]}"; do
                start_flume_agent \
                    "$host" \
                    "log-collector" \
                    "$FLUME_CONF_DIR/log-collector.conf"
            done
            ;;
        kafka-sink|hdfs-sink)
            start_flume_agent \
                "${CLUSTER_HOSTS[0]}" \
                "$agent_type" \
                "$FLUME_CONF_DIR/${agent_type}.conf"
            ;;
        all)
            for agent in "${!FLUME_AGENTS[@]}"; do
                start_flume_cluster "$agent"
            done
            ;;
        *)
            print_error "未知 agent 类型: $agent_type"
            usage
            return 1
            ;;
    esac
}

# ============================================================
# Stop
# ============================================================
stop_flume_agent() {
    local host=$1
    local agent_name=$2
    local pid_file="$FLUME_PID_DIR/flume-${agent_name}.pid"

    print_info "在 $host 停止 Flume Agent [$agent_name]"

    if run_on_host "$host" "[ -f '$pid_file' ]"; then
        local pid
        pid=$(run_on_host "$host" "cat $pid_file")
        run_on_host "$host" "kill $pid 2>/dev/null"
        sleep 2
    fi

    run_on_host "$host" "pkill -f 'flume.*$agent_name' || true"
    run_on_host "$host" "rm -f $pid_file"
}

stop_flume_cluster() {
    local agent_type=${1:-"all"}

    print_step "停止 Flume 集群 ($agent_type)"

    case "$agent_type" in
        log-collector)
            for host in "${CLUSTER_HOSTS[@]}"; do
                stop_flume_agent "$host" "log-collector"
            done
            ;;
        kafka-sink|hdfs-sink)
            stop_flume_agent "${CLUSTER_HOSTS[0]}" "$agent_type"
            ;;
        all)
            for agent in "${!FLUME_AGENTS[@]}"; do
                stop_flume_cluster "$agent"
            done
            ;;
    esac
}

# ============================================================
# Status
# ============================================================
check_flume_status() {
    print_step "Flume 集群状态"

    for agent in "${!FLUME_AGENTS[@]}"; do
        echo "Agent: $agent"
        local pid_file="$FLUME_PID_DIR/flume-${agent}.pid"

        for host in "${CLUSTER_HOSTS[@]}"; do
            local status
            status=$(check_process "$host" "flume" "$pid_file")
            echo "  $host : $status"
        done
    done
}

# ============================================================
# Main
# ============================================================
case "$1" in
    start)
        # 自定义启动：start agent conf [host]
        if [[ $# -ge 3 ]]; then
            start_flume_agent "${4:-${CLUSTER_HOSTS[0]}}" "$2" "$3"
            exit $?
        fi
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
    list-configs)
        run_on_cluster "ls -lh $FLUME_CONF_DIR/*.conf 2>/dev/null || echo 无配置文件"
        ;;
    *)
        usage
        exit 1
        ;;
esac
