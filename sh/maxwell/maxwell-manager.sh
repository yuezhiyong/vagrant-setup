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
MAXWELL_NODES=(
centos-201
)

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
start() {
    print_info "Starting Maxwell..."
    for host in "\${MAXWELL_NODES[@]}"; do
        start_node \$host
    done
}

stop() {
    print_info "Stopping Maxwell..."
    for host in "\${MAXWELL_NODES[@]}"; do
        stop_node \$host
    done
}

status() {
    print_info "Checking Maxwell status..."
    for host in "\${MAXWELL_NODES[@]}"; do
        status_node \$host
    done
}

restart() {
    stop
    sleep 2
    start
}

# ========= 主入口 =========
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
