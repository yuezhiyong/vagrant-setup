#!/bin/bash
# ============================================
# 大数据集群自动安装脚本
# 自动从/vagrant/目录安装组件到/opt/module
# ============================================

# 动态设置SCRIPTS_BASE变量（当前脚本所在目录的父目录）
export SCRIPTS_BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# 设置其他路径变量
export MODULE_BASE="/opt/module"

# 保存原始的SCRIPTS_BASE值
ORIG_SCRIPTS_BASE="$SCRIPTS_BASE"

# 加载公共函数库（按依赖顺序）
source $SCRIPTS_BASE/common/config.sh

# 恢复原始的SCRIPTS_BASE值，以确保后续加载的脚本能找到正确位置
export SCRIPTS_BASE="$ORIG_SCRIPTS_BASE"

source $SCRIPTS_BASE/common/color.sh
source $SCRIPTS_BASE/common/common.sh

# 组件配置
declare -A COMPONENTS=(
    ["jdk"]="jdk-8u*linux-x64.tar.gz"
    ["hadoop"]="hadoop-3.*.tar.gz"
    ["zookeeper"]="apache-zookeeper-3.*.tar.gz"
    ["kafka"]="kafka_2.*.tgz"
    ["flume"]="apache-flume-1.*-bin.tar.gz"
)

# 期望的安装路径
declare -A TARGET_PATHS=(
    ["jdk"]="$MODULE_BASE/java"
    ["hadoop"]="$MODULE_BASE/hadoop"
    ["zookeeper"]="$MODULE_BASE/zookeeper"
    ["kafka"]="$MODULE_BASE/kafka"
    ["flume"]="$MODULE_BASE/flume"
)

print_install_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║            大数据集群自动安装脚本                        ║"
    echo "║            版本 2.0.0 (Vagrant版)                       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "源文件目录: ${YELLOW}/vagrant/${NC}"
    echo -e "安装目录: ${YELLOW}$MODULE_BASE${NC}"
    echo -e "集群节点: ${YELLOW}${CLUSTER_HOSTS[*]}${NC}"
    print_divider
}

check_vagrant_files() {
    print_step "检查Vagrant文件"
    
    local vagrant_dir="/vagrant"
    if [ ! -d "$vagrant_dir" ]; then
        print_error "未找到/vagrant/目录，请确保在Vagrant环境中运行"
        return 1
    fi
    
    print_info "扫描/vagrant/目录中的组件文件..."
    
    local found_components=0
    for component in "${!COMPONENTS[@]}"; do
        local pattern="${COMPONENTS[$component]}"
        echo -e "  $component: $pattern"
        local files=$(find $vagrant_dir -type f -name "$pattern" 2>/dev/null)
        
        if [ -n "$files" ]; then
            local file=$(echo "$files" | head -1)
            print_success "$component: $(basename $file) ($(dirname $file))"
            found_components=$((found_components + 1))
        else
            print_warning "$component: 未找到匹配 $pattern 的文件"
        fi
    done
    
    if [ $found_components -eq 0 ]; then
        print_error "未找到任何组件文件，请将tar文件放入/vagrant/目录"
        return 1
    fi
    
    print_success "找到 $found_components 个组件文件"
    return 0
}

extract_component() {
    local component=$1
    local tar_file=$2
    local target_dir=$3
    
    print_info "解压 $component: $(basename $tar_file) -> $target_dir"
    
    # 创建目标目录
    run_on_cluster "mkdir -p $target_dir"
    
    # 解压文件
    if [[ "$tar_file" == *.tar.gz ]] || [[ "$tar_file" == *.tgz ]]; then
        run_on_cluster "tar -xzf $tar_file -C $target_dir --strip-components=1"
    elif [[ "$tar_file" == *.zip ]]; then
        run_on_cluster "unzip -q $tar_file -d $target_dir"
    else
        print_error "不支持的文件格式: $tar_file"
        return 1
    fi
    
    # 检查解压是否成功
    if run_on_host $MASTER_NODE "[ -d \"$target_dir/bin\" ] || [ -d \"$target_dir/sbin\" ] || [ -d \"$target_dir/lib\" ]"; then
        print_success "$component 解压成功"
        
        # 获取实际解压后的目录名（用于创建符号链接）
        local actual_dir=$(ssh $MASTER_NODE "ls -d $target_dir/*/ 2>/dev/null | head -1 | sed 's|/$||'")
        if [ -n "$actual_dir" ]; then
            echo "$actual_dir"
        else
            echo "$target_dir"
        fi
    else
        print_error "$component 解压失败或目录结构不正确"
        return 1
    fi
}

