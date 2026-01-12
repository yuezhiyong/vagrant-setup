#!/bin/bash
# ============================================================
# Maxwell Manager Script
# ============================================================

# ========= 基础配置 =========
MAXWELL_HOME=/opt/module/maxwell
MAXWELL_BIN=$MAXWELL_HOME/bin/maxwell
MAXWELL_CONF=$MAXWELL_HOME/config.properties
LOG_DIR=$MAXWELL_HOME/logs
PID_DIR=$MAXWELL_HOME/run
PID_FILE=$PID_DIR/maxwell.pid


# Maxwell 节点（通常只需要 1 台）
MAXWELL_NODES=(centos-201)

SSH_CMD="ssh -o StrictHostKeyChecking=no"

# ========= 工具函数 =========
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

# ========= 单节点操作 =========
start_node() {
    local host=$1

    $SSH_CMD $host << EOF
mkdir -p $LOG_DIR $PID_DIR

if [ -f "$PID_FILE" ] && kill -0 \$(cat $PID_FILE) 2>/dev/null; then
    echo "[WARN] Maxwell already running on $host"
    exit 0
fi

nohup $MAXWELL_BIN \
  --config $MAXWELL_CONF \
  >> $LOG_DIR/maxwell.log 2>&1 &

echo \$! > $PID_FILE
echo "[INFO] Maxwell started on $host, pid=\$(cat $PID_FILE)"
EOF
}

stop_node() {
    local host=$1

    $SSH_CMD $host << EOF
if [ ! -f "$PID_FILE" ]; then
    echo "[WARN] Maxwell not running on $host"
    exit 0
fi

PID=\$(cat $PID_FILE)
if kill -0 \$PID 2>/dev/null; then
    kill \$PID
    echo "[INFO] Maxwell stopped on $host"
else
    echo "[WARN] Process not found, cleaning pid file"
fi

rm -f $PID_FILE
EOF
}

status_node() {
    local host=$1

    $SSH_CMD $host << EOF
if [ -f "$PID_FILE" ] && kill -0 \$(cat $PID_FILE) 2>/dev/null; then
    echo "[RUNNING] Maxwell on $host (pid=\$(cat $PID_FILE))"
else
    echo "[STOPPED] Maxwell on $host"
fi
EOF
}

# ========= 集群操作 =========
start_maxwell() {
    print_info "Starting Maxwell..."
    for host in ${MAXWELL_NODES[@]}; do
        echo "Starting $host..."
        start_node $host
    done
}

stop_maxwell() {
    print_info "Stopping Maxwell..."
    for host in ${MAXWELL_NODES[@]}; do
        stop_node $host
    done
}

status_maxwell() {
    print_info "Checking Maxwell status..."
    for host in ${MAXWELL_NODES[@]}; do
        status_node $host
    done
}

restart() {
    stop
    sleep 2
    start
}


bootstrap_table() {
    local db=$1
    local table=$2
    local where_clause=$3


    if [ -z "$db" ] || [ -z "$table" ]; then
        echo "用法: $0 bootstrap <db> <table>"
        exit 1
    fi

    # 1检查 Maxwell 主进程是否运行
    if ! pgrep -f "com.zendesk.maxwell.Maxwell" >/dev/null 2>&1; then
        print_error "Maxwell 未运行，请先执行: $0 start"
        exit 1
    fi

    # 2防止重复 bootstrap
    if [ -f "$BOOT_PID" ] && kill -0 "$(cat $BOOT_PID)" 2>/dev/null; then
        print_warning "bootstrap 已在运行中 (PID=$(cat $BOOT_PID))"
        echo "日志: tail -f $BOOT_LOG"
        exit 0
    fi
    print_info "Bootstrapping $db.$table (background mode)"

    nohup $MAXWELL_HOME/bin/maxwell-bootstrap \
        --config $MAXWELL_CONF \
        --database $db \
        --table $table \
        > $LOG_DIR/bootstrap-$db-$table.log 2>&1 &

    echo "Bootstrap started, log:"
    echo "  tail -f $LOG_DIR/bootstrap-$db-$table.log"
}

# ========= 主入口 =========
case "$1" in
    start)
        start_maxwell
        ;;
    stop)
        stop_maxwell
        ;;
    restart)
        stop_maxwell
        sleep 2
        start_maxwell
        ;;
    status)
        status_maxwell
        ;;
    bootstrap)
        bootstrap_table "$2" "$3" "$4"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|bootstrap}"
        echo ""
        echo "Examples:"
        echo "  $0 bootstrap order_db orders"
        exit 1
        ;;
esac
