#!/bin/bash

# ============================================
# 配置同步脚本
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

sync_all_configs() {
    print_step "同步集群配置"
    
    # 1. 同步脚本
    print_info "同步管理脚本..."
    # 创建目标目录并设置权限
    run_on_cluster "sudo mkdir -p /opt/sh && sudo chown $USER:$USER /opt/sh"
    sync_directory "$SCRIPTS_BASE" "/opt/sh"
    run_on_cluster "chmod +x /opt/sh/*/*.sh"
    
    # 2. 同步Hadoop配置
    print_info "同步Hadoop配置..."
    if [ -d "$HADOOP_HOME/etc/hadoop" ]; then
        run_on_cluster "sudo mkdir -p $HADOOP_HOME/etc/hadoop && sudo chown $USER:$USER $HADOOP_HOME/etc/hadoop"
        sync_directory "$HADOOP_HOME/etc/hadoop" "$HADOOP_HOME/etc/hadoop"
    fi
    
    # 3. 同步Zookeeper配置
    print_info "同步Zookeeper配置..."
    if [ -d "$ZOOKEEPER_HOME/conf" ]; then
        run_on_cluster "sudo mkdir -p $ZOOKEEPER_HOME/conf && sudo chown $USER:$USER $ZOOKEEPER_HOME/conf"
        distribute_file "$ZOOKEEPER_HOME/conf/zoo.cfg" "$ZOOKEEPER_HOME/conf/"
    fi
    
    # 4. 同步Kafka配置
    print_info "同步Kafka配置..."
    if [ -d "$KAFKA_HOME/config" ]; then
        # 重新生成并分发Kafka配置
        $SCRIPTS_BASE/kafka/kafka-manager.sh setup
    fi
    
    # 5. 同步Flume配置
    print_info "同步Flume配置..."
    if [ -d "$SCRIPTS_BASE/flume/conf" ]; then
        run_on_cluster "sudo mkdir -p $FLUME_CONF_DIR && sudo chown $USER:$USER $FLUME_CONF_DIR"
        sync_directory "$SCRIPTS_BASE/flume/conf" "$FLUME_CONF_DIR"
    fi
    
    print_success "配置同步完成"
}

# Check if argument is provided, default to "all" if not
ARG="${1:-all}"

case "$ARG" in
    ""|"all")
        sync_all_configs
        ;;
        
    "scripts")
        run_on_cluster "sudo mkdir -p /opt/sh && sudo chown $USER:$USER /opt/sh"
        sync_directory "$SCRIPTS_BASE" "/opt/sh"
        run_on_cluster "chmod +x /opt/sh/*/*.sh"
        ;;
        
    "hadoop")
        run_on_cluster "sudo mkdir -p $HADOOP_HOME/etc/hadoop && sudo chown $USER:$USER $HADOOP_HOME/etc/hadoop"
        sync_directory "$HADOOP_HOME/etc/hadoop" "$HADOOP_HOME/etc/hadoop"
        ;;
        
    "kafka")
        $SCRIPTS_BASE/kafka/kafka-manager.sh setup
        ;;
        
    "flume")
        run_on_cluster "sudo mkdir -p $FLUME_CONF_DIR && sudo chown $USER:$USER $FLUME_CONF_DIR"
        sync_directory "$SCRIPTS_BASE/flume/conf" "$FLUME_CONF_DIR"
        ;;
        
    *)
        echo "用法: $0 {all|scripts|hadoop|kafka|flume}"
        exit 1
esac