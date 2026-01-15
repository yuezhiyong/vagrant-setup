#!/bin/bash

# ============================================
# 组件管理脚本
# 用于单独管理组件的安装、卸载、状态检查
# ============================================

# Dynamically calculate SCRIPTS_BASE based on script location
set -euo pipefail
# Override SCRIPTS_BASE with the actual script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
export SCRIPTS_BASE
echo "SCRIPTS_BASE: $SCRIPTS_BASE"

source $SCRIPTS_BASE/common/color.sh
source $SCRIPTS_BASE/common/common.sh
source $SCRIPTS_BASE/common/config.sh

# 安装和配置函数已在此定义

# 组件配置
declare -A COMPONENTS=(
    ["jdk"]="jdk-8u*linux-x64.tar.gz"
    ["hadoop"]="hadoop-3.*.tar.gz"
    ["zookeeper"]="apache-zookeeper-3.*.tar.gz"
    ["kafka"]="kafka_2.*.tgz"
    ["flume"]="apache-flume-1.*-bin.tar.gz"
    ["hive"]="apache-hive-*.tar.gz"
    ["datax"]="datax.tar.gz"
    ["maxwell"]="maxwell-*.tar.gz"
    ["spark"]="spark-*-bin-hadoop*.tgz"
)

# 期望的安装路径
declare -A TARGET_PATHS=(
    ["jdk"]="$MODULE_BASE/java"
    ["hadoop"]="$MODULE_BASE/hadoop"
    ["zookeeper"]="$MODULE_BASE/zookeeper"
    ["kafka"]="$MODULE_BASE/kafka"
    ["flume"]="$MODULE_BASE/flume"
    ["hive"]="$MODULE_BASE/hive"
    ["datax"]="$MODULE_BASE/datax"
    ["maxwell"]="$MODULE_BASE/maxwell"
    ["spark"]="$MODULE_BASE/spark"
)

