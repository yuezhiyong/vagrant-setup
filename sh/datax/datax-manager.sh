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

# 显示帮助信息
show_help() {
    echo "DataX 管理脚本 - 用法说明"
    echo ""
    echo "命令格式: $0 {start|stop|status|setup|generate|run-job|run-all-jobs|help}"
    echo ""
    echo "可用命令:"
    echo "  start <jobJson> [logDir] [Xms] [Xmx]"
    echo "        启动 DataX 任务"
    echo "        jobJson: Job JSON 配置文件路径"
    echo "        logDir:  日志目录 (可选，默认: $DEFAULT_LOG_DIR)"
    echo "        Xms:     JVM 初始内存 (可选，默认: $DEFAULT_XMS)"
    echo "        Xmx:     JVM 最大内存 (可选，默认: $DEFAULT_XMX)"
    echo ""
    echo "  stop"
    echo "        停止当前运行的 DataX 任务"
    echo ""
    echo "  status"
    echo "        查看 DataX 任务运行状态"
    echo ""
    echo "  setup"
    echo "        配置 DataX 环境，创建示例配置文件"
    echo ""
    echo "  generate <jdbcUrl> <username> <password> <database> [tableName] [jobDir]"
    echo "        生成 DataX 任务配置文件"
    echo "        jdbcUrl:  JDBC 连接 URL"
    echo "        username: 数据库用户名"
    echo "        password: 数据库密码"
    echo "        database: 数据库名称"
    echo "        tableName: 表名 (可选，如果不指定则生成整个数据库)"
    echo "        jobDir:   生成的配置文件存放目录"
    echo ""
    echo "  run-job <jobJson> <runDate> [logDir] [Xms] [Xmx]"
    echo "        执行带日期参数的 DataX 任务"
    echo "        jobJson: Job JSON 配置文件路径"
    echo "        runDate: 日期参数，格式 yyyy-MM-dd，例如 2026-01-16"
    echo "        logDir:  日志目录 (可选)"
    echo "        Xms:     JVM 初始内存 (可选，默认: $DEFAULT_XMS)"
    echo "        Xmx:     JVM 最大内存 (可选，默认: $DEFAULT_XMX)"
    echo ""
    echo "  run-all-jobs <jobDir> <runDate> [logDir] [Xms] [Xmx]"
    echo "        执行目录下所有 DataX 任务"
    echo "        jobDir:  Job JSON 配置文件目录"
    echo "        runDate: 日期参数 (必填，格式 yyyy-MM-dd，所有任务都会使用该日期参数)"
    echo "        logDir:  日志目录 (可选，默认: $DEFAULT_LOG_DIR)"
    echo "        Xms:     JVM 初始内存 (可选，默认: $DEFAULT_XMS)"
    echo "        Xmx:     JVM 最大内存 (可选，默认: $DEFAULT_XMX)"
    echo ""
    echo "  help"
    echo "        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 start /path/to/job.json"
    echo "  $0 start /path/to/job.json /custom/log/dir 256m 512m"
    echo "  $0 run-job /path/to/job.json 2026-01-16"
    echo "  $0 run-job /path/to/job.json 2026-01-16 /custom/log/dir 256m 512m"
    echo "  $0 run-all-jobs /path/to/job/directory 2026-01-16"
    echo "  $0 run-all-jobs /path/to/job/directory 2026-01-16 /custom/log/dir 256m 512m"
    echo "  $0 generate jdbc:mysql://localhost:3306/test user pass test table1 /jobs/"
}

