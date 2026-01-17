#!/bin/bash
# =========================================================
# Spark Manager Script (稳定版)
# 支持：安装 | 配置 | 启动 | 停止 | 状态
# Author: for production-like bigdata env
# =========================================================
set -euo pipefail

# ------------------ 基础路径 ------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
export SCRIPTS_BASE

source "$SCRIPTS_BASE/common/color.sh"
source "$SCRIPTS_BASE/common/common.sh"
source "$SCRIPTS_BASE/common/config.sh"

ACTION="${1:-}"

# ------------------ Spark 配置 ------------------
SPARK_VERSION="3.3.1"
SPARK_TAR="spark-${SPARK_VERSION}-bin-without-hadoop.tgz"
INSTALL_BASE="/opt/module"
SPARK_HOME="${INSTALL_BASE}/spark"
PID_DIR="$SPARK_HOME/run"
LOG_DIR="$SPARK_HOME/logs"

HADOOP_HOME="/opt/module/hadoop"
JAVA_HOME="/opt/module/java"

# ------------------ 检查环境 ------------------
check_env() {
    [ -d "$JAVA_HOME" ] || { print_error "JAVA_HOME 不存在"; exit 1; }
    [ -d "$HADOOP_HOME" ] || { print_error "HADOOP_HOME 不存在"; exit 1; }

    export JAVA_HOME
    export HADOOP_HOME
    export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$PATH"
}

# ------------------ 安装 Spark ------------------
install_spark() {
    if [ -d "$SPARK_HOME" ]; then
        print_info "Spark 已安装: $SPARK_HOME"
        return
    fi

    [ -f "$SPARK_TAR" ] || { print_error "未找到 $SPARK_TAR"; exit 1; }

    print_info "安装 Spark ${SPARK_VERSION}"
    tar -zxvf "$SPARK_TAR" -C "$INSTALL_BASE" >/dev/null
    mv "${INSTALL_BASE}/spark-${SPARK_VERSION}-bin-without-hadoop" "$SPARK_HOME"
    mkdir -p "$LOG_DIR" "$PID_DIR"

    print_info "Spark 安装完成"
}

# ------------------ 配置 Spark ------------------
configure_spark() {
    print_info "配置 Spark"

    mkdir -p "$SPARK_HOME/conf"

    # spark-env.sh
    cat > "$SPARK_HOME/conf/spark-env.sh" <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export SPARK_HOME=$SPARK_HOME
export SPARK_DIST_CLASSPATH=\$($HADOOP_HOME/bin/hadoop classpath)
export SPARK_MASTER_HOST=\$(hostname)
export SPARK_WORKER_MEMORY=1g
export SPARK_WORKER_CORES=1
export LD_LIBRARY_PATH=$HADOOP_HOME/lib/native
export SPARK_DAEMON_JAVA_OPTS="-Djava.net.preferIPv4Stack=true"
export YARN_CONF_DIR=$HADOOP_HOME/etc/hadoop
export SPARK_HISTORY_OPTS="-Dspark.history.ui.port=18080 -Dspark.history.retainedApplications=100 -Dspark.history.fs.logDirectory=hdfs://${MASTER_NODE}:8020/spark/eventLog"
EOF

    # spark-defaults.conf
    cat > "$SPARK_HOME/conf/spark-defaults.conf" <<EOF
spark.master                     spark://$(hostname):7077
spark.eventLog.enabled           true
spark.eventLog.dir               hdfs://$(hostname):8020/spark/eventLog
spark.serializer                 org.apache.spark.serializer.KryoSerializer
spark.sql.adaptive.enabled       true
spark.sql.adaptive.coalescePartitions.enabled  true
EOF

    # workers/slaves
    if [ -f "$SCRIPTS_BASE/common/config.sh" ]; then
        source "$SCRIPTS_BASE/common/config.sh"
        > "$SPARK_HOME/conf/workers"
        for host in "${CLUSTER_HOSTS[@]}"; do
            echo "$host" >> "$SPARK_HOME/conf/workers"
        done
    else
        echo "localhost" > "$SPARK_HOME/conf/workers"
    fi

    print_info "Spark 配置完成"
}

