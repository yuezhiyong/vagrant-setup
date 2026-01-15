#!/bin/bash
# =========================================================
# Spark Manager Script
# Author: for production-like bigdata env
# =========================================================
set -euo pipefail

# Override SCRIPTS_BASE with the actual script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
export SCRIPTS_BASE

source $SCRIPTS_BASE/common/color.sh
source $SCRIPTS_BASE/common/common.sh

ACTION="${1:-}"

SPARK_VERSION="3.3.1"
SPARK_TAR="spark-${SPARK_VERSION}-bin-without-hadoop.tgz"

INSTALL_BASE="/opt/module"
SPARK_HOME="${INSTALL_BASE}/spark"
PID_DIR=$SPARK_HOME/run
LOG_DIR=$SPARK_HOME/logs

HADOOP_HOME="/opt/module/hadoop"
JAVA_HOME="/opt/module/java"

# ---------- check env ----------
check_env() {
    [ -d "$JAVA_HOME" ] || { print_error "JAVA_HOME 不存在"; exit 1; }
    [ -d "$HADOOP_HOME" ] || { print_error "HADOOP_HOME 不存在"; exit 1; }

    export JAVA_HOME
    export HADOOP_HOME
    export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$PATH
}

# ---------- install spark ----------
install_spark() {
    if [ -d "$SPARK_HOME" ]; then
        print_info "Spark 已安装: $SPARK_HOME"
        return
    fi

    if [ ! -f "$SPARK_TAR" ]; then
        print_error "未找到 $SPARK_TAR"
        exit 1
    fi

    print_info "安装 Spark ${SPARK_VERSION}"
    tar -zxvf "$SPARK_TAR" -C "$INSTALL_BASE" >/dev/null
    mv "${INSTALL_BASE}/spark-${SPARK_VERSION}-bin-without-hadoop" "$SPARK_HOME"

    mkdir -p "$LOG_DIR" "$PID_DIR"

    print_info "Spark 安装完成"
}

# ---------- configure spark ----------
configure_spark() {
    print_info "配置 Spark"

    # 创建配置目录
    mkdir -p "$SPARK_HOME/conf"

    # 创建 spark-env.sh
    cat > "$SPARK_HOME/conf/spark-env.sh" <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export SPARK_HOME=$SPARK_HOME
export SPARK_DIST_CLASSPATH=$(hadoop classpath)
export SPARK_MASTER_HOST=$(hostname)
export SPARK_WORKER_MEMORY=1g
export SPARK_WORKER_CORES=1
export LD_LIBRARY_PATH=$HADOOP_HOME/lib/native
export SPARK_DAEMON_JAVA_OPTS="-Djava.net.preferIPv4Stack=true"
EOF

    # 创建 spark-defaults.conf
    cat > "$SPARK_HOME/conf/spark-defaults.conf" <<EOF
spark.master                     spark://$(hostname):7077
spark.eventLog.enabled           true
spark.eventLog.dir               hdfs://$(hostname):9000/spark/eventLog
spark.serializer                 org.apache.spark.serializer.KryoSerializer
spark.sql.adaptive.enabled       true
spark.sql.adaptive.coalescePartitions.enabled  true
EOF

    # 创建 slaves/works 文件（根据集群配置）
    if [ -f "$SCRIPTS_BASE/common/config.sh" ]; then
        source "$SCRIPTS_BASE/common/config.sh"
        > "$SPARK_HOME/conf/workers"  # 清空文件
        for host in "${CLUSTER_HOSTS[@]}"; do
            echo "$host" >> "$SPARK_HOME/conf/workers"
        done
    else
        # 默认只在本地运行
        cat > "$SPARK_HOME/conf/workers" <<EOF
localhost
EOF
    fi

    print_info "Spark 配置完成"
}

