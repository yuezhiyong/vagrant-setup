#!/bin/bash
# 集群公共配置文件

# 集群节点列表
export CLUSTER_HOSTS=("centos-101" "centos-102" "centos-103")

# 组件安装目录
export MODULE_HOME="/opt/module"
export JAVA_HOME="$MODULE_HOME/jdk1.8.0_371"
export ZK_HOME="$MODULE_HOME/zookeeper-3.7.0"
export KAFKA_HOME="$MODULE_HOME/kafka_2.13-3.4.0"
export FLUME_HOME="$MODULE_HOME/flume-1.11.0"
export HADOOP_HOME="$MODULE_HOME/hadoop-3.3.4"

# 数据存储目录
export DATA_HOME="/opt/data"
export ZK_DATA_DIR="$DATA_HOME/zookeeper"
export KAFKA_LOG_DIR="$DATA_HOME/kafka"
export HDFS_DATA_DIR="$DATA_HOME/hadoop"

# 日志目录
export LOG_HOME="/opt/logs"

# 颜色输出
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# 输出函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 远程执行命令
remote_exec() {
    local host=$1
    local cmd=$2
    ssh $host "$cmd"
    return $?
}

# 检查远程服务是否运行
check_remote_service() {
    local host=$1
    local service=$2
    local pid_file=$3
    
    local result=$(ssh $host "if [ -f $pid_file ] && ps -p \$(cat $pid_file) > /dev/null 2>&1; then echo 'running'; else echo 'stopped'; fi")
    echo $result
}

# 分发文件到集群
distribute_file() {
    local src_file=$1
    local dest_dir=$2
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        scp -r $src_file $host:$dest_dir/
        if [ $? -eq 0 ]; then
            print_info "文件已分发到 $host:$dest_dir"
        else
            print_error "文件分发到 $host 失败"
        fi
    done
}