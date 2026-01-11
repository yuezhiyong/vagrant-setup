#!/bin/bash
# ============================================
# Hadoop 3.x 集群管理脚本（官方方式）
# ============================================

set -e

# ---------- 初始化 ----------
SCRIPTS_BASE=$(cd "$(dirname "$0")/.." && pwd)

export SCRIPTS_BASE
source "$SCRIPTS_BASE/common/config.sh"
source "$SCRIPTS_BASE/common/color.sh"
source "$SCRIPTS_BASE/common/common.sh"

HDFS_RPC_PORT=8020
HDFS_HTTP_PORT=9870
YARN_RM_PORT=8088

# ---------- 工具函数 ----------

check_port() {
    local host=$1
    local port=$2
    run_on_host "$host" "nc -z localhost $port >/dev/null 2>&1"
}

# ---------- HDFS ----------

format_namenode() {
    print_warning "⚠️ 即将格式化 NameNode（清空 HDFS 数据）"
    read -p "确认格式化？(y/n): " confirm
    [ "$confirm" = "y" ] || return 1

    run_on_host "$MASTER_NODE" \
        "$HADOOP_HOME/bin/hdfs namenode -format -force"
}

start_hdfs() {
    print_step "启动 HDFS (Hadoop 3.x)"

    if [ "$1" = "format" ]; then
        format_namenode
    fi

    print_info "执行 start-dfs.sh"
    run_on_host "$MASTER_NODE" "$HADOOP_HOME/sbin/start-dfs.sh"

    sleep 5
}

stop_hdfs() {
    print_step "停止 HDFS"
    run_on_host "$MASTER_NODE" "$HADOOP_HOME/sbin/stop-dfs.sh"
}

# ---------- YARN ----------

start_yarn() {
    print_step "启动 YARN"
    run_on_host "$MASTER_NODE" "$HADOOP_HOME/sbin/start-yarn.sh"
    sleep 3
}

stop_yarn() {
    print_step "停止 YARN"
    run_on_host "$MASTER_NODE" "$HADOOP_HOME/sbin/stop-yarn.sh"
}

# ---------- 状态检查 ----------

check_hdfs_status() {
    print_step "HDFS 状态"

    for host in "${CLUSTER_HOSTS[@]}"; do
        local nn="DOWN"
        local dn="DOWN"

        check_port "$host" "$HDFS_RPC_PORT" && nn="UP"
        run_on_host "$host" "pgrep -f DataNode >/dev/null 2>&1" && dn="UP"

        echo "  $host: NameNode[$nn] DataNode[$dn]"
    done

    print_info "HDFS 报告:"
    run_on_host "$MASTER_NODE" "$HADOOP_HOME/bin/hdfs dfsadmin -report" || true
}

check_yarn_status() {
    print_step "YARN 状态"

    for host in "${CLUSTER_HOSTS[@]}"; do
        local rm="DOWN"
        local nm="DOWN"

        check_port "$host" "$YARN_RM_PORT" && rm="UP"
        run_on_host "$host" "pgrep -f NodeManager >/dev/null 2>&1" && nm="UP"

        echo "  $host: ResourceManager[$rm] NodeManager[$nm]"
    done

    print_info "YARN 节点列表:"
    run_on_host "$MASTER_NODE" "$HADOOP_HOME/bin/yarn node -list" || true
}

check_all_status() {
    check_hdfs_status
    echo ""
    check_yarn_status
}

# ---------- 命令入口 ----------

case "$1" in
    start)
        start_hdfs "$2"
        start_yarn
        check_all_status
        ;;
    stop)
        stop_yarn
        stop_hdfs
        ;;
    restart)
        stop_yarn
        stop_hdfs
        sleep 3
        start_hdfs
        start_yarn
        check_all_status
        ;;
    status)
        check_all_status
        ;;
    start-hdfs)
        start_hdfs "$2"
        ;;
    stop-hdfs)
        stop_hdfs
        ;;
    start-yarn)
        start_yarn
        ;;
    stop-yarn)
        stop_yarn
        ;;
    format)
        format_namenode
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|start-hdfs|stop-hdfs|start-yarn|stop-yarn|format}"
        echo ""
        echo "说明:"
        echo "  start [format]   启动 HDFS + YARN（可选格式化）"
        echo "  stop             停止整个 Hadoop"
        echo "  restart          重启 Hadoop"
        echo "  status           查看集群状态"
        echo "  format           仅格式化 NameNode"
        exit 1
        ;;
esac
