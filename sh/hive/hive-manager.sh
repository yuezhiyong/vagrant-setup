#!/bin/bash
# =========================================================
# Hive Manager Script
# Author: for production-like bigdata env
# =========================================================
set -euo pipefail
# Override SCRIPTS_BASE with the actual script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
export SCRIPTS_BASE
echo "SCRIPTS_BASE: $SCRIPTS_BASE"

source $SCRIPTS_BASE/common/color.sh
source $SCRIPTS_BASE/common/common.sh
source $SCRIPTS_BASE/common/config.sh

ACTION="${1:-}"

HIVE_VERSION="3.1.3"
HIVE_TAR="hive-${HIVE_VERSION}.tar.gz"

INSTALL_BASE="/opt/module"
HIVE_HOME="${INSTALL_BASE}/hive"
PID_DIR=$HIVE_HOME/run
LOG_DIR=$HIVE_HOME/logs
HIVE_BIN=$HIVE_HOME/bin/hive

PID_FILE=$PID_DIR/hive-metastore.pid
HADOOP_HOME="/opt/module/hadoop"
JAVA_HOME="/opt/module/java"

MYSQL_HOST="centos-101"
MYSQL_PORT="3306"
MYSQL_DB="hive"
MYSQL_USER="root"
MYSQL_PASS="000000"

LOG_DIR="${HIVE_HOME}/logs"
PID_FILE="/tmp/hive-metastore.pid"


# ---------- check env ----------
check_env() {
    [ -d "$JAVA_HOME" ] || { print_error "JAVA_HOME 不存在"; exit 1; }
    [ -d "$HADOOP_HOME" ] || { print_error "HADOOP_HOME 不存在"; exit 1; }

    export JAVA_HOME
    export HADOOP_HOME
    export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$PATH
}

is_metastore_running() {
    if [ ! -f "$PID_FILE" ]; then
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if [ -z "$pid" ]; then
        return 1
    fi

    # PID 是否存在
    if ! ps -p "$pid" > /dev/null 2>&1; then
        return 1
    fi

    # 是否是 Hive Metastore 进程
    ps -p "$pid" -o cmd= | grep -q "HiveMetaStore"
}

# ---------- install hive ----------
install_hive() {
    if [ -d "$HIVE_HOME" ]; then
        print_info "Hive 已安装: $HIVE_HOME"
        return
    fi

    if [ ! -f "$HIVE_TAR" ]; then
        print_error "未找到 $HIVE_TAR"
        exit 1
    fi

    print_info "安装 Hive ${HIVE_VERSION}"
    tar -zxvf "$HIVE_TAR" -C "$INSTALL_BASE" >/dev/null
    mv "${INSTALL_BASE}/apache-hive-${HIVE_VERSION}-bin" "$HIVE_HOME"

    mkdir -p "$LOG_DIR"

    print_info "Hive 安装完成"
}

# ---------- configure hive ----------
configure_hive() {
    print_info "配置 hive-site.xml"

    cat > "$HIVE_HOME/conf/hive-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>

  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DB}?createDatabaseIfNotExist=true&amp;useSSL=false&amp;serverTimezone=Asia/Shanghai&amp;allowPublicKeyRetrieval=true</value>
  </property>

  <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>com.mysql.cj.jdbc.Driver</value>
  </property>

  <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>${MYSQL_USER}</value>
  </property>

  <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>${MYSQL_PASS}</value>
  </property>

  <property>
    <name>hive.metastore.warehouse.dir</name>
    <value>/user/hive/warehouse</value>
  </property>

  <property>
    <name>hive.metastore.schema.verification</name>
    <value>false</value>
  </property>

  <property>
    <name>hive.exec.dynamic.partition</name>
    <value>true</value>
  </property>

  <property>
    <name>hive.exec.dynamic.partition.mode</name>
    <value>nonstrict</value>
  </property>

  <property>
    <name>hive.server2.thrift.bind.host</name>
    <value>0.0.0.0</value>
  </property>

  <property>
    <name>hive.server2.thrift.port</name>
    <value>10000</value>
  </property>