install_component() {
    local component=$1
    local pattern="${COMPONENTS[$component]}"
    local target_path="${TARGET_PATHS[$component]}"
    
    print_info "安装 $component ..."
    
    # 查找文件
    local tar_file=$(find /vagrant -type f -name "$pattern" 2>/dev/null | head -1)
    if [ -z "$tar_file" ]; then
        print_warning "未找到 $component 的安装文件，跳过安装"
        return 0
    fi
    
    # 检查是否已安装
    if run_on_host $MASTER_NODE "[ -d \"$target_path\" ] && [ \"\$(ls -A $target_path)\" ]"; then
        print_info "$component 已安装，跳过"
        return 0
    fi
    
    # 分发tar文件到所有节点
    print_info "分发 $component 文件到集群..."
    distribute_file "$tar_file" "/tmp"
    local remote_tar="/tmp/$(basename $tar_file)"
    
    # 在所有节点解压
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "在 $host 上安装 $component..."
        # 使用here document传递命令，避免转义问题
        run_on_host $host "bash -s" << EOF
# 清理旧目录
rm -rf $target_path

# 创建临时目录用于解压
temp_dir=\$(mktemp -d)
if [[ "$remote_tar" == *.tar.gz ]] || [[ "$remote_tar" == *.tgz ]]; then
    tar -xzf "$remote_tar" -C "\$temp_dir"
elif [[ "$remote_tar" == *.zip ]]; then
    unzip -q "$remote_tar" -d "\$temp_dir"
fi

# 获取解压后的实际目录名
extracted_dir=\$(ls -d \$temp_dir/*/ 2>/dev/null | head -1 | xargs basename)

# 将解压后的目录重命名到目标路径
if [ -n "\$extracted_dir" ]; then
    mv "\$temp_dir/\$extracted_dir" "$target_path"
else
    # 如果没有子目录，则直接移动内容
    mv \$temp_dir/* $target_path/ 2>/dev/null || mv \$temp_dir/.[^.]* $target_path/ 2>/dev/null
fi

# 清理临时目录
rm -rf "\$temp_dir"
EOF
        
        # 检查安装是否成功
        if run_on_host $host "[ -d \"$target_path\" ] && [ \"$(ls -A $target_path)\" ]"; then
            print_success "$host: $component 安装成功"
        else
            print_error "$host: $component 安装失败"
            return 1
        fi
    done
    
    # 清理临时文件
    run_on_cluster "rm -f $remote_tar"
    
    print_success "$component 安装完成"
    return 0
}

setup_java() {
    print_step "设置Java环境"
    
    # 查找Java安装
    local java_dirs=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/java* 2>/dev/null")
    if [ -z "$java_dirs" ]; then
        print_error "未找到Java安装"
        return 1
    fi
    
    local java_home=$(echo "$java_dirs" | head -1)
    echo "Java Home: $java_home"
    # 更新环境变量
    local bashrc_content="
# Java环境变量
export JAVA_HOME=$java_home
export PATH=\$JAVA_HOME/bin:\$PATH
"
    
    # 设置所有节点的Java环境变量
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "设置 $host Java环境变量..."
        echo "$bashrc_content" | run_on_host $host "cat >> ~/.bashrc"
        
        # 验证Java安装
        local java_version=$(ssh $host "source ~/.bashrc && java -version 2>&1 | head -1")
        if [[ $java_version == *"version"* ]]; then
            print_success "$host: Java $java_version"
        else
            print_error "$host: Java验证失败"
            return 1
        fi
    done
    
    # 更新配置中的JAVA_HOME
    export JDK_HOME="$java_home"
    
    return 0
}

setup_hadoop_config() {
    print_step "配置Hadoop"
    
    local hadoop_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/hadoop* 2>/dev/null | head -1")
    if [ -z "$hadoop_home" ]; then
        print_error "未找到Hadoop安装"
        return 1
    fi
    
    export HADOOP_HOME="$hadoop_home"
    
    # 创建必要的配置文件
    local hadoop_conf_dir="$HADOOP_HOME/etc/hadoop"
    
    # 创建core-site.xml
    cat > /tmp/core-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!--
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License. See accompanying LICENSE file.
-->

<!-- Put site-specific property overrides in this file. -->

<configuration>
        <property>
                <name>fs.defaultFS</name>
                <value>hdfs://${MASTER_NODE}:8020</value>
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

    # 创建hdfs-site.xml
    cat > /tmp/hdfs-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!--
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License. See accompanying LICENSE file.
-->

<!-- Put site-specific property overrides in this file. -->

<configuration>
        <property>
                <name>dfs.namenode.http-address</name>
                <value>${MASTER_NODE}:9870</value>
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

    # 创建yarn-site.xml
    cat > /tmp/yarn-site.xml << EOF
<?xml version="1.0"?>
<!--
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License. See accompanying LICENSE file.
-->
<configuration>

<!-- Site specific YARN configuration properties -->
        <property>
                <name>yarn.nodemanager.aux-services</name>
                <value>mapreduce_shuffle</value>
        </property>
        <property>
                <name>yarn.resourcemanager.hostname</name>
                <value>${MASTER_NODE}</value>
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
                <value>http://${MASTER_NODE}:19888/jobhistory/logs</value>
        </property>
        <property>
                <name>yarn.log-aggregation.retain-seconds</name>
                <value>604800</value>
        </property>

</configuration>
EOF

    # 创建mapred-site.xml
    cat > /tmp/mapred-site.xml << EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!--
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License. See accompanying LICENSE file.
-->

<!-- Put site-specific property overrides in this file. -->

<configuration>
        <property>
                <name>mapreduce.framework.name</name>
                <value>yarn</value>
        </property>
        <property>
                <name>mapreduce.jobhistory.address</name>
                <value>${MASTER_NODE}:10020</value>
        </property>
        <property>
                <name>mapreduce.jobhistory.webapp.address</name>
                <value>${MASTER_NODE}:19888</value>
        </property>
</configuration>
EOF

    # 创建workers文件
    printf "%s\n" "${CLUSTER_HOSTS[@]}" > /tmp/workers
    
    # 分发配置文件到集群
    print_info "分发Hadoop配置文件..."
    for host in "${CLUSTER_HOSTS[@]}"; do
        run_on_host $host "mkdir -p $hadoop_conf_dir"
        
        for config_file in core-site.xml hdfs-site.xml yarn-site.xml mapred-site.xml workers; do
            $SCP_CMD /tmp/$config_file $host:$hadoop_conf_dir/
        done
        
        # 复制模板文件
        run_on_host $host "cp $hadoop_conf_dir/mapred-site.xml.template $hadoop_conf_dir/mapred-site.xml 2>/dev/null || true"
        
        print_success "$host: Hadoop配置完成"
    done
    
    # 更新hadoop-env.sh配置
    print_info "更新Hadoop环境配置..."
    for host in "${CLUSTER_HOSTS[@]}"; do
        run_on_host $host "sed -i '/^export HADOOP_SECURE_DN_USER=/ s/^/#/' $hadoop_conf_dir/hadoop-env.sh 2>/dev/null || true"
        run_on_host $host "sed -i '/^export JSVC_HOME=/ s/^/#/' $hadoop_conf_dir/hadoop-env.sh 2>/dev/null || true"
        
        # 添加安全配置
        run_on_host $host "grep -q 'export HADOOP_ALLOW_ROOT=' $hadoop_conf_dir/hadoop-env.sh 2>/dev/null || echo 'export HADOOP_ALLOW_ROOT=true' >> $hadoop_conf_dir/hadoop-env.sh"
        run_on_host $host "grep -q 'export HADOOP_SECURE_DN_USER=' $hadoop_conf_dir/hadoop-env.sh 2>/dev/null || echo '# export HADOOP_SECURE_DN_USER=root' >> $hadoop_conf_dir/hadoop-env.sh"
    done
    
    # 清理临时文件
    rm -f /tmp/*.xml /tmp/workers
    
    return 0
}

setup_zookeeper_config() {
    print_step "配置Zookeeper"
    
    local zk_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/zookeeper* 2>/dev/null | head -1")
    if [ -z "$zk_home" ]; then
        print_error "未找到Zookeeper安装"
        return 1
    fi
    
    export ZOOKEEPER_HOME="$zk_home"
    
    # 创建zoo.cfg配置文件
    local zoo_cfg="
# Zookeeper配置
tickTime=2000
initLimit=10
syncLimit=5
dataDir=$ZK_DATA_DIR
dataLogDir=$ZK_LOG_DIR
clientPort=2181
maxClientCnxns=0
admin.enableServer=false
autopurge.snapRetainCount=3
autopurge.purgeInterval=24
4lw.commands.whitelist=*
"
    
    # 添加集群配置
    local id=1
    for host in "${CLUSTER_HOSTS[@]}"; do
        zoo_cfg+="server.$id=$host:2888:3888"$'\n'
        id=$((id + 1))
    done
    
    # 分发配置到所有节点
    print_info "分发Zookeeper配置文件..."
    local id=1
    for host in "${CLUSTER_HOSTS[@]}"; do
        # 创建数据目录
        run_on_host $host "mkdir -p $ZK_DATA_DIR $ZK_LOG_DIR"
        
        # 设置myid
        run_on_host $host "echo $id > $ZK_DATA_DIR/myid"
        
        # 写入配置文件
        echo "$zoo_cfg" | run_on_host $host "cat > $ZOOKEEPER_HOME/conf/zoo.cfg"
        
        print_success "$host: Zookeeper配置完成 (myid=$id)"
        id=$((id + 1))
    done
    
    return 0
}

setup_kafka_config() {
    print_step "配置Kafka"
    
    local kafka_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/kafka* 2>/dev/null | head -1")
    if [ -z "$kafka_home" ]; then
        print_error "未找到Kafka安装"
        return 1
    fi
    
    export KAFKA_HOME="$kafka_home"
    
    # 为每个节点生成配置文件
    local broker_id=1
    for host in "${CLUSTER_HOSTS[@]}"; do
        local kafka_conf="
# Kafka Broker配置 - $host
broker.id=$broker_id
listeners=PLAINTEXT://$host:9092
advertised.listeners=PLAINTEXT://$host:9092
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

# 日志配置
log.dirs=$KAFKA_LOG_DIR
num.partitions=3
num.recovery.threads.per.data.dir=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

# Zookeeper配置
zookeeper.connect=$(printf "%s:2181," "${CLUSTER_HOSTS[@]}" | sed 's/,$//')
zookeeper.connection.timeout.ms=18000

# 副本配置
default.replication.factor=3
min.insync.replicas=2

# 其他配置
delete.topic.enable=true
auto.create.topics.enable=false
"
        
        # 写入配置文件
        echo "$kafka_conf" | run_on_host $host "cat > $KAFKA_HOME/config/server.properties"
        print_success "$host: Kafka配置完成 (broker.id=$broker_id)"
        
        broker_id=$((broker_id + 1))
    done
    
    return 0
}

setup_flume_config() {
    print_step "配置Flume"
    
    local flume_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/flume* 2>/dev/null | head -1")
    if [ -z "$flume_home" ]; then
        print_warning "未找到Flume安装，跳过配置"
        return 0
    fi
    
    export FLUME_HOME="$flume_home"
    
    # 创建Flume配置文件目录
    run_on_cluster "mkdir -p $FLUME_CONF_DIR"
    
    # 创建示例配置文件
    cat > /tmp/flume-kafka.conf << EOF
# Flume Kafka Sink配置示例
agent.sources = tail-source
agent.channels = mem-channel
agent.sinks = kafka-sink

# Source配置 - 监控日志文件
agent.sources.tail-source.type = TAILDIR
agent.sources.tail-source.channels = mem-channel
agent.sources.tail-source.positionFile = $FLUME_LOG_DIR/taildir_position.json
agent.sources.tail-source.filegroups = f1
agent.sources.tail-source.filegroups.f1 = /var/log/.*\.log

# Channel配置
agent.channels.mem-channel.type = memory
agent.channels.mem-channel.capacity = 10000
agent.channels.mem-channel.transactionCapacity = 1000

# Sink配置 - Kafka
agent.sinks.kafka-sink.type = org.apache.flume.sink.kafka.KafkaSink
agent.sinks.kafka-sink.channel = mem-channel
agent.sinks.kafka-sink.kafka.bootstrap.servers = $(printf "%s:9092," "${CLUSTER_HOSTS[@]}" | sed 's/,$//')
agent.sinks.kafka-sink.kafka.topic = flume-logs
agent.sinks.kafka-sink.flumeBatchSize = 100
EOF

    # 分发配置文件
    distribute_file "/tmp/flume-kafka.conf" "$FLUME_CONF_DIR"
    rm -f /tmp/flume-kafka.conf
    
    print_success "Flume配置完成"
    return 0
}

setup_environment_variables() {
    print_step "设置环境变量"
    
    # 获取实际安装路径
    local java_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/jdk* 2>/dev/null | head -1")
    local hadoop_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/hadoop* 2>/dev/null | head -1")
    local zk_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/zookeeper* 2>/dev/null | head -1")
    local kafka_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/kafka* 2>/dev/null | head -1")
    local flume_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/flume* 2>/dev/null | head -1")
    
    local bashrc_content="
# ============================================
# 大数据集群环境变量
# ============================================

# Java环境
export JAVA_HOME=${java_home:-$MODULE_BASE/java}
export PATH=\$JAVA_HOME/bin:\$PATH

# Hadoop环境
export HADOOP_HOME=${hadoop_home:-$MODULE_BASE/hadoop}
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin

# Zookeeper环境
export ZOOKEEPER_HOME=${zk_home:-$MODULE_BASE/zookeeper}
export PATH=\$PATH:\$ZOOKEEPER_HOME/bin

# Kafka环境
export KAFKA_HOME=${kafka_home:-$MODULE_BASE/kafka}
export PATH=\$PATH:\$KAFKA_HOME/bin

# Flume环境
export FLUME_HOME=${flume_home:-$MODULE_BASE/flume}
export PATH=\$PATH:\$FLUME_HOME/bin

# Hadoop进程用户
export HDFS_NAMENODE_USER=root
export HDFS_DATANODE_USER=root
export HDFS_SECONDARYNAMENODE_USER=root
export YARN_RESOURCEMANAGER_USER=root
export YARN_NODEMANAGER_USER=root

# 常用别名
alias hstart='$SCRIPTS_BASE/hadoop/hadoop-start.sh start'
alias hstop='$SCRIPTS_BASE/hadoop/hadoop-start.sh stop'
alias kstart='$SCRIPTS_BASE/kafka/kafka-manager.sh start'
alias kstop='$SCRIPTS_BASE/kafka/kafka-manager.sh stop'
alias zstart='$SCRIPTS_BASE/kafka/zk-start.sh start'
alias zstop='$SCRIPTS_BASE/kafka/zk-start.sh stop'
alias fstart='$SCRIPTS_BASE/flume/flume-manager.sh start'
alias fstop='$SCRIPTS_BASE/flume/flume-manager.sh stop'
alias cstart='$SCRIPTS_BASE/cluster/start-all.sh'
alias cstop='$SCRIPTS_BASE/cluster/stop-all.sh'
alias cstatus='$SCRIPTS_BASE/cluster/status-all.sh'
"
    
    # 设置所有节点的环境变量
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "设置 $host 环境变量..."
        
        # 备份原有的.bashrc
        run_on_host $host "cp ~/.bashrc ~/.bashrc.backup.\$(date +%Y%m%d) 2>/dev/null || true"
        
        # 移除旧的环境变量设置
        run_on_host $host "sed -i '/大数据集群环境变量/,/============================================/d' ~/.bashrc"
        
        # 添加新的环境变量
        echo "$bashrc_content" | run_on_host $host "cat >> ~/.bashrc"
        
        # 立即生效
        run_on_host $host "source ~/.bashrc"
        
        print_success "$host: 环境变量设置完成"
    done
    
    # 更新当前脚本的环境变量
    export JDK_HOME="${java_home:-$MODULE_BASE/java}"
    export HADOOP_HOME="${hadoop_home:-$MODULE_BASE/hadoop}"
    export ZOOKEEPER_HOME="${zk_home:-$MODULE_BASE/zookeeper}"
    export KAFKA_HOME="${kafka_home:-$MODULE_BASE/kafka}"
    export FLUME_HOME="${flume_home:-$MODULE_BASE/flume}"
    
    # 更新配置文件
    update_config_file
    
    return 0
}

update_config_file() {
    print_info "更新配置文件..."
    
    # 更新config.sh中的路径
    local config_file="$SCRIPTS_BASE/common/config.sh"
    
    if [ -f "$config_file" ]; then
        # 备份原配置
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d)"
        
        # 更新路径变量
        sed -i "s|export JDK_HOME=.*|export JDK_HOME=\"$JDK_HOME\"|" "$config_file"
        sed -i "s|export HADOOP_HOME=.*|export HADOOP_HOME=\"$HADOOP_HOME\"|" "$config_file"
        sed -i "s|export ZOOKEEPER_HOME=.*|export ZOOKEEPER_HOME=\"$ZOOKEEPER_HOME\"|" "$config_file"
        sed -i "s|export KAFKA_HOME=.*|export KAFKA_HOME=\"$KAFKA_HOME\"|" "$config_file"
        sed -i "s|export FLUME_HOME=.*|export FLUME_HOME=\"$FLUME_HOME\"|" "$config_file"
        
        print_success "配置文件更新完成"
    fi
}

setup_ssh_keys() {
    print_step "设置SSH免密登录"
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "设置 $host SSH免密登录..."
        
        # 生成密钥（如果不存在）
        run_on_host $host "
            if [ ! -f ~/.ssh/id_rsa ]; then
                ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
            fi
        "
        
        # 收集所有节点的公钥
        local all_pub_keys=""
        for h in "${CLUSTER_HOSTS[@]}"; do
            local pub_key=$(run_on_host $h "cat ~/.ssh/id_rsa.pub 2>/dev/null")
            all_pub_keys+="$pub_key"$'\n'
        done
        
        # 分发到每个节点
        echo "$all_pub_keys" | run_on_host $host "
            mkdir -p ~/.ssh
            chmod 700 ~/.ssh
            echo '$all_pub_keys' >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            # 禁用严格主机检查
            echo 'Host *' > ~/.ssh/config
            echo '    StrictHostKeyChecking no' >> ~/.ssh/config
            echo '    UserKnownHostsFile /dev/null' >> ~/.ssh/config
            chmod 600 ~/.ssh/config
        "
        
        # 测试SSH连接
        if check_ssh_connection $host; then
            print_success "$host SSH免密登录配置成功"
        else
            print_error "$host SSH免密登录配置失败"
            return 1
        fi
    done
    
    return 0
}

setup_hosts_file() {
    print_step "设置/etc/hosts文件"
    
    # 收集所有节点的IP地址
    local hosts_content=""
    for host in "${CLUSTER_HOSTS[@]}"; do
        local ip=$(get_host_ip $host)
        if [ -n "$ip" ]; then
            hosts_content+="$ip $host"$'\n'
        else
            # 如果无法获取IP，使用本地解析
            hosts_content+="127.0.0.1 $host"$'\n'
        fi
    done
    
    # 更新所有节点的hosts文件
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "更新 $host /etc/hosts..."
        # 备份原有文件
        run_on_host $host "sudo cp /etc/hosts /etc/hosts.backup.\$(date +%Y%m%d)"
        # 移除旧条目
        # run_on_host $host "sudo sed -i '/${CLUSTER_HOSTS[0]}/,/^$/d' /etc/hosts"
        
        # 添加新条目
        echo "# 大数据集群节点" | run_on_host $host "sudo tee -a /etc/hosts > /dev/null"
        echo "$hosts_content" | run_on_host $host "sudo tee -a /etc/hosts > /dev/null"
        print_success "$host hosts文件更新完成"
    done
}

create_directories_structure() {
    print_step "创建目录结构"
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "在 $host 创建目录..."
        
        # 软件目录
        run_on_host $host "sudo mkdir -p $MODULE_BASE"
        
        # 设置目录权限给vagrant用户
        run_on_host $host "sudo chown vagrant:vagrant $MODULE_BASE"
        
        # 数据目录
        #run_on_host $host "sudo mkdir -p $ZK_DATA_DIR $ZK_LOG_DIR"
        #run_on_host $host "sudo mkdir -p $KAFKA_LOG_DIR $FLUME_LOG_DIR"
        #run_on_host $host "sudo mkdir -p $LOG_DIR"
        
        # 设置数据目录权限
        #run_on_host $host "sudo chown -R vagrant:vagrant $(dirname $ZK_DATA_DIR) $(dirname $KAFKA_LOG_DIR) $(dirname $FLUME_LOG_DIR) $LOG_DIR 2>/dev/null || true"
        
        # Hadoop目录
        #run_on_host $host "sudo mkdir -p ${HDFS_NAME_DIR[@]} ${HDFS_DATA_DIR[@]} ${HDFS_CHECKPOINT_DIR[@]} ${YARN_NODEMANAGER_DIR[@]}"
        #run_on_host $host "sudo mkdir -p $MODULE_BASE/hadoop/{tmp,logs}"
        
        # 设置Hadoop目录权限
        #run_on_host $host "sudo chown -R vagrant:vagrant $(dirname ${HDFS_NAME_DIR[0]}) $MODULE_BASE/hadoop 2>/dev/null || true"
        
        # 脚本目录
        #run_on_host $host "sudo mkdir -p $SCRIPTS_BASE"
        #run_on_host $host "sudo chown vagrant:vagrant $SCRIPTS_BASE 2>/dev/null || true"
        
        print_success "$host 目录创建完成"
    done
}

install_all_components() {
    print_install_banner
    
    # 检查Vagrant文件
    if ! check_vagrant_files; then
        print_error "无法继续安装"
        exit 1
    fi
    
    print_warning "即将安装大数据集群到所有节点"
    print_warning "这将会:"
    echo "  1. 安装所有组件到 $MODULE_BASE"
    echo "  2. 配置SSH免密登录"
    echo "  3. 设置环境变量"
    echo "  4. 配置所有组件"
    echo ""
    read -p "确认安装？(y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        print_info "安装取消"
        exit 0
    fi
    
    # 预检查：验证SSH连接
    print_step "预检查SSH连接"
    if ! check_all_ssh; then
        print_error "SSH连接检查失败，请确保可以从 $(hostname) SSH连接到所有集群节点"
        exit 1
    fi
    
    
    
    # 1. 设置SSH
    setup_ssh_keys || {
        print_error "SSH设置失败"
        exit 1
    }

    # 2. 创建目录结构
    create_directories_structure
    
    # 3. 设置hosts文件
    # setup_hosts_file
    
    # 4. 安装组件
    print_step "安装组件"
    
    # 安装顺序很重要：Java -> Zookeeper -> Hadoop -> Kafka -> Flume
    local components=("jdk" "zookeeper" "hadoop" "kafka" "flume")
    
    for component in "${components[@]}"; do
        install_component $component || {
            print_warning "$component 安装失败，继续安装其他组件..."
        }
        sleep 2
    done
    
    # 5. 设置Java环境
    setup_java || {
        print_error "Java环境设置失败"
        exit 1
    }
    
    # 6. 配置各个组件
    setup_hadoop_config || {
        print_warning "Hadoop配置失败，可能需要手动配置"
    }
    
    setup_zookeeper_config || {
        print_warning "Zookeeper配置失败，可能需要手动配置"
    }
    
    setup_kafka_config || {
        print_warning "Kafka配置失败，可能需要手动配置"
    }
    
    setup_flume_config || {
        print_warning "Flume配置失败，可能需要手动配置"
    }
    
    # 7. 设置环境变量
    setup_environment_variables
    
    # 8. 分发脚本
    print_step "分发管理脚本"
    
    # 同步脚本到所有节点
    $SCRIPTS_BASE/utils/sync-config.sh scripts
    
    print_step "安装完成"
    print_success "大数据集群安装完成！"
    
    # 使环境变量立即在所有节点生效
    run_on_cluster "source ~/.bashrc"
    
    echo ""
    echo -e "${GREEN}使用说明:${NC}"
    echo "1. 启动集群: $SCRIPTS_BASE/cluster/start-all.sh"
    echo "2. 停止集群: $SCRIPTS_BASE/cluster/stop-all.sh"
    echo "3. 查看状态: $SCRIPTS_BASE/cluster/status-all.sh"
    echo "4. 测试组件:"
    echo "   - 测试Hadoop: hdfs dfs -ls /"
    echo "   - 测试Kafka: $SCRIPTS_BASE/kafka/kafka-manager.sh create-topic test"
    echo ""
    echo -e "${YELLOW}环境变量已生效${NC}"
}

# 安装模式选择
case "$1" in
    ""|"all")
        install_all_components
        ;;
        
    "check")
        check_vagrant_files
        ;;
        
    "components")
        print_step "安装所有组件"
        for component in jdk zookeeper hadoop kafka flume; do
            install_component $component
        done
        ;;
        
    "config")
        print_step "配置所有组件"
        setup_java
        setup_hadoop_config
        setup_zookeeper_config
        setup_kafka_config
        setup_flume_config
        setup_environment_variables
        ;;
        
    "ssh")
        setup_ssh_keys
        ;;
        
    *)
        echo "用法: $0 {all|check|components|config|ssh}"
        echo ""
        echo "安装模式:"
        echo "  all         完整安装（推荐）"
        echo "  check       检查Vagrant文件"
        echo "  components  只安装组件"
        echo "  config      只配置组件"
        echo "  ssh         只设置SSH"
        exit 1
esac
