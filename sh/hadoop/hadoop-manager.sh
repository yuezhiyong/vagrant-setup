#!/bin/bash
# ============================================
# Hadoop 3.x 集群管理脚本（官方方式）
# ============================================
set -euo pipefail
# Override SCRIPTS_BASE with the actual script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
export SCRIPTS_BASE
echo "SCRIPTS_BASE: $SCRIPTS_BASE"

source $SCRIPTS_BASE/common/color.sh
source $SCRIPTS_BASE/common/common.sh
source $SCRIPTS_BASE/common/config.sh


HDFS_RPC_PORT=8020
HDFS_HTTP_PORT=9870
YARN_RM_PORT=8088

CMD=${1:-}
SUBCMD=${2:-}

# ---------- 工具函数 ----------

check_port() {
    local host=$1
    local port=$2
    run_on_host "$host" "nc -z localhost $port >/dev/null 2>&1"
}

is_cluster_formatted() {
    # 检查 NameNode 是否已经格式化
    # 在 Hadoop 3.x 中，格式化的集群会在 NameNode 数据目录下创建 VERSION 文件
    local hadoop_tmp_dir="$MODULE_BASE/hadoop/data"
    local name_node_dir="${hadoop_tmp_dir}/current"
    
    # 尝试检查 Master 节点上的 NameNode 目录是否存在 VERSION 文件
    if run_on_host "$MASTER_NODE" "test -f \"$name_node_dir/data/dfs/name/current/VERSION\" 2>/dev/null"; then
        return 0  # 返回 0 表示已格式化
    else
        return 1  # 返回 1 表示未格式化
    fi
}

# ---------- HDFS ----------

format_namenode() {
    local auto_confirm=$1
    
    if [ "$auto_confirm" != "force" ]; then
        print_warning "⚠️ 即将格式化 NameNode（清空 HDFS 数据）"
        read -p "确认格式化？(y/n): " confirm
        [ "$confirm" = "y" ] || return 1
    fi

    run_on_host "$MASTER_NODE" \
        "export HDFS_NAMENODE_USER=$HDFS_NAMENODE_USER && export HDFS_DATANODE_USER=$HDFS_DATANODE_USER && export HDFS_SECONDARYNAMENODE_USER=$HDFS_SECONDARYNAMENODE_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/bin/hdfs namenode -format -force"
}

start_hdfs() {
    print_step "启动 HDFS (Hadoop 3.x)"
    
    # 检查集群是否已经格式化，如果未格式化且没有传递 format 参数，则提示用户
    if ! is_cluster_formatted && [ "$1" != "format" ]; then
        print_warning "⚠️ 警告：Hadoop 集群尚未格式化！"
        print_warning "⚠️ 如果这是第一次启动，请先运行 '$0 format' 或 '$0 start format' 来格式化集群。"
        print_warning "⚠️ 否则集群可能无法正常启动。"
        read -p "您确定要继续启动吗？(y/N): " confirm
        [ "$confirm" = "y" ] || return 1
    fi

    if [ "$1" = "format" ]; then
        format_namenode "force"
    fi

    print_info "执行 start-dfs.sh"
    run_on_host "$MASTER_NODE" "export HDFS_NAMENODE_USER=$HDFS_NAMENODE_USER && export HDFS_DATANODE_USER=$HDFS_DATANODE_USER && export HDFS_SECONDARYNAMENODE_USER=$HDFS_SECONDARYNAMENODE_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/sbin/start-dfs.sh"

    sleep 5
}

stop_hdfs() {
    print_step "停止 HDFS"
    run_on_host "$MASTER_NODE" "export HDFS_NAMENODE_USER=$HDFS_NAMENODE_USER && export HDFS_DATANODE_USER=$HDFS_DATANODE_USER && export HDFS_SECONDARYNAMENODE_USER=$HDFS_SECONDARYNAMENODE_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/sbin/stop-dfs.sh"
}

# ---------- YARN ----------