# 检查日期格式 (yyyy-MM-dd)
check_date_format() {
    local date_str=$1
    
    # 检查基本格式 YYYY-MM-DD
    if ! [[ $date_str =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        print_error "日期格式错误: $date_str, 请使用 yyyy-MM-dd 格式 (例如: 2026-01-16)"
        return 1
    fi
    
    # 使用 date 命令验证日期是否有效
    if ! date -d "$date_str" >/dev/null 2>&1; then
        print_error "无效日期: $date_str, 请输入正确的日期"
        return 1
    fi
    
    return 0
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

JOB_GEN_JAR="/opt/module/datax/datax-job-generator.jar"

print_info() { echo -e "[INFO] $*"; }
print_error() { echo -e "[ERROR] $*" >&2; exit 1; }

generate_job() {
    local jdbc_url=$1
    local db_user=$2
    local db_pass=$3
    local database=$4
    local tablename=$5
    local job_dir=$6

    # 参数校验
    [ -z "$jdbc_url" ] && print_error "JDBC URL 必需"
    [ -z "$db_user" ] && print_error "DB 用户名必需"
    [ -z "$db_pass" ] && print_error "DB 密码必需"
    [ -z "$database" ] && print_error "数据库名必需"

    # 判断是否提供了表名（通过检查第6个参数是否存在来判断）
    # 如果第6个参数存在，说明第5个参数是tablename，第6个是job_dir
    # 如果第6个参数不存在，说明第5个参数实际上是job_dir，tablename为空
    if [ -n "$job_dir" ]; then
        # 6个参数：指定了tablename
        [ -z "$job_dir" ] && print_error "Job 输出目录必需"
    else
        # 5个参数：没有指定tablename，第5个参数是job_dir
        job_dir=$5
        tablename=""
        [ -z "$job_dir" ] && print_error "Job 输出目录必需"
    fi

    # 检查输出目录是否存在文件
    if [ -d "$job_dir" ]; then
        # 检查目录是否包含任何文件
        if [ -n "$(ls -A "$job_dir" 2>/dev/null)" ]; then
            print_error "目标目录 $job_dir 中已存在文件，不能生成新的任务配置。请清理目录或选择其他目录。"
            exit 1
        fi
    fi
    
    # 创建输出目录
    mkdir -p "$job_dir"

    # 构建命令
    local cmd
    if [ -z "$tablename" ]; then
        # 全库生成
        cmd="java -jar $JOB_GEN_JAR $jdbc_url $db_user $db_pass $database $job_dir"
    else
        # 指定表生成
        cmd="java -jar $JOB_GEN_JAR $jdbc_url $db_user $db_pass $database $tablename $job_dir"
    fi

    print_info "执行生成命令: $cmd"
    eval "$cmd"
    local ret=$?
    if [ $ret -ne 0 ]; then
        print_error "生成 DataX job 失败，返回码 $ret"
    fi
    print_info "DataX job 生成完成: $job_dir"
}

# ----------------------------
# 执行单个 DataX Job（支持动态日期）
# 比如 ./datax-manager.sh run-job ~/datax-test/gmall.activity_info1.json 20260114
# ----------------------------
run_datax_job() {
    local job_json=$1      # 原始 job JSON 文件
    local run_date=$2      # 日期参数，格式 yyyy-MM-dd，例如 2026-01-16
    local log_dir=$3       # 可选日志目录
    local jvm_xms=$4       # 可选JVM初始内存
    local jvm_xmx=$5       # 可选JVM最大内存
    local python_bin=${6:-$PYTHON_BIN}  # Python二进制文件路径，可选
    
    # 设置默认值
    log_dir=${log_dir:-"$DEFAULT_LOG_DIR"}
    jvm_xms=${jvm_xms:-$DEFAULT_XMS}
    jvm_xmx=${jvm_xmx:-$DEFAULT_XMX}

    [ -z "$job_json" ] && print_error "请指定 Job JSON 文件"
    [ -z "$run_date" ] && print_error "请指定日期参数"

    # Validate date format
    if ! check_date_format "$run_date"; then
        exit 1
    fi

    # 检查 job JSON 文件
    if [ ! -f "$job_json" ]; then
        print_error "Job JSON 文件不存在: $job_json"
    fi

    # 创建日志目录
    mkdir -p "$log_dir"

    # 临时生成带日期的 job 文件
    local job_with_date="${job_json%.json}_${run_date}.json"
    cp "$job_json" "$job_with_date"

    # 替换路径中的 {date} 为实际日期（支持多种日期占位符格式）
    sed -i "s|\${date}|$run_date|g" "$job_with_date"
    sed -i "s|{date}|$run_date|g" "$job_with_date"
    sed -i "s|\${run_date}|$run_date|g" "$job_with_date"
    sed -i "s|{run_date}|$run_date|g" "$job_with_date"

    # 提取 HDFS 路径，假设 writer.path 一行中包含目标路径
    local hdfs_path
    hdfs_path=$(grep -Po '"path"\s*:\s*"\K[^"]+' "$job_with_date" | head -1)
    if [ -z "$hdfs_path" ]; then
        print_error "未找到 writer.path 路径"
    fi
    print_info "目标 HDFS 路径: $hdfs_path"

    # 检查 HDFS 路径是否存在，如果不存在则创建
    if ! hdfs dfs -test -d "$hdfs_path"; then
        print_info "HDFS 目录不存在，创建: $hdfs_path"
        hdfs dfs -mkdir -p "$hdfs_path"
    else
        print_info "HDFS 目录已存在"
    fi

    # 构建日志文件
    local log_file="$log_dir/datax_$(basename $job_json .json)_$run_date_$(date +%H%M%S).log"
    print_info "执行 DataX 任务: $job_with_date"
    print_info "日志文件: $log_file"
    print_info "JVM 内存设置: -Xms${jvm_xms} -Xmx${jvm_xmx}"

    # 执行 DataX，添加内存限制参数
    nohup "$python_bin" "$DATAX_HOME/bin/datax.py" -j "-Xms${jvm_xms} -Xmx${jvm_xmx}" "$job_with_date" > "$log_file" 2>&1 &

    local pid=$!
    echo $pid > "/tmp/datax_${run_date}.pid"
    print_info "DataX PID: $pid"
}


# ----------------------------
# 执行目录下所有 DataX Job
# 比如 ./datax-manager.sh run-all-jobs /path/to/job/directory runDate [logDir] [Xms] [Xmx]
# ----------------------------
run_all_datax_jobs() {
    local job_dir=$1         # Job JSON 文件所在目录
    local run_date=$2        # 日期参数
    local log_dir=$3         # 可选日志目录
    local jvm_xms=$4         # 可选JVM初始内存
    local jvm_xmx=$5         # 可选JVM最大内存
    
    # 设置默认值
    log_dir=${log_dir:-"$DEFAULT_LOG_DIR"}
    jvm_xms=${jvm_xms:-$DEFAULT_XMS}
    jvm_xmx=${jvm_xmx:-$DEFAULT_XMX}

    [ -z "$job_dir" ] && print_error "请指定 Job JSON 文件目录"
    [ -z "$run_date" ] && print_error "请指定运行日期参数"

    # 检查目录是否存在
    if [ ! -d "$job_dir" ]; then
        print_error "Job 目录不存在: $job_dir"
        exit 1
    fi

    # 检查 Python (only once for all jobs)
    check_python

    # 创建日志目录
    mkdir -p "$log_dir"

    print_info "正在扫描目录: $job_dir"
    
    # 定义处理单个 job 的函数
    process_single_job() {
        local job_file=$1
        local run_date=$2
        local log_dir=$3
        local jvm_xms=$4
        local jvm_xmx=$5
        
        print_info "发现 Job 文件: $(basename "$job_file")"
        
        # 总是使用带日期参数的执行方式 since run_date is required
        print_info "执行带日期参数的 DataX 任务: $job_file"
        run_datax_job "$job_file" "$run_date" "$log_dir" "$jvm_xms" "$jvm_xmx" "$PYTHON_BIN"
    }
    
    # 遍历目录下的所有 JSON 和 JOB 文件
    for job_file in "$job_dir"/*.json; do
        if [ -f "$job_file" ]; then
            process_single_job "$job_file" "$run_date" "$log_dir" "$jvm_xms" "$jvm_xmx"
        fi
    done
    
    for job_file in "$job_dir"/*.job; do
        if [ -f "$job_file" ]; then
            process_single_job "$job_file" "$run_date" "$log_dir" "$jvm_xms" "$jvm_xmx"
        fi
    done
    
    print_info "所有 Job 任务执行完毕"
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
            show_help
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
    generate)
        generate_job "$2" "$3" "$4" "$5" "$6" "$7"
        ;;
    run-job)
        if [ -z "$2" ]; then
            print_error "请指定 Job JSON 文件"
            show_help
            exit 1
        fi
        if [ -z "$3" ]; then
            print_error "请指定运行日期"
            show_help
            exit 1
        fi
        # Validate date format
        if ! check_date_format "$3"; then
            exit 1
        fi
        # Check python for standalone run-job command
        check_python
        run_datax_job "$2" "$3" "$4" "$5" "$6" "$PYTHON_BIN"
        ;;
    run-all-jobs)
        if [ -z "$2" ]; then
            print_error "请指定 Job JSON 文件目录"
            show_help
            exit 1
        fi
        if [ -z "$3" ]; then
            print_error "请指定运行日期参数"
            show_help
            exit 1
        fi
        # Validate date format
        if ! check_date_format "$3"; then
            exit 1
        fi
        run_all_datax_jobs "$2" "$3" "$4" "$5" "$6"
        ;;
    help|"")
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac