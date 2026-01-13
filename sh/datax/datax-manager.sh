#!/bin/bash
# -*- mode: shell -*-
# DataX Manager 脚本（改进版）
# 功能：
#   - 启动 DataX 任务，自动限制 JVM 内存
#   - 停止任务
#   - 查看状态
#   - 自动检测 Python
#   - 自动创建日志目录

# 配置 DataX 安装路径
DATAX_HOME="/opt/module/datax"

# 默认日志目录
DEFAULT_LOG_DIR="${DATAX_HOME}/logs"
PID_FILE="/tmp/datax.pid"

# 默认 JVM 内存
DEFAULT_XMS="128m"
DEFAULT_XMX="256m"

# 打印信息
print_info() {
    echo -e "[INFO] $*"
}

print_error() {
    echo -e "[ERROR] $*" >&2
}

# 检查 Python
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
    JVM_XMS=${3:-$DEFAULT_XMS}
    JVM_XMX=${4:-$DEFAULT_XMX}

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
    print_info "JVM 内存设置: -Xms${JVM_XMS} -Xmx${JVM_XMX}"

    # 后台启动 DataX，添加 -j 参数限制 JVM 内存
    nohup "$PYTHON_BIN" "$DATAX_HOME/bin/datax.py" -j "-Xms${JVM_XMS} -Xmx${JVM_XMX}" "$JOB_JSON" > "$LOG_FILE" 2>&1 &
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

# 配置 DataX 集群环境
setup_datax() {
    print_info "配置 DataX 集群环境..."
    
    # 检查 DataX 是否已安装
    if [ ! -d "$DATAX_HOME" ]; then
        print_error "DataX 未安装，请先安装 DataX 到 $DATAX_HOME"
        exit 1
    fi
    
    # 创建日志目录
    mkdir -p "$DEFAULT_LOG_DIR"
    
    # 检查 Python 环境
    check_python
    
    # 创建示例配置文件
    mkdir -p "$DATAX_HOME/job"
    
    # 创建示例作业配置
    cat > "$DATAX_HOME/job/sample-job.json" <<EOF
{
    "job": {
        "setting": {
            "speed": {
                "channel": 1
            },
            "errorLimit": {
                "record": 0,
                "percentage": 0.02
            }
        },
        "content": [
            {
                "reader": {
                    "name": "streamreader",
                    "parameter": {
                        "sliceRecordCount": 10,
                        "column": [
                            {
                                "value": "DataX On Spark",
                                "type": "string"
                            },
                            {
                                "value": 1988,
                                "type": "long"
                            }
                        ]
                    }
                },
                "writer": {
                    "name": "streamwriter",
                    "parameter": {
                        "print": true
                    }
                }
            }
        ]
    }
}
EOF

    print_info "DataX 配置完成"
    print_info "示例作业文件已创建: $DATAX_HOME/job/sample-job.json"
    print_info "可以使用以下命令测试: $0 start $DATAX_HOME/job/sample-job.json"
}

# 主入口
case "$1" in
    start)
        if [ -z "$2" ]; then
            print_error "请指定 Job JSON 文件"
            echo "用法: $0 start <jobJson> [logDir] [Xms] [Xmx]|setup"
            exit 1
        fi
        start_datax "$2" "$3" "$4" "$5"
        ;;
    stop)
        stop_datax
        ;;
    status)
        status_datax
        ;;
    setup)
        setup_datax
        ;;
    *)
        echo "用法: $0 {start <jobJson> [logDir] [Xms] [Xmx]|stop|status|setup}"
        exit 1
        ;;
esac