# ------------------ 设置集群 ------------------
setup_spark() {
    print_info "配置 Spark 集群环境..."
    [ -d "$SPARK_HOME" ] || { print_error "Spark未安装，请先执行: $0 install"; exit 1; }
    mkdir -p "$SPARK_HOME/conf" "$SPARK_HOME/logs" "$SPARK_HOME/run"
    configure_spark

    BASHRC="$HOME/.bashrc"
    grep -q "^export SPARK_HOME=" "$BASHRC" 2>/dev/null || echo "export SPARK_HOME=$SPARK_HOME" >> "$BASHRC"
    grep -q "\$SPARK_HOME/bin" "$BASHRC" 2>/dev/null || echo 'export PATH="$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin"' >> "$BASHRC"
    export SPARK_HOME
    export PATH="$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin"

    print_info "Spark 配置完成并导出环境变量"
}

# ------------------ 启动 Master ------------------
start_master() {
    print_info "启动 Spark Master..."
    mkdir -p "$LOG_DIR" "$PID_DIR"
    "$SPARK_HOME/sbin/start-master.sh" > "$LOG_DIR/spark-master.out" 2>&1
    sleep 5

    MASTER_PID_FILE=$(ls $SPARK_HOME/run/spark-*-org.apache.spark.deploy.master.Master-*.pid 2>/dev/null | head -n1)
    if [ -f "$MASTER_PID_FILE" ]; then
        MASTER_PID=$(cat "$MASTER_PID_FILE")
        if ps -p "$MASTER_PID" > /dev/null 2>&1; then
            print_success "Spark Master 启动成功 (PID: $MASTER_PID)"
        else
            print_error "Spark Master PID 文件存在，但进程未运行"
        fi
    else
        print_error "Spark Master 启动失败，PID 文件未生成"
    fi
}

# ------------------ 启动 Workers ------------------
start_workers() {
    print_info "启动 Spark Workers..."
    "$SPARK_HOME/sbin/start-workers.sh" > "$LOG_DIR/spark-workers.out" 2>&1
    sleep 5

    WORKER_PIDS=$(ls $SPARK_HOME/run/spark-*-org.apache.spark.deploy.worker.Worker-*.pid 2>/dev/null)
    if [ -n "$WORKER_PIDS" ]; then
        echo "$WORKER_PIDS" | while read pidfile; do
            pid=$(cat "$pidfile")
            if ps -p "$pid" > /dev/null 2>&1; then
                print_info "Worker PID $pid 正在运行"
            else
                print_error "Worker PID $pid 未运行"
            fi
        done
    else
        print_error "未检测到 Spark Worker PID 文件"
    fi
}

# ------------------ 启动集群 ------------------
start() {
    start_master
    start_workers
}

# ------------------ 停止 Master ------------------
stop_master() {
    print_info "停止 Spark Master..."
    "$SPARK_HOME/sbin/stop-master.sh"
}

# ------------------ 停止 Workers ------------------
stop_workers() {
    print_info "停止 Spark Workers..."
    "$SPARK_HOME/sbin/stop-workers.sh"
}

# ------------------ 停止集群 ------------------
stop() {
    stop_workers
    stop_master
}

# ------------------ 状态 ------------------
status() {
    MASTER_PID_FILE=$(ls $SPARK_HOME/run/spark-*-org.apache.spark.deploy.master.Master-*.pid 2>/dev/null | head -n1)
    if [ -f "$MASTER_PID_FILE" ]; then
        MASTER_PID=$(cat "$MASTER_PID_FILE")
        if ps -p "$MASTER_PID" > /dev/null 2>&1; then
            print_info "Spark Master 正在运行 (PID: $MASTER_PID)"
        else
            print_info "Spark Master 已停止"
        fi
    else
        print_info "Spark Master 未运行"
    fi

    WORKER_PIDS=$(ls $SPARK_HOME/run/spark-*-org.apache.spark.deploy.worker.Worker-*.pid 2>/dev/null)
    if [ -n "$WORKER_PIDS" ]; then
        echo "$WORKER_PIDS" | while read pidfile; do
            pid=$(cat "$pidfile")
            if ps -p "$pid" > /dev/null 2>&1; then
                print_info "Worker PID $pid 正在运行"
            else
                print_info "Worker PID $pid 已停止"
            fi
        done
    else
        print_info "Spark Worker 未运行"
    fi
}

