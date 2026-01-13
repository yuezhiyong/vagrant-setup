#!/bin/bash
# =========================================================
# Hive Manager Script
# Author: for production-like bigdata env
# =========================================================

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

MYSQL_HOST="centos-201"
MYSQL_PORT="3306"
MYSQL_DB="hive"
MYSQL_USER="hive"
MYSQL_PASS="hive"

LOG_DIR="${HIVE_HOME}/logs"
PID_FILE="/tmp/hive-metastore.pid"

print_info() {
    echo -e "[INFO] $*"
}

print_error() {
    echo -e "[ERROR] $*" >&2
}

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
    <value>jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DB}?createDatabaseIfNotExist=true&amp;useSSL=false&amp;serverTimezone=Asia/Shanghai</value>
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

</configuration>
EOF

    print_info "hive-site.xml 已生成"
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

# ---------- status ----------
status_metastore() {
    if [ -f "$PID_FILE" ] && ps -p "$(cat $PID_FILE)" >/dev/null; then
        print_info "Metastore 正在运行"
    else
        print_info "Metastore 未运行"
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
        print_warn "mysql命令未找到，将跳过数据库连接测试"
    else
        if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "USE $MYSQL_DB;" &> /dev/null; then
            print_info "MySQL连接正常"
        else
            print_warn "无法连接到MySQL数据库，Hive元数据存储可能无法工作"
        fi
    fi
    
    # 生成hive-site.xml配置文件
    configure_hive
    
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

    print_info "Hive配置完成"
}

# ---------- main ----------
case "$1" in
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
    stop)
        stop_metastore
        ;;
    status)
        status_metastore
        ;;
    setup)
        setup_hive
        ;;
    *)
        echo "用法: $0 {install|init|start|stop|status|setup}"
        ;;
esac
