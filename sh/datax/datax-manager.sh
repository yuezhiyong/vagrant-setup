#!/bin/bash
# -*- mode: shell -*-
# 改进版 DataX Manager 脚本
# 功能：
#   - 启动 DataX 任务
#   - 停止任务
#   - 查看状态
#   - 自动检查 Python 环境
# 用法:
#   ./datax-manager.sh start <jobJson> [logDir]
#   ./datax-manager.sh stop
#   ./datax-manager.sh status

# 配置 DataX 安装路径
DATAX_HOME="/opt/module/datax"

# 默认日志目录
DEFAULT_LOG_DIR="${DATAX_HOME}/logs"
PID_FILE="/tmp/datax.pid"

# 打印信息
print_info() {
    echo -e "[INFO] $*"
}

print_error() {
    echo -e "[ERROR] $*" >&2
}

# 检查 Python 环境
check_python() {
    if command -v python >/dev/null 2>&1; then
        PYTHON_BIN=$(command -v python)
        print_info "使用 Python: $PYTHON_BIN"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN=$(command -v python3)
        print_info "系统未找到 python，使用 python3: $PYTHON_BIN"
    else
        print_error "系统未安装 Python，请先安装 Python 或 Python3"
        exit 1
    fi
}

# 启动 DataX
start_datax() {
    JOB_JSON=$1
    LOG_DIR=${2:-"$DEFAULT_LOG_DIR"}

    # 检查 Python
    check_python

    # 检查日志目录
    if [ ! -d "$LOG_DIR" ]; then
        print_info "日志目录不存在，创建: $LOG_DIR"
        mkdir -p "$LOG_DIR"
    fi

    # 检查 Job JSON 文件
    if [ ! -f "$JOB_JSON" ]; then
        print_error "Job JSON 文件不存在: $JOB_JSON"
        exit 1
    fi

    LOG_FILE="$LOG_DIR/datax_$(basename $JOB_JSON .json)_$(date +%Y%m%d%H%M%S).log"
    print_info "启动 DataX 任务: $JOB_JSON"
    print_info "日志文件: $LOG_FILE"

    nohup "$PYTHON_BIN" "$DATAX_HOME/bin/datax.py" "$JOB_JSON" > "$LOG_FILE" 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    print_info "DataX PID: $PID"
}

# 停止 DataX
stop_datax() {
    if [ ! -f "$PID_FILE" ]; then
        print_error "PID 文件不存在: $PID_FILE"
        exit 1
    fi

    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        print_info "停止 DataX PID: $PID"
        kill -9 "$PID"
        rm -f "$PID_FILE"
    else
        print_info "DataX PID $PID 不存在"
        rm -f "$PID_FILE"
    fi
}

# 查看状态
status_datax() {
    if [ ! -f "$PID_FILE" ]; then
        print_info "DataX 没有运行"
        exit 0
    fi

    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        print_info "DataX 正在运行, PID: $PID"
    else
        print_info "DataX 已停止"
        rm -f "$PID_FILE"
    fi
}

# 主入口
case "$1" in
    start)
        start_datax "$2" "$3"
        ;;
    stop)
        stop_datax
        ;;
    status)
        status_datax
        ;;
    *)
        echo "用法: $0 {start <jobJson> [logDir]|stop|status}"
        exit 1
        ;;
esac