start_yarn() {
    print_step "启动 YARN 按角色分发"

    # 确保 yarn-site.xml 中 yarn.resourcemanager.hostname 已设置正确
    # MASTER_NODE 可以是 NameNode，这里假设 RESOURCE_MANAGER_NODE 单独指定
    # NODEMANAGER_NODES 是需要启动 NodeManager 的节点列表（可是所有节点也可以启动 NM）

    RESOURCE_MANAGER_NODE=${YARN_NODE:-"centos-102"}

    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "在 $host 启动 YARN 服务..."
        if [ "$host" = "$RESOURCE_MANAGER_NODE" ]; then
            # 启动 ResourceManager
            run_on_host "$host" "export YARN_RESOURCEMANAGER_USER=$YARN_RESOURCEMANAGER_USER && export YARN_NODEMANAGER_USER=$YARN_NODEMANAGER_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/sbin/yarn-daemon.sh start resourcemanager"
            print_success "$host: ResourceManager 已启动"
        fi

        # 启动 NodeManager
        run_on_host "$host" "export YARN_RESOURCEMANAGER_USER=$YARN_RESOURCEMANAGER_USER && export YARN_NODEMANAGER_USER=$YARN_NODEMANAGER_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/sbin/yarn-daemon.sh start nodemanager"
        print_success "$host: NodeManager 已启动"

        sleep 1
    done

    print_success "YARN 集群启动完成"

    # 可选：检查 YARN 状态
    check_yarn_status
}

stop_yarn() {
    print_step "停止 YARN 按角色分发"

    RESOURCE_MANAGER_NODE=${YARN_NODE:-"centos-102"}

    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "停止 $host 的 NodeManager..."
        run_on_host "$host" "export YARN_RESOURCEMANAGER_USER=$YARN_RESOURCEMANAGER_USER && export YARN_NODEMANAGER_USER=$YARN_NODEMANAGER_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/sbin/yarn-daemon.sh stop nodemanager" || true

        if [ "$host" = "$RESOURCE_MANAGER_NODE" ]; then
            print_info "停止 $host 的 ResourceManager..."
            run_on_host "$host" "export YARN_RESOURCEMANAGER_USER=$YARN_RESOURCEMANAGER_USER && export YARN_NODEMANAGER_USER=$YARN_NODEMANAGER_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/sbin/yarn-daemon.sh stop resourcemanager" || true
        fi

        sleep 1
    done

    print_success "YARN 集群已停止"
}

# ---------- JobHistory Server ----------

start_historyserver() {
    print_step "启动 MapReduce JobHistory Server"
    
    run_on_host "$MASTER_NODE" "export HADOOP_MAPRED_HOME=$HADOOP_HOME && export HADOOP_COMMON_HOME=$HADOOP_HOME && export HADOOP_HDFS_HOME=$HADOOP_HOME && export HADOOP_YARN_HOME=$HADOOP_HOME && export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop && export HADOOP_USER_CLASSPATH_FIRST=true && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/sbin/mr-jobhistory-daemon.sh start historyserver"
    
    sleep 3
    
    # 检查 History Server 是否成功启动
    if run_on_host "$MASTER_NODE" "ps aux | grep -v grep | grep historyserver >/dev/null 2>&1"; then
        print_success "MapReduce JobHistory Server 启动成功"
        print_info "访问地址: http://$MASTER_NODE:19888"
    else
        print_error "MapReduce JobHistory Server 启动失败"
        return 1
    fi
}

stop_historyserver() {
    print_step "停止 MapReduce JobHistory Server"
    
    run_on_host "$MASTER_NODE" "export HADOOP_MAPRED_HOME=$HADOOP_HOME && export HADOOP_COMMON_HOME=$HADOOP_HOME && export HADOOP_HDFS_HOME=$HADOOP_HOME && export HADOOP_YARN_HOME=$HADOOP_HOME && export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop && export HADOOP_USER_CLASSPATH_FIRST=true && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/sbin/mr-jobhistory-daemon.sh stop historyserver"
    
    sleep 2
    
    print_success "MapReduce JobHistory Server 已停止"
}

# ---------- 状态检查 ----------

check_hdfs_status() {
    print_step "HDFS 状态（官方方式）"

    if is_hdfs_available; then
        print_success "HDFS: 可用（NameNode + DataNode 正常）"
    else
        print_error "HDFS: 不可用（NameNode 未就绪）"
        return
    fi

    print_info "DataNode 状态:"
    run_on_host "$MASTER_NODE" \
        "export HDFS_NAMENODE_USER=$HDFS_NAMENODE_USER && export HDFS_DATANODE_USER=$HDFS_DATANODE_USER && export HDFS_SECONDARYNAMENODE_USER=$HDFS_SECONDARYNAMENODE_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/bin/hdfs dfsadmin -report" | \
        awk '
        /Live datanodes/ {print}
        /Hostname:/ {host=$2}
        /Datanode UUID/ {print "  - " host ": UP"}
        '
}