install_component() {
    local component=$1
    local pattern="${COMPONENTS[$component]}"
    local target_path="${TARGET_PATHS[$component]}"
    
    print_info "安装 $component ..."
    print_info "文件模式: $pattern"
    # 查找文件
    local tar_file=$(find /vagrant/data -type f -name "$pattern" 2>/dev/null | head -1)
    if [ -z "$tar_file" ]; then
        print_warning "未找到 $component 的安装文件，跳过安装"
        return 1
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
    
    # 使用hadoop-manager.sh的setup功能来配置Hadoop
    print_info "使用hadoop-manager.sh配置Hadoop集群..."
    bash $SCRIPTS_BASE/hadoop/hadoop-manager.sh setup
    
    if [ $? -eq 0 ]; then
        print_success "Hadoop集群配置完成"
        return 0
    else
        print_error "Hadoop集群配置失败"
        return 1
    fi
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

setup_hive_config() {
    print_step "配置Hive"
    
    # 检查Hive是否安装
    local hive_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/hive* 2>/dev/null | head -1")
    if [ -z "$hive_home" ]; then
        print_warning "未找到Hive安装，跳过配置"
        return 0
    fi
    
    export HIVE_HOME="$hive_home"
    
    # 使用hive-manager.sh的配置功能
    print_info "使用hive-manager.sh配置Hive..."
    bash $SCRIPTS_BASE/hive/hive-manager.sh setup
    
    if [ $? -eq 0 ]; then
        print_success "Hive配置完成"
        return 0
    else
        print_error "Hive配置失败"
        return 1
    fi
}

setup_datax_config() {
    print_step "配置DataX"
    
    # 检查DataX是否安装
    local datax_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/datax* 2>/dev/null | head -1")
    if [ -z "$datax_home" ]; then
        print_warning "未找到DataX安装，跳过配置"
        return 0
    fi
    
    export DATAX_HOME="$datax_home"
    
    # 使用datax-manager.sh的配置功能
    print_info "使用datax-manager.sh配置DataX..."
    bash $SCRIPTS_BASE/datax/datax-manager.sh setup
    
    if [ $? -eq 0 ]; then
        print_success "DataX配置完成"
        return 0
    else
        print_error "DataX配置失败"
        return 1
    fi
}

setup_maxwell_config() {
    print_step "配置Maxwell"
    
    # 检查Maxwell是否安装
    local maxwell_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/maxwell* 2>/dev/null | head -1")
    if [ -z "$maxwell_home" ]; then
        print_warning "未找到Maxwell安装，跳过配置"
        return 0
    fi
    
    export MAXWELL_HOME="$maxwell_home"
    
    # 使用maxwell-manager.sh的配置功能
    print_info "使用maxwell-manager.sh配置Maxwell..."
    bash $SCRIPTS_BASE/maxwell/maxwell-manager.sh setup
    
    if [ $? -eq 0 ]; then
        print_success "Maxwell配置完成"
        return 0
    else
        print_error "Maxwell配置失败"
        return 1
    fi
}

setup_spark_config() {
    print_step "配置Spark"
    
    # 检查Spark是否安装
    local spark_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/spark* 2>/dev/null | head -1")
    if [ -z "$spark_home" ]; then
        print_warning "未找到Spark安装，跳过配置"
        return 0
    fi
    
    export SPARK_HOME="$spark_home"
    
    # 使用spark-manager.sh的配置功能
    print_info "使用spark-manager.sh配置Spark..."
    bash ../spark/spark-manager.sh setup
    
    if [ $? -eq 0 ]; then
        print_success "Spark配置完成"
        return 0
    else
        print_error "Spark配置失败"
        return 1
    fi
}

setup_environment_variables() {
    print_step "设置环境变量"
    
    # 获取实际安装路径
    local java_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/jdk* 2>/dev/null | head -1")
    local hadoop_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/hadoop* 2>/dev/null | head -1")
    local zk_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/zookeeper* 2>/dev/null | head -1")
    local kafka_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/kafka* 2>/dev/null | head -1")
    local flume_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/flume* 2>/dev/null | head -1")
    local hive_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/hive* 2>/dev/null | head -1")
    local datax_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/datax* 2>/dev/null | head -1")
    local maxwell_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/maxwell* 2>/dev/null | head -1")
    local spark_home=$(ssh $MASTER_NODE "ls -d $MODULE_BASE/spark* 2>/dev/null | head -1")
    
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

# Hive环境
export HIVE_HOME=${hive_home:-$MODULE_BASE/hive}
export PATH=\$PATH:\$HIVE_HOME/bin

# DataX环境
export DATAX_HOME=${datax_home:-$MODULE_BASE/datax}
export PATH=\$PATH:\$DATAX_HOME/bin

# Maxwell环境
export MAXWELL_HOME=${maxwell_home:-$MODULE_BASE/maxwell}
export PATH=\$PATH:\$MAXWELL_HOME/bin

# Spark环境
export SPARK_HOME=${spark_home:-$MODULE_BASE/spark}
export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin

# Hadoop进程用户
export HDFS_NAMENODE_USER=$HDFS_NAMENODE_USER
export HDFS_DATANODE_USER=$HDFS_DATANODE_USER
export HDFS_SECONDARYNAMENODE_USER=$HDFS_SECONDARYNAMENODE_USER
export YARN_RESOURCEMANAGER_USER=$YARN_RESOURCEMANAGER_USER
export YARN_NODEMANAGER_USER=$YARN_NODEMANAGER_USER

# 常用别名
alias hstart='$SCRIPTS_BASE/hadoop/hadoop-manager.sh start'
alias hstop='$SCRIPTS_BASE/hadoop/hadoop-manager.sh stop'
alias kstart='$SCRIPTS_BASE/kafka/kafka-manager.sh start'
alias kstop='$SCRIPTS_BASE/kafka/kafka-manager.sh stop'
alias zstart='$SCRIPTS_BASE/zookeeper/zk-manager.sh start'
alias zstop='$SCRIPTS_BASE/zookeeper/zk-manager.sh stop'
alias fstart='$SCRIPTS_BASE/flume/flume-manager.sh start'
alias fstop='$SCRIPTS_BASE/flume/flume-manager.sh stop'
alias sstart='$SCRIPTS_BASE/spark/spark-manager.sh start'
alias sstop='$SCRIPTS_BASE/spark/spark-manager.sh stop'
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
    export HIVE_HOME="${hive_home:-$MODULE_BASE/hive}"
    export DATAX_HOME="${datax_home:-$MODULE_BASE/datax}"
    export MAXWELL_HOME="${maxwell_home:-$MODULE_BASE/maxwell}"
    export SPARK_HOME="${spark_home:-$MODULE_BASE/spark}"
    
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
        sed -i "s|export HIVE_HOME=.*|export HIVE_HOME=\"$HIVE_HOME\"|" "$config_file"
        sed -i "s|export DATAX_HOME=.*|export DATAX_HOME=\"$DATAX_HOME\"|" "$config_file"
        sed -i "s|export MAXWELL_HOME=.*|export MAXWELL_HOME=\"$MAXWELL_HOME\"|" "$config_file"
        sed -i "s|export SPARK_HOME=.*|export SPARK_HOME=\"$SPARK_HOME\"|" "$config_file"
        
        print_success "配置文件更新完成"
    fi
}


show_component_status() {
    print_step "组件安装状态"
    
    local components=("Java" "Hadoop" "Zookeeper" "Kafka" "Flume" "Hive" "DataX" "Maxwell" "Spark")
    local paths=("$JDK_HOME" "$HADOOP_HOME" "$ZOOKEEPER_HOME" "$KAFKA_HOME" "$FLUME_HOME" "$HIVE_HOME" "$DATAX_HOME" "$MAXWELL_HOME" "$SPARK_HOME")
    
    echo -e "${YELLOW}┌─────────────────┬─────────────────┬──────────────┐${NC}"
    echo -e "${YELLOW}│   组件名称       │   安装路径      │   状态       │${NC}"
    echo -e "${YELLOW}├─────────────────┼─────────────────┼──────────────┤${NC}"
    
    for i in "${!components[@]}"; do
        local component="${components[$i]}"
        local path="${paths[$i]}"
        local status="未安装"
        local version=""
        
        if [ -d "$path" ]; then
            status="已安装"
            case $component in
                "Java")
                    version=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
                    ;;
                "Hadoop")
                    version=$(hadoop version 2>/dev/null | head -1 | cut -d' ' -f2)
                    ;;
                "Zookeeper")
                    version=$(zookeeper version 2>&1 | head -1 | cut -d',' -f1 | cut -d' ' -f5)
                    ;;
                "Kafka")
                    version=$(kafka-topics.sh --version 2>&1 | head -1)
                    ;;
                "Flume")
                    version=$(flume-ng version 2>&1 | head -1 | cut -d' ' -f2)
                    ;;
                "Hive")
                    version=$(hive --version 2>/dev/null | head -1 | cut -d' ' -f3)
                    ;;
                "DataX")
                    version="N/A"
                    ;;
                "Maxwell")
                    version="N/A"
                    ;;
                "Spark")
                    version=$(spark-shell --version 2>&1 | grep -o "version [0-9.]*)" | cut -d' ' -f2 | tr -d ')')
                    ;;
            esac
            
            if [ -n "$version" ] && [ "$version" != "N/A" ]; then
                status="已安装 ($version)"
            fi
        fi
        
        printf "${YELLOW}│ %-15s │ %-15s │ %-12s │${NC}\n" \
            "$component" \
            "$(basename $path 2>/dev/null || echo 'N/A')" \
            "$status"
    done
    
    echo -e "${YELLOW}└─────────────────┴─────────────────┴──────────────┘${NC}"
}

