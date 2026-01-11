#!/bin/bash

# ============================================
# 集群配置文件
# ============================================

# 集群节点配置
export CLUSTER_HOSTS=("centos-201" "centos-202" "centos-203")

# 管理节点（运行控制脚本的节点）
export MASTER_NODE="centos-201"

# 软件安装路径
export MODULE_BASE="/opt/module"
export SCRIPTS_BASE="/opt/sh"

# 软件版本配置
export JDK_HOME="/opt/module/java"
export HADOOP_HOME="/opt/module/hadoop"
export ZOOKEEPER_HOME="/opt/module/zookeeper"
export KAFKA_HOME="/opt/module/kafka"
export FLUME_HOME="/opt/module/flume"

# Hadoop配置
export HDFS_NAME_DIR=("$MODULE_BASE/hadoop/name")
export HDFS_DATA_DIR=("$MODULE_BASE/hadoop/data")
export HDFS_CHECKPOINT_DIR=("$MODULE_BASE/hadoop/namesecondary")
export YARN_NODEMANAGER_DIR=("$MODULE_BASE/hadoop/nodemanager")

# Hadoop进程用户
export HADOOP_USER="hadoop"

# Zookeeper配置
export ZK_DATA_DIR="$MODULE_BASE/zookeeper/data"
export ZK_LOG_DIR="$MODULE_BASE/zookeeper/logs"
export ZK_PID_DIR="/tmp"
export ZK_PID_FILE="$ZK_PID_DIR/zookeeper.pid"

# Kafka配置
export KAFKA_LOG_DIR="$MODULE_BASE/kafka/logs"
export KAFKA_PID_DIR="/tmp"
export KAFKA_PID_FILE="$KAFKA_PID_DIR/kafka.pid"

# Flume配置
export FLUME_CONF_DIR="$SCRIPTS_BASE/flume/conf"
export FLUME_LOG_DIR="$MODULE_BASE/flume/logs"
export FLUME_PID_DIR="/tmp"
export FLUME_PID_FILE="$FLUME_PID_DIR/flume.pid"

# SSH配置
export SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"
export SSH_CMD="ssh $SSH_OPTS"
export SCP_CMD="scp $SSH_OPTS"

# 日志配置
export LOG_DIR="$MODULE_BASE/logs"
mkdir -p $LOG_DIR

# 创建必要的目录
create_directories() {
    for host in "${CLUSTER_HOSTS[@]}"; do
        $SSH_CMD $host "mkdir -p $ZK_DATA_DIR $ZK_LOG_DIR $KAFKA_LOG_DIR $FLUME_LOG_DIR $LOG_DIR"
        $SSH_CMD $host "mkdir -p ${HDFS_NAME_DIR[@]} ${HDFS_DATA_DIR[@]} ${HDFS_CHECKPOINT_DIR[@]} ${YARN_NODEMANAGER_DIR[@]}"
    done
}