#!/bin/bash

# ============================================
# 配置同步脚本
# ============================================

source $SCRIPTS_BASE/common/common.sh

sync_all_configs() {
    print_step "同步集群配置"
    
    # 1. 同步脚本
    print_info "同步管理脚本..."
    sync_directory "$SCRIPTS_BASE" "/opt/sh"
    run_on_cluster "chmod +x /opt/sh/*/*.sh"
    
    # 2. 同步Hadoop配置
    print_info "同步Hadoop配置..."
    if [ -d "$HADOOP_HOME/etc/hadoop" ]; then
        sync_directory "$HADOOP_HOME/etc/hadoop" "$HADOOP_HOME/etc/hadoop"
    fi
    
    # 3. 同步Zookeeper配置
    print_info "同步Zookeeper配置..."
    if [ -d "$ZOOKEEPER_HOME/conf" ]; then
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
        sync_directory "$SCRIPTS_BASE/flume/conf" "$FLUME_CONF_DIR"
    fi
    
    print_success "配置同步完成"
}

case "$1" in
    ""|"all")
        sync_all_configs
        ;;
        
    "scripts")
        sync_directory "$SCRIPTS_BASE" "/opt/sh"
        run_on_cluster "chmod +x /opt/sh/*/*.sh"
        ;;
        
    "hadoop")
        sync_directory "$HADOOP_HOME/etc/hadoop" "$HADOOP_HOME/etc/hadoop"
        ;;
        
    "kafka")
        $SCRIPTS_BASE/kafka/kafka-manager.sh setup
        ;;
        
    "flume")
        sync_directory "$SCRIPTS_BASE/flume/conf" "$FLUME_CONF_DIR"
        ;;
        
    *)
        echo "用法: $0 {all|scripts|hadoop|kafka|flume}"
        exit 1
esac