install_single_component() {
    local component=$1
    local install_result=0
    
    case $component in
        "jdk"|"java")
            install_component "jdk"
            install_result=$?
            if [ $install_result -eq 0 ]; then
                setup_java
            fi
            ;;
        "hadoop")
            install_component "hadoop"
            install_result=$?
            if [ $install_result -eq 0 ]; then
                setup_hadoop_config
            fi
            ;;
        "zookeeper"|"zk")
            install_component "zookeeper"
            install_result=$?
            if [ $install_result -eq 0 ]; then
                setup_zookeeper_config
            fi
            ;;
        "kafka")
            install_component "kafka"
            install_result=$?
            if [ $install_result -eq 0 ]; then
                setup_kafka_config
            fi
            ;;
        "flume")
            install_component "flume"
            install_result=$?
            if [ $install_result -eq 0 ]; then
                setup_flume_config
            fi
            ;;
        "hive")
            install_component "hive"
            install_result=$?
            if [ $install_result -eq 0 ]; then
                setup_hive_config
            fi
            ;;
        "datax")
            install_component "datax"
            install_result=$?
            if [ $install_result -eq 0 ]; then
                setup_datax_config
            fi
            ;;
        "maxwell")
            install_component "maxwell"
            install_result=$?
            if [ $install_result -eq 0 ]; then
                setup_maxwell_config
            fi
            ;;
        "spark")
            install_component "spark"
            install_result=$?
            if [ $install_result -eq 0 ]; then
                setup_spark_config
            fi
            ;;
        *)
            print_error "未知组件: $component"
            return 1
            ;;
    esac
    
    # 只有在安装成功的情况下才更新环境变量
    if [ $install_result -eq 0 ]; then
        setup_environment_variables
    fi
    
    return $install_result
}