</configuration>
EOF

    print_info "hive-site.xml 已生成"
}

# ---------- configure spark integration ----------
configure_spark_integration() {
    print_info "配置 Hive Spark 集成..."
    
    # 检查 Spark 是否已安装
    if [ -d "/opt/module/spark" ]; then
        SPARK_HOME="/opt/module/spark"
    else
        # 尝试查找其他可能的 Spark 安装路径
        SPARK_HOME=$(ls -rd /opt/module/spark* 2>/dev/null | head -n 1)
        if [ -z "$SPARK_HOME" ]; then
            print_warning "未找到 Spark 安装，跳过 Spark 集成配置"
            return 0
        fi
    fi
    
    print_info "使用 SPARK_HOME: $SPARK_HOME"
    
    # 更新 hive-site.xml 以启用 Spark 引擎
    local temp_hive_site="$HIVE_HOME/conf/hive-site.xml.tmp"
    
    # 首先复制现有配置
    cp "$HIVE_HOME/conf/hive-site.xml" "$temp_hive_site"
    
    # 检查是否已经存在 spark 相关配置
    if ! grep -q "hive.execution.engine" "$temp_hive_site"; then
        # 删除现有的 </configuration> 标签，添加新的配置，最后再加上 </configuration> 标签
        sed -i '/<\/configuration>/d' "$temp_hive_site"
        # 添加 Spark 相关配置
        cat >> "$temp_hive_site" << EOF
  <property>
    <name>hive.execution.engine</name>
    <value>spark</value>
    <description>使用 Spark 作为执行引擎</description>
  </property>
  <property>
    <name>spark.home</name>
    <value>$SPARK_HOME</value>
    <description>Spark 安装路径</description>
  </property>
  <property>
    <name>spark.sql.warehouse.dir</name>
    <value>/user/hive/warehouse</value>
    <description>Spark SQL warehouse 目录</description>
  </property>
  <property>
    <name>spark.yarn.jars</name>
    <value>${SPARK_YARN_JAR:-$SPARK_HOME/jars/*}</value>
    <description>Spark YARN jars 路径</description>
  </property>
  <!-- Hive on Spark 必配 -->
  <property>
    <name>hive.spark.client.connect.timeout</name>
    <value>10000ms</value>
  </property>
  <property>
    <name>hive.spark.client.server.connect.timeout</name>
    <value>30000ms</value>
  </property>
  <property>
    <name>hive.spark.client.rpc.threads</name>
    <value>5</value>
  </property>
</configuration>
EOF
    else
        # 如果已有配置，更新 Spark 相关配置
        sed -i "s|<value>.*</value>|<value>$SPARK_HOME</value>|g" "$temp_hive_site"
        # 确保 spark.yarn.jars 属性存在
        if ! grep -q "spark.yarn.jars" "$temp_hive_site"; then
            # 删除现有的 </configuration> 标签，添加新的配置，最后再加上 </configuration> 标签
            sed -i '/<\/configuration>/d' "$temp_hive_site"
            # 添加 spark.yarn.jars 配置
            cat >> "$temp_hive_site" << EOF
  <property>
    <name>spark.yarn.jars</name>
    <value>${SPARK_YARN_JAR:-$SPARK_HOME/jars/*}</value>
    <description>Spark YARN jars 路径</description>
  </property>
  <!-- Hive on Spark 必配 -->
  <property>
    <name>hive.spark.client.connect.timeout</name>
    <value>10000ms</value>
  </property>
  <property>
    <name>hive.spark.client.server.connect.timeout</name>
    <value>30000ms</value>
  </property>
  <property>
    <name>hive.spark.client.rpc.threads</name>
    <value>5</value>
  </property>
</configuration>
EOF
        else
            # 检查是否已包含 Hive on Spark 必需配置
            if ! grep -q "hive.spark.client.connect.timeout" "$temp_hive_site"; then
                # 删除现有的 </configuration> 标签，添加新的配置，最后再加上 </configuration> 标签
                sed -i '/<\/configuration>/d' "$temp_hive_site"
                # 添加 Hive on Spark 必需配置
                cat >> "$temp_hive_site" << EOF
  <!-- Hive on Spark 必配 -->
  <property>
    <name>hive.spark.client.connect.timeout</name>
    <value>120000ms</value>
  </property>
  <property>
    <name>hive.spark.client.server.connect.timeout</name>
    <value>120000ms</value>
  </property>
  <property>
    <name>hive.spark.client.rpc.threads</name>
    <value>5</value>
  </property>
</configuration>
EOF
            fi
        fi
    fi
    
    # 替换原来的配置文件
    mv "$temp_hive_site" "$HIVE_HOME/conf/hive-site.xml"
    
    # 检查 spark-defaults.conf 文件是否存在，如果不存在则创建它
    if [ ! -f "$SPARK_HOME/conf/spark-defaults.conf" ]; then
        print_info "创建 spark-defaults.conf 配置文件..."
        
        # 创建 spark-defaults.conf 文件
        cat > "$SPARK_HOME/conf/spark-defaults.conf" << EOF
spark.master                    yarn
spark.eventLog.enabled          true
spark.eventLog.dir              hdfs://$(hostname):8020/spark/eventLog
spark.serializer                org.apache.spark.serializer.KryoSerializer
spark.sql.adaptive.enabled      true
spark.sql.adaptive.coalescePartitions.enabled  true
spark.driver.extraClassPath     $HADOOP_HOME/share/hadoop/tools/lib/*:$HIVE_HOME/lib/*
spark.executor.extraClassPath   $HADOOP_HOME/share/hadoop/tools/lib/*:$HIVE_HOME/lib/*
EOF
        
        print_info "spark-defaults.conf 已创建"
    else
        print_info "检测到 spark-defaults.conf，配置 Spark 依赖路径..."
    fi
    
    # 如果 Spark 的 spark-defaults.conf 存在，将其复制到 Hive 的 conf 目录下
    if [ -f "$SPARK_HOME/conf/spark-defaults.conf" ]; then
        print_info "复制 spark-defaults.conf 到 Hive 配置目录..."
        cp "$SPARK_HOME/conf/spark-defaults.conf" "$HIVE_HOME/conf/spark-defaults.conf"
        print_info "spark-defaults.conf 已复制到 Hive 配置目录"
    fi
    
    # 创建或更新 hive-exec-log4j2.properties 以包含 Spark 依赖
    if [ ! -f "$HIVE_HOME/conf/hive-exec-log4j2.properties" ]; then
        cp "$HIVE_HOME/conf/hive-log4j2.properties" "$HIVE_HOME/conf/hive-exec-log4j2.properties"
    fi
    
    print_info "Hive Spark 集成配置完成"
}

# ---------- init metastore ----------
init_metastore() {
    print_info "初始化 Hive Metastore"

    export HADOOP_HOME
    export JAVA_HOME
    export HIVE_HOME
    export PATH=$HIVE_HOME/bin:$PATH

    schematool -dbType mysql -initSchema
}

# ---------- start metastore ----------
start_metastore() {
    mkdir -p "$PID_DIR" "$LOG_DIR"

    if is_metastore_running; then
        echo "[INFO] Metastore 已运行 (PID=$(cat $PID_FILE))"
        return 0
    fi

    echo "[INFO] 启动 Hive Metastore..."

    nohup "$HIVE_BIN" --service metastore \
        > "$LOG_DIR/metastore.log" 2>&1 &

    echo $! > "$PID_FILE"

    sleep 5

    if is_metastore_running; then
        echo "[INFO] Metastore 启动成功 (PID=$(cat $PID_FILE))"
    else
        echo "[ERROR] Metastore 启动失败"
        rm -f "$PID_FILE"
        exit 1
    fi
}

# ---------- start hiveserver ----------
start_hiveserver() {
    mkdir -p "$PID_DIR" "$LOG_DIR"
    
    local hiveserver_pid_file="$PID_DIR/hiveserver2.pid"
    
    if [ -f "$hiveserver_pid_file" ] && ps -p $(cat "$hiveserver_pid_file") > /dev/null 2>&1; then
        print_info "HiveServer2 已运行 (PID=$(cat $hiveserver_pid_file))"
        return 0
    fi
    
    print_info "启动 HiveServer2..."
    
    nohup "$HIVE_BIN" --service hiveserver2 \
        > "$LOG_DIR/hiveserver2.log" 2>&1 &
    
    echo $! > "$hiveserver_pid_file"
    
    sleep 8
    
    if [ -f "$hiveserver_pid_file" ] && ps -p $(cat "$hiveserver_pid_file") > /dev/null 2>&1; then
        print_info "HiveServer2 启动成功 (PID=$(cat $hiveserver_pid_file))"
    else
        print_error "HiveServer2 启动失败"
        rm -f "$hiveserver_pid_file"
        exit 1
    fi
}

# ---------- stop metastore ----------
stop_metastore() {
    if ! is_metastore_running; then
        echo "[INFO] Metastore 未运行"
        rm -f "$PID_FILE"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")

    echo "[INFO] 停止 Metastore (PID=$pid)..."
    kill "$pid"

    for i in {1..10}; do
        if ! ps -p "$pid" > /dev/null; then
            rm -f "$PID_FILE"
            echo "[INFO] Metastore 已停止"
            return 0
        fi
        sleep 1
    done

    echo "[WARN] 正常停止失败，强制 kill"
    kill -9 "$pid"
    rm -f "$PID_FILE"
}

# ---------- stop hiveserver ----------
stop_hiveserver() {
    local hiveserver_pid_file="$PID_DIR/hiveserver2.pid"
    
    if [ ! -f "$hiveserver_pid_file" ]; then
        print_info "HiveServer2 未运行"
        return 0
    fi
    
    local pid
    pid=$(cat "$hiveserver_pid_file")
    
    if ! ps -p "$pid" > /dev/null 2>&1; then
        print_info "HiveServer2 未运行"
        rm -f "$hiveserver_pid_file"
        return 0
    fi
    
    print_info "停止 HiveServer2 (PID=$pid)..."
    kill "$pid"
    
    for i in {1..10}; do
        if ! ps -p "$pid" > /dev/null 2>&1; then
            rm -f "$hiveserver_pid_file"
            print_info "HiveServer2 已停止"
            return 0
        fi
        sleep 1
    done
    
    print_warning "正常停止失败，强制 kill"
    kill -9 "$pid"
    rm -f "$hiveserver_pid_file"
}

# ---------- restart metastore ----------
restart_metastore() {
    print_info "重启 Metastore..."
    stop_metastore
    sleep 3
    start_metastore
}

# ---------- restart hiveserver ----------
restart_hiveserver() {
    print_info "重启 HiveServer2..."
    stop_hiveserver
    sleep 3
    start_hiveserver
}

# ---------- status ----------
status_metastore() {
    if [ -f "$PID_FILE" ] && ps -p "$(cat $PID_FILE)" >/dev/null; then
        print_info "Metastore 正在运行"
    else
        print_info "Metastore 未运行"
    fi
}

# ---------- status hiveserver ----------
status_hiveserver() {
    local hiveserver_pid_file="$PID_DIR/hiveserver2.pid"
    
    if [ -f "$hiveserver_pid_file" ] && ps -p $(cat "$hiveserver_pid_file") > /dev/null 2>&1; then
        print_info "HiveServer2 正在运行 (PID=$(cat $hiveserver_pid_file))"
    else
        print_info "HiveServer2 未运行"
    fi
}

# ---------- setup hive cluster ----------
setup_hive() {
    print_info "配置Hive集群环境..."
    
    # 检查Hive是否已安装
    if [ ! -d "$HIVE_HOME" ]; then
        print_error "Hive未安装，请先执行: $0 install"
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
    mkdir -p "$HIVE_HOME/conf" "$HIVE_HOME/logs" "$HIVE_HOME/run"
    
    # 检查MySQL连接
    print_info "检查MySQL连接..."
    if ! command -v mysql &> /dev/null; then
        print_warning "mysql命令未找到，将跳过数据库连接测试"
    else
        if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "USE $MYSQL_DB;" &> /dev/null; then
            print_info "MySQL连接正常"
        else
            print_warning "无法连接到MySQL数据库，Hive元数据存储可能无法工作"
        fi
    fi
    
    # 生成hive-site.xml配置文件
    configure_hive
    
    # 配置 Hive 以使用 Spark 作为执行引擎
    configure_spark_integration
    
    # 创建hive-env.sh
    cat > "$HIVE_HOME/conf/hive-env.sh" <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export HIVE_HOME=$HIVE_HOME
EOF

    # 创建hive-log4j2.properties
    cat > "$HIVE_HOME/conf/hive-log4j2.properties" <<EOF
status = INFO
name = HiveLog4j2
packages = org.apache.hadoop.hive.ql.log

# Property used to enable log file rotation
rootLogger.level = INFO
rootLogger.appenderRef = console

appender.console.type = Console
appender.console.name = console
appender.console.target = SYSTEM_ERR
appender.console.layout.type = PatternLayout
appender.console.layout.pattern = %d{yy/MM/dd HH:mm:ss} [%t]: %p %c{2}: %m%n
EOF
    # ========== 导出环境变量到 ~/.bashrc ==========
    BASHRC="$HOME/.bashrc"
    NEED_UPDATE=false

    if ! grep -q "^export HIVE_HOME=" "$BASHRC" 2>/dev/null; then
        echo "export HIVE_HOME=$HIVE_HOME" >> "$BASHRC"
        NEED_UPDATE=true
    fi

    if ! grep -q 'PATH.*\$HIVE_HOME/bin' "$BASHRC" 2>/dev/null; then
        echo 'export PATH="$HIVE_HOME/bin:$PATH"' >> "$BASHRC"
        NEED_UPDATE=true
    fi

    if [ "$NEED_UPDATE" = true ]; then
        print_info "已将 Hive 环境变量写入 $BASHRC"
    fi

    # 同时导出到当前 shell（供本脚本后续使用）
    export HIVE_HOME
    export PATH="$HIVE_HOME/bin:$PATH"

    print_info "Hive配置完成"
}

# ---------- main ----------
case "$ACTION" in
    install)
        check_env
        install_hive
        configure_hive
        ;;
    init)
        check_env
        init_metastore
        ;;
    start)
        start_metastore
        ;;
    start-hiveserver)
        start_hiveserver
        ;;
    stop)
        stop_metastore
        ;;
    stop-hiveserver)
        stop_hiveserver
        ;;
    restart)
        restart_metastore
        ;;
    restart-hiveserver)
        restart_hiveserver
        ;;
    status)
        status_metastore
        ;;
    status-hiveserver)
        status_hiveserver
        ;;
    setup)
        setup_hive
        ;;
    "")
        echo "用法: $0 {install|init|start|start-hiveserver|stop|stop-hiveserver|restart|restart-hiveserver|status|status-hiveserver|setup}"
        exit 1
        ;;
    *)
        echo "未知命令: $1"
        echo "用法: $0 {install|init|start|start-hiveserver|stop|stop-hiveserver|restart|restart-hiveserver|status|status-hiveserver|setup}"
        exit 1
        ;;
esac