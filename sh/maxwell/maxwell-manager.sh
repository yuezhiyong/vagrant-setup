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
MAXWELL_NODES=(centos-101)

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

# Bootstrap all tables in a database
bootstrap_database() {
    local db=$1

    if [ -z "$db" ]; then
        echo "用法: $0 bootstrap-database <db>"
        exit 1
    fi

    # 检查 Maxwell 主进程是否运行
    if ! pgrep -f "com.zendesk.maxwell.Maxwell" >/dev/null 2>&1; then
        print_error "Maxwell 未运行，请先执行: $0 start"
        exit 1
    fi

    print_info "获取数据库 $db 中的所有表..."
    
    # 提示用户输入 MySQL 连接参数
    echo -n "请输入 MySQL 主机地址 (默认: localhost): "
    read -r input_host
    mysql_host=${input_host:-localhost}
    
    echo -n "请输入 MySQL 用户名 (默认: root): "
    read -r input_user
    mysql_user=${input_user:-root}
    
    echo -n "请输入 MySQL 端口 (默认: 3306): "
    read -r input_port
    mysql_port=${input_port:-3306}
    
    # 提示输入密码但不在屏幕上显示
    echo -n "请输入 MySQL 密码: "
    stty -echo  # 关闭回显
    read -r mysql_password
    stty echo   # 恢复回显
    echo  # 换行

    # 创建临时 MySQL 配置文件用于安全认证
    MYSQL_CNF=$(mktemp)
    chmod 600 $MYSQL_CNF
    cat > $MYSQL_CNF << EOF
[client]
host=$mysql_host
user=$mysql_user
password=$mysql_password
port=$mysql_port
EOF
    
    tables=$(mysql --defaults-file=$MYSQL_CNF -e "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db' AND TABLE_TYPE='BASE TABLE';" 2>/dev/null | grep -v "TABLE_NAME")
    
    # 清理临时配置文件
    rm -f $MYSQL_CNF

    if [ -z "$tables" ]; then
        print_error "无法获取数据库 $db 中的表信息或数据库中无表"
        exit 1
    fi

    print_info "开始为数据库 $db 中的以下表进行 bootstrap:"
    echo "$tables"
    echo ""

    # 对每个表执行 bootstrap
    for table in $tables; do
        print_info "正在启动 $db.$table 的 bootstrap..."
        
        nohup $MAXWELL_HOME/bin/maxwell-bootstrap \
            --config $MAXWELL_CONF \
            --database $db \
            --table $table \
            > $LOG_DIR/bootstrap-$db-$table.log 2>&1 &
        
        # 等待一小段时间以确保启动成功
        sleep 1
        
        echo "Bootstrap started for $db.$table, log:"
        echo "  tail -f $LOG_DIR/bootstrap-$db-$table.log"
        echo ""
    done
    
    print_info "所有表的 bootstrap 任务已启动完成！"
    print_info "查看各表日志: ls $LOG_DIR/bootstrap-$db-*.log"
    print_info "实时监控所有日志: tail -f $LOG_DIR/bootstrap-$db-*.log"
}

# 配置 Maxwell 集群环境
setup_maxwell() {
    print_info "配置 Maxwell 集群环境..."
    
    # 检查 Maxwell 是否已安装
    if [ ! -d "$MAXWELL_HOME" ]; then
        print_error "Maxwell 未安装，请先安装 Maxwell 到 $MAXWELL_HOME"
        exit 1
    fi
    
    # 创建必要目录
    mkdir -p "$LOG_DIR" "$PID_DIR" "$MAXWELL_HOME/conf"
    
    # 创建默认配置文件
    cat > "$MAXWELL_CONF" <<EOF
# Maxwell 配置文件

# MySQL 配置
mysql_host=centos-101
mysql_user=maxwell
mysql_password=maxwell
mysql_port=3306

# Kafka 配置
producer=kafka
kafka.bootstrap.servers=centos-101:9092,centos-102:9092,centos-103:9092
kafka_topic=maxwell

# 其他配置
log_level=INFO
EOF

    print_info "Maxwell 配置完成"
    print_info "配置文件已创建: $MAXWELL_CONF"
    print_info "可使用以下命令启动: $0 start"
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
    bootstrap-database)
        bootstrap_database "$2"
        ;;
    setup)
        setup_maxwell
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|bootstrap|bootstrap-database|setup}"
        echo ""
        echo "Examples:"
        echo "  $0 bootstrap order_db orders"
        echo "  $0 bootstrap-database order_db"
        exit 1
        ;;
esac