# ---------- setup spark cluster ----------
setup_spark() {
    print_info "配置Spark集群环境..."
    
    # 检查Spark是否已安装
    if [ ! -d "$SPARK_HOME" ]; then
        print_error "Spark未安装，请先执行: $0 install"
        exit 1
    fi
    
    # 检查Hadoop是否已安装并设置环境变量
    if [ -z "$HADOOP_HOME" ] || [ ! -d "$HADOOP_HOME" ]; then
        export HADOOP_HOME="/opt/module/hadoop"
    fi
    
    if [ -z "$JAVA_HOME" ] || [ ! -d "$JAVA_HOME" ]; then
        export JAVA_HOME="/opt/module/java"
    fi
    
    # 创建必要目录
    mkdir -p "$SPARK_HOME/conf" "$SPARK_HOME/logs" "$SPARK_HOME/run"
    
    # 生成Spark配置文件
    configure_spark
    
    # ========== 导出环境变量到 ~/.bashrc ==========
    BASHRC="$HOME/.bashrc"
    NEED_UPDATE=false

    # 检查并添加SPARK_HOME环境变量
    if [ -f "$BASHRC" ]; then
        if ! grep -q "^export SPARK_HOME=" "$BASHRC" 2>/dev/null; then
            echo "" >> "$BASHRC"
            echo "# Spark环境变量" >> "$BASHRC"
            echo "export SPARK_HOME=$SPARK_HOME" >> "$BASHRC"
            NEED_UPDATE=true
        else
            # 如果已有SPARK_HOME定义，检查是否正确
            if ! grep -q "export SPARK_HOME=$SPARK_HOME" "$BASHRC" 2>/dev/null; then
                sed -i "s|^export SPARK_HOME=.*|export SPARK_HOME=$SPARK_HOME|g" "$BASHRC"
            fi
        fi

        # 检查并添加Spark到PATH
        if ! grep -q "SPARK_HOME/bin" "$BASHRC" 2>/dev/null; then
            echo 'export PATH="$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin"' >> "$BASHRC"
            NEED_UPDATE=true
        else
            # 检查现有PATH设置是否正确
            if ! grep -q "export PATH=.*\\$SPARK_HOME/bin" "$BASHRC" 2>/dev/null; then
                echo 'export PATH="$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin"' >> "$BASHRC"
                NEED_UPDATE=true
            fi
        fi
    else
        print_error "$BASHRC 文件不存在，创建该文件"
        touch "$BASHRC"
        echo "" >> "$BASHRC"
        echo "# Spark环境变量" >> "$BASHRC"
        echo "export SPARK_HOME=$SPARK_HOME" >> "$BASHRC"
        echo 'export PATH="$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin"' >> "$BASHRC"
        NEED_UPDATE=true
    fi

    if [ "$NEED_UPDATE" = true ]; then
        print_info "已将 Spark 环境变量写入 $BASHRC"
    else
        print_info "Spark 环境变量已在 $BASHRC 中存在"
    fi

    # 同时导出到当前 shell（供本脚本后续使用）
    export SPARK_HOME=$SPARK_HOME
    export PATH="$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin"

    print_info "Spark配置完成"
}

# ---------- start spark master ----------
start_master() {
    print_info "启动 Spark Master..."

    if [ -f "$PID_DIR/spark-master.pid" ]; then
        local pid=$(cat "$PID_DIR/spark-master.pid")
        if ps -p $pid > /dev/null 2>&1; then
            print_info "Spark Master 已运行 (PID: $pid)"
            return 0
        fi
    fi

    mkdir -p "$PID_DIR" "$LOG_DIR"

    nohup "$SPARK_HOME"/sbin/start-master.sh > "$LOG_DIR/spark-master.out" 2>&1 &
    MASTER_PID=$!
    echo $MASTER_PID > "$PID_DIR/spark-master.pid"

    sleep 3

    if ps -p $MASTER_PID > /dev/null 2>&1; then
        print_success "Spark Master 启动成功 (PID: $MASTER_PID)"
    else
        print_error "Spark Master 启动失败"
        rm -f "$PID_DIR/spark-master.pid"
        return 1
    fi
}

# ---------- start spark workers ----------
start_workers() {
    print_info "启动 Spark Workers..."

    "$SPARK_HOME"/sbin/start-workers.sh

    sleep 3
    print_info "Spark Workers 启动完成"
}

# ---------- start spark cluster ----------
start() {
    start_master
    start_workers
}

# ---------- stop spark master ----------
stop_master() {
    print_info "停止 Spark Master..."

    if [ -f "$PID_DIR/spark-master.pid" ]; then
        local pid=$(cat "$PID_DIR/spark-master.pid")
        if ps -p $pid > /dev/null 2>&1; then
            kill $pid
            rm -f "$PID_DIR/spark-master.pid"
            print_success "Spark Master 停止成功"
        else
            print_info "Spark Master 未运行"
            rm -f "$PID_DIR/spark-master.pid"
        fi
    else
        print_info "Spark Master 未运行"
    fi
}

# ---------- stop spark workers ----------
stop_workers() {
    print_info "停止 Spark Workers..."

    "$SPARK_HOME"/sbin/stop-workers.sh

    print_info "Spark Workers 停止完成"
}

# ---------- stop spark cluster ----------
stop() {
    stop_workers
    stop_master
}

# ---------- status ----------
status() {
    if [ -f "$PID_DIR/spark-master.pid" ]; then
        local pid=$(cat "$PID_DIR/spark-master.pid")
        if ps -p $pid > /dev/null 2>&1; then
            print_info "Spark Master 正在运行 (PID: $pid)"
        else
            print_info "Spark Master 未运行"
        fi
    else
        print_info "Spark Master 未运行"
    fi
}

# ---------- main ----------
case "$ACTION" in
    install)
        check_env
        install_spark
        configure_spark
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
    setup)
        setup_spark
        ;;
    "")
        echo "用法: $0 {install|start|stop|status|master-start|master-stop|worker-start|worker-stop|setup}"
        exit 1
        ;;
    *)
        echo "未知命令: $1"
        echo "用法: $0 {install|start|stop|status|master-start|master-stop|worker-start|worker-stop|setup}"
        exit 1
        ;;
esac