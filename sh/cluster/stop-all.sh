#!/bin/bash

# ============================================
# 停止所有组件
# ============================================

source $SCRIPTS_BASE/common/common.sh

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                大数据集群停止脚本                        ║"
    echo "║                版本 1.0.0                                ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

stop_all_components() {
    print_banner
    
    # 1. 停止Flume（如果运行）
    print_step "1. 停止Flume集群"
    $SCRIPTS_BASE/flume/flume-manager.sh stop all 2>/dev/null || true
    
    # 2. 停止Kafka
    print_step "2. 停止Kafka集群"
    $SCRIPTS_BASE/kafka/kafka-manager.sh stop || {
        print_warning "Kafka停止过程中出现错误，尝试强制停止"
        run_on_cluster "pkill -f 'kafka.Kafka'" || true
    }
    sleep 3
    
    # 3. 停止Zookeeper
    print_step "3. 停止Zookeeper集群"
    $SCRIPTS_BASE/kafka/zk-start.sh stop || {
        print_warning "Zookeeper停止过程中出现错误，尝试强制停止"
        run_on_cluster "pkill -f 'QuorumPeerMain'" || true
    }
    sleep 3
    
    # 4. 停止Hadoop
    print_step "4. 停止Hadoop集群"
    $SCRIPTS_BASE/hadoop/hadoop-start.sh stop || {
        print_warning "Hadoop停止过程中出现错误，尝试强制停止"
        run_on_cluster "pkill -f 'NameNode\|DataNode\|ResourceManager\|NodeManager'" || true
    }
    
    print_step "停止完成"
    print_success "所有组件已停止！"
    
    # 清理PID文件
    run_on_cluster "rm -f /tmp/*.pid /tmp/hadoop-*.pid"
}

case "$1" in
    ""|"all")
        stop_all_components
        ;;
        
    "force")
        print_banner
        print_warning "强制停止所有进程..."
        run_on_cluster "pkill -f 'flume\|kafka\|zookeeper\|hadoop'"
        run_on_cluster "rm -f /tmp/*.pid"
        print_success "强制停止完成"
        ;;
        
    *)
        echo "用法: $0 {all|force}"
        echo ""
        echo "停止模式:"
        echo "  all     正常停止所有组件"
        echo "  force   强制停止所有进程"
        exit 1
esac