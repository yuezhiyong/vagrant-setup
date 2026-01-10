#!/bin/bash

# ============================================
# 启动所有组件
# ============================================

source $SCRIPTS_BASE/common/common.sh

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                大数据集群启动脚本                        ║"
    echo "║                版本 1.0.0                                ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

start_all_components() {
    print_banner
    
    # 1. 检查环境
    print_step "1. 检查集群环境"
    check_all_ssh || exit 1
    create_directories
    
    # 2. 启动Zookeeper
    print_step "2. 启动Zookeeper集群"
    $SCRIPTS_BASE/kafka/zk-start.sh start || {
        print_error "Zookeeper启动失败"
        exit 1
    }
    sleep 5
    
    # 3. 启动Kafka
    print_step "3. 启动Kafka集群"
    $SCRIPTS_BASE/kafka/kafka-manager.sh start || {
        print_error "Kafka启动失败"
        exit 1
    }
    sleep 5
    
    # 4. 启动Hadoop
    print_step "4. 启动Hadoop集群"
    $SCRIPTS_BASE/hadoop/hadoop-start.sh start || {
        print_error "Hadoop启动失败"
        exit 1
    }
    sleep 5
    
    # 5. 启动Flume（可选）
    if [ "$1" = "with-flume" ]; then
        print_step "5. 启动Flume"
        $SCRIPTS_BASE/flume/flume-manager.sh setup
        $SCRIPTS_BASE/flume/flume-manager.sh start all
    fi
    
    print_step "启动完成"
    print_success "所有组件启动完成！"
    
    # 显示状态
    echo ""
    $SCRIPTS_BASE/cluster/status-all.sh
}

case "$1" in
    ""|"all")
        start_all_components
        ;;
        
    "with-flume")
        start_all_components "with-flume"
        ;;
        
    "minimal")
        print_banner
        $SCRIPTS_BASE/kafka/zk-start.sh start
        sleep 3
        $SCRIPTS_BASE/kafka/kafka-manager.sh start
        ;;
        
    *)
        echo "用法: $0 {all|with-flume|minimal}"
        echo ""
        echo "启动模式:"
        echo "  all         启动所有组件 (ZK, Kafka, Hadoop)"
        echo "  with-flume  启动所有组件包括Flume"
        echo "  minimal     只启动ZK和Kafka"
        exit 1
esac