remove_component() {
    local component=$1
    local path=""
    
    case $component in
        "jdk"|"java") path="$JDK_HOME" ;;
        "hadoop") path="$HADOOP_HOME" ;;
        "zookeeper"|"zk") path="$ZOOKEEPER_HOME" ;;
        "kafka") path="$KAFKA_HOME" ;;
        "flume") path="$FLUME_HOME" ;;
        "hive") path="$HIVE_HOME" ;;
        "datax") path="$DATAX_HOME" ;;
        "maxwell") path="$MAXWELL_HOME" ;;
        "spark") path="$SPARK_HOME" ;;
        *) print_error "未知组件: $component"; return 1 ;;
    esac
    
    if [ ! -d "$path" ]; then
        print_warning "组件 $component 未安装"
    fi
    
    print_warning "即将删除组件 $component ($path)"
    read -p "确认删除？(y/n): " confirm
    
    if [ "$confirm" = "y" ]; then
        print_info "删除 $component ..."
        run_on_cluster "rm -rf $path"
        print_success "$component 已删除"
        return 0
    else
        print_info "取消删除"
        return 1
    fi
}

reinstall_component() {
    local component=$1
    
    print_info "重新安装 $component ..."
    
    # 先删除
    if ! remove_component $component; then
        print_info "取消重新安装 $component"
        return 1
    fi
    
    # 再安装
    install_single_component $component
}

case "$1" in
    "status")
        show_component_status
        ;;
        
    "install")
        if [ -z "$2" ]; then
            echo "用法: $0 install {jdk|hadoop|zookeeper|kafka|flume|hive|datax|maxwell|spark|all}"
            exit 1
        fi
        
        if [ "$2" = "all" ]; then
            $SCRIPTS_BASE/utils/install-all.sh components
        elif [ "$2" = "java" ] || [ "$2" = "hadoop" ] || [ "$2" = "zookeeper" ] || [ "$2" = "kafka" ] || [ "$2" = "flume" ] || [ "$2" = "hive" ] || [ "$2" = "datax" ] || [ "$2" = "maxwell" ] || [ "$2" = "spark" ]; then
            install_single_component "$2"
        else
            install_single_component "$2"
        fi
        ;;
        
    "setup")
        if [ -z "$2" ]; then
            echo "用法: $0 setup {java|hadoop|zookeeper|kafka|flume|hive|datax|maxwell|spark}"
            exit 1
        fi
        
        case "$2" in
            "java")
                setup_java
                ;;
            "hadoop")
                setup_hadoop_config
                ;;
            "zookeeper")
                setup_zookeeper_config
                ;;
            "kafka")
                # 使用kafka-manager.sh的setup功能来配置Kafka
                print_info "使用kafka-manager.sh配置Kafka集群..."
                bash $SCRIPTS_BASE/kafka/kafka-manager.sh setup
                ;;
            "flume")
                setup_flume_config
                ;;
            "hive")
                setup_hive_config
                ;;
            "datax")
                setup_datax_config
                ;;
            "maxwell")
                setup_maxwell_config
                ;;
            "spark")
                setup_spark_config
                ;;
            *)
                print_error "未知组件: $2"
                exit 1
                ;;
        esac
        ;;
        
    "setup_env")
        setup_environment_variables
        ;;
        
    "remove"|"uninstall")
        if [ -z "$2" ]; then
            echo "用法: $0 remove {jdk|hadoop|zookeeper|kafka|flume|hive|datax|maxwell|spark}"
            exit 1
        fi
        remove_component "$2"
        ;;
        
    "reinstall")
        if [ -z "$2" ]; then
            echo "用法: $0 reinstall {jdk|hadoop|zookeeper|kafka|flume|hive|datax|maxwell|spark}"
            exit 1
        fi
        reinstall_component "$2"
        ;;
        
    "list")
        print_info "可用的组件文件:"
        # 搜索所有可能的组件文件格式
        for pattern in "/vagrant/data/java/jdk-*.tar.gz" "/vagrant/data/hadoop/hadoop-*.tar.gz" "/vagrant/data/zookeeper/apache-zookeeper-*.tar.gz" "/vagrant/data/kafka/kafka_*.tgz" "/vagrant/data/flume/apache-flume-*.tar.gz" "/vagrant/data/hive/apache-hive-*.tar.gz" "/vagrant/data/datax/datax.tar.gz" "/vagrant/data/maxwell/maxwell-*.tar.gz" "/vagrant/data/spark/spark-*-bin-hadoop*.tgz"; do
            if ls $pattern 1> /dev/null 2>&1; then
                ls -la $pattern
                files_found=true
            fi
        done
        if [ "$files_found" = false ]; then
            echo "无文件"
        fi
        ;;
        
    *)
        echo "用法: $0 {status|install|remove|reinstall|list}"
        echo ""
        echo "命令说明:"
        echo "  status                  查看组件状态"
        echo "  install <component>     安装指定组件"
        echo "  remove <component>      删除指定组件"
        echo "  reinstall <component>   重新安装组件"
        echo "  list                    列出可用组件文件"
        echo ""
        echo "可用组件: jdk, hadoop, zookeeper, kafka, flume, hive, datax, maxwell, spark"
        exit 1
esac