check_yarn_status() {
    print_step "YARN 状态（安全判活）"

    if run_on_host "$YARN_NODE" \
        "export YARN_RESOURCEMANAGER_USER=$YARN_RESOURCEMANAGER_USER && export YARN_NODEMANAGER_USER=$YARN_NODEMANAGER_USER && export HADOOP_ALLOW_ROOT=true && timeout 5s $HADOOP_HOME/bin/yarn node -list >/dev/null 2>&1"; then
        print_success "YARN: 可用"
        run_on_host "$YARN_NODE" \
            "export YARN_RESOURCEMANAGER_USER=$YARN_RESOURCEMANAGER_USER && export YARN_NODEMANAGER_USER=$YARN_NODEMANAGER_USER && export HADOOP_ALLOW_ROOT=true && timeout 5s $HADOOP_HOME/bin/yarn node -list"
    else
        print_error "YARN: 不可用（RM 未就绪或连接超时）"
    fi
}

check_all_status() {
    check_hdfs_status
    echo ""
    check_yarn_status
}

setup_hadoop() {
    print_step "配置Hadoop集群"
    
    # 创建必要的配置文件
    local hadoop_conf_dir="$HADOOP_HOME/etc/hadoop"
    
    # 创建core-site.xml
    local core_site_conf=$(cat << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!-- Put site-specific property overrides in this file. -->

<configuration>
        <property>
                <name>fs.defaultFS</name>
                <value>hdfs://$MASTER_NODE:8020</value>
        </property>
        <property>
                <name>hadoop.tmp.dir</name>
                <value>$MODULE_BASE/hadoop/data</value>
        </property>
        <property>
                <name>hadoop.http.staticuser.user</name>
                <value>vagrant</value>
        </property>
        <property>
                <name>hadoop.proxyuser.vagrant.hosts</name>
                <value>*</value>
        </property>
        <property>
                <name>hadoop.proxyuser.vagrant.groups</name>
                <value>*</value>
        </property>
        <property>
                <name>hadoop.proxyuser.vagrant.users</name>
                <value>*</value>
        </property>
        <property>
                <name>hadoop.security.authorization</name>
                <value>false</value>
        </property>
</configuration>
EOF
)
    
    # 创建hdfs-site.xml
    local hdfs_site_conf=$(cat << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<!-- Put site-specific property overrides in this file. -->

<configuration>
        <property>
                <name>dfs.namenode.http-address</name>
                <!-- 这里如果需要被其他的外界端口访问到可以设置为0.0.0.0:9870 -->
                <value>0.0.0.0:9870</value>
        </property>
        <property>
                <name>dfs.namenode.secondary.http-address</name>
                <value>${CLUSTER_HOSTS[2]}:9868</value>
        </property>
        <property>
                <name>dfs.replication</name>
                <value>3</value>
        </property>
</configuration>
EOF
)
    
    # 创建yarn-site.xml
    local yarn_site_conf=$(cat << EOF
<?xml version="1.0"?>
<configuration>

<!-- Site specific YARN configuration properties -->
        <property>
                <name>yarn.nodemanager.aux-services</name>
                <value>mapreduce_shuffle</value>
        </property>
        <property>
                <name>yarn.resourcemanager.hostname</name>
                <value>$YARN_NODE</value>
        </property>
        <property>
                <name>yarn.resourcemanager.webapp.address</name>
                <value>0.0.0.0:8088</value>
        </property>
        <property>
                <name>yarn.nodemanager.env-whitelist</name>
                <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_HOME,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_MAPRED_HOME</value>
        </property>
        <property>
                <name>yarn.scheduler.minimium-allocation-mb</name>
                <value>512</value>
        </property>
        <property>
                <name>yarn.scheduler.maximum-allocation-mb</name>
                <value>2048</value>
        </property>
        <property>
                <name>yarn.nodemanager.pmem-check-enabled</name>
                <value>true</value>
        </property>
        <property>
                <name>yarn.nodemanager.resource.memory-mb</name>
                <value>2048</value>
        </property>
        <property>
                <name>yarn.nodemanager.vmem-check-enabled</name>
                <value>false</value>
        </property>
        <property>
                <name>yarn.log-aggregation-enable</name>
                <value>true</value>
        </property>
        <property>
                <name>yarn.log.server.url</name>
                <value>http://$MASTER_NODE:19888/jobhistory/logs</value>
        </property>
        <property>
                <name>yarn.log-aggregation.retain-seconds</name>
                <value>604800</value>
        </property>

</configuration>
EOF
)
    
    # 创建mapred-site.xml
    local mapred_site_conf=$(cat << EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>


<!-- Put site-specific property overrides in this file. -->

<configuration>
        <property>
                <name>mapreduce.framework.name</name>
                <value>yarn</value>
        </property>
        <property>
                <name>mapreduce.jobhistory.address</name>
                <value>$MASTER_NODE:10020</value>
        </property>
        <property>
                <name>mapreduce.jobhistory.webapp.address</name>
                <value>$MASTER_NODE:19888</value>
        </property>
</configuration>
EOF
)
    
    # 创建workers文件
    local workers_conf="$(printf "%s\n" "${CLUSTER_HOSTS[@]}")"
    
    # 分发配置文件到集群
    print_info "分发Hadoop配置文件到集群..."
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "分发配置到 $host..."
        
        # 创建配置目录
        run_on_host $host "mkdir -p $hadoop_conf_dir"
        
        # 写入配置文件
        echo "$core_site_conf" | run_on_host $host "cat > $hadoop_conf_dir/core-site.xml"
        echo "$hdfs_site_conf" | run_on_host $host "cat > $hadoop_conf_dir/hdfs-site.xml"
        echo "$yarn_site_conf" | run_on_host $host "cat > $hadoop_conf_dir/yarn-site.xml"
        echo "$mapred_site_conf" | run_on_host $host "cat > $hadoop_conf_dir/mapred-site.xml"
        echo "$workers_conf" | run_on_host $host "cat > $hadoop_conf_dir/workers"
        
        print_success "$host: 配置分发完成"
    done
    
    # 更新hadoop-env.sh配置
    print_info "更新Hadoop环境配置..."

    for host in "${CLUSTER_HOSTS[@]}"; do
    run_on_host "$host" "
        conf=$HADOOP_HOME/etc/hadoop/hadoop-env.sh

        grep -q '^export HADOOP_ALLOW_ROOT=' \$conf \
        || echo 'export HADOOP_ALLOW_ROOT=true' >> \$conf

        grep -q '^export HDFS_NAMENODE_USER=' \$conf \
        && sed -i 's|^export HDFS_NAMENODE_USER=.*|export HDFS_NAMENODE_USER=$HDFS_NAMENODE_USER|' \$conf \
        || echo 'export HDFS_NAMENODE_USER=$HDFS_NAMENODE_USER' >> \$conf

        grep -q '^export HDFS_DATANODE_USER=' \$conf \
        && sed -i 's|^export HDFS_DATANODE_USER=.*|export HDFS_DATANODE_USER=$HDFS_DATANODE_USER|' \$conf \
        || echo 'export HDFS_DATANODE_USER=$HDFS_DATANODE_USER' >> \$conf
    "
    done
    
    print_success "Hadoop集群配置完成"
}