# ------------------ 测试 Spark Pi ------------------
testSparkPi() {
    print_info "运行 Spark Pi 测试..."
    
    if [ ! -d "$SPARK_HOME" ]; then
        print_error "Spark 未安装"
        return 1
    fi
    
    # 检查 Spark Master 是否正在运行
    MASTER_PID_FILE=""
    for file in $SPARK_HOME/run/spark-*-org.apache.spark.deploy.master.Master-*.pid; do
        if [ -f "$file" ]; then
            MASTER_PID_FILE="$file"
            break
        fi
    done
    
    if [ -n "$MASTER_PID_FILE" ] && [ -f "$MASTER_PID_FILE" ]; then
        MASTER_PID=$(cat "$MASTER_PID_FILE")
        if ps -p "$MASTER_PID" > /dev/null 2>&1; then
            print_info "Spark Master 正在运行 (PID: $MASTER_PID)"
            print_info "使用集群模式运行 Pi 示例..."
            # 使用集群模式运行 Pi 示例
            $SPARK_HOME/bin/spark-submit \
                --class org.apache.spark.examples.SparkPi \
                --master spark://$(hostname):7077 \
                --total-executor-cores 2 \
                --executor-memory 512m \
                $SPARK_HOME/examples/jars/spark-examples_*.jar 10 2>&1
        else
            print_warning "Spark Master 未运行，将以本地模式运行 Pi 测试"
            print_info "使用本地模式运行 Pi 示例..."
            $SPARK_HOME/bin/spark-submit \
                --class org.apache.spark.examples.SparkPi \
                --master local[2] \
                $SPARK_HOME/examples/jars/spark-examples_*.jar 10 2>&1
        fi
    else
        print_warning "Spark Master 未运行，将以本地模式运行 Pi 测试"
        print_info "使用本地模式运行 Pi 示例..."
        $SPARK_HOME/bin/spark-submit \
            --class org.apache.spark.examples.SparkPi \
            --master local[2] \
            $SPARK_HOME/examples/jars/spark-examples_*.jar 10 2>&1
    fi
}

# ------------------ 主入口 ------------------
case "$ACTION" in
    install)
        check_env
        install_spark
        configure_spark
        ;;
    setup)
        setup_spark
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    master-start)
        start_master
        ;;
    master-stop)
        stop_master
        ;;
    worker-start)
        start_workers
        ;;
    worker-stop)
        stop_workers
        ;;
    test)
        testSparkPi
        ;;
    "")
        echo "用法: $0 {install|setup|start|stop|status|master-start|master-stop|worker-start|worker-stop|test}"
        echo ""
        echo "命令说明:"
        echo "  install         安装 Spark"
        echo "  setup           配置 Spark 集群环境"
        echo "  start           启动 Spark 集群 (Master + Workers)"
        echo "  stop            停止 Spark 集群 (Master + Workers)"
        echo "  status          查看 Spark 集群状态"
        echo "  master-start    启动 Spark Master"
        echo "  master-stop     停止 Spark Master"
        echo "  worker-start    启动 Spark Workers"
        echo "  worker-stop     停止 Spark Workers"
        echo "  test            运行 Spark Pi 测试 (验证安装)"
        exit 1
        ;;
    *)
        echo "未知命令: $1"
        echo "用法: $0 {install|setup|start|stop|status|master-start|master-stop|worker-start|worker-stop|test}"
        exit 1
        ;;
esac