get_datanode_status() {
    run_on_host "$MASTER_NODE" \
        "export HDFS_NAMENODE_USER=$HDFS_NAMENODE_USER && export HDFS_DATANODE_USER=$HDFS_DATANODE_USER && export HDFS_SECONDARYNAMENODE_USER=$HDFS_SECONDARYNAMENODE_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/bin/hdfs dfsadmin -report 2>/dev/null"
}

is_hdfs_available() {
    run_on_host "$MASTER_NODE" \
        "export HDFS_NAMENODE_USER=$HDFS_NAMENODE_USER && export HDFS_DATANODE_USER=$HDFS_DATANODE_USER && export HDFS_SECONDARYNAMENODE_USER=$HDFS_SECONDARYNAMENODE_USER && export HADOOP_ALLOW_ROOT=true && $HADOOP_HOME/bin/hdfs dfs -ls / >/dev/null 2>&1"
}

# ---------- 命令入口 ----------

case "$CMD" in
    start)
        start_hdfs "$SUBCMD"
        start_yarn
        check_all_status
        ;;
    stop)
        stop_yarn
        stop_hdfs
        ;;
    restart)
        stop_yarn
        stop_hdfs
        sleep 3
        start_hdfs "$SUBCMD"
        start_yarn
        check_all_status
        ;;
    status)
        check_all_status
        ;;
    start-hdfs)
        start_hdfs "$SUBCMD"
        ;;
    stop-hdfs)
        stop_hdfs
        ;;
    start-yarn)
        start_yarn
        ;;
    stop-yarn)
        stop_yarn
        ;;
    format)
        format_namenode
        ;;
    setup)
        setup_hadoop
        ;;
    start-historyserver)
        start_historyserver
        ;;
    stop-historyserver)
        stop_historyserver
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|start-hdfs|stop-hdfs|start-yarn|stop-yarn|start-historyserver|stop-historyserver|format}"
        echo ""
        echo "说明:"
        echo "  start [format]              启动 HDFS + YARN（可选格式化）"
        echo "  stop                        停止整个 Hadoop"
        echo "  restart                     重启 Hadoop"
        echo "  status                      查看集群状态"
        echo "  setup                       配置 Hadoop 集群"
        echo "  format                      仅格式化 NameNode"
        echo "  start-historyserver         启动 JobHistory Server"
        echo "  stop-historyserver          停止 JobHistory Server"
        exit 1
        ;;
esac
