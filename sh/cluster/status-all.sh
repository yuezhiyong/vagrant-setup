#!/bin/bash

# ============================================
# 查看所有组件状态
# ============================================

SCRIPTS_BASE=$(cd "$(dirname "$0")/.." && pwd)
# Temporarily set SCRIPTS_BASE for loading config files
export SCRIPTS_BASE
source $SCRIPTS_BASE/common/config.sh
# Override SCRIPTS_BASE with the actual script location
unset SCRIPTS_BASE
SCRIPTS_BASE=$(cd "$(dirname "$0")/.." && pwd)
export SCRIPTS_BASE
source $SCRIPTS_BASE/common/color.sh
source $SCRIPTS_BASE/common/common.sh

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                大数据集群状态监控                        ║"
    echo "║                版本 1.0.0                                ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "集群节点: ${YELLOW}${CLUSTER_HOSTS[*]}${NC}"
    echo -e "管理节点: ${YELLOW}$MASTER_NODE${NC}"
    echo -e "当前时间: ${YELLOW}$(date)${NC}"
    print_divider
}

check_all_status() {
    print_banner
    
    # 1. 系统状态
    print_step "系统状态"
    for host in "${CLUSTER_HOSTS[@]}"; do
        local load=$(run_on_host $host "uptime | awk -F'load average:' '{print \$2}'")
        local memory=$(run_on_host $host "free -h | grep Mem | awk '{print \$4}'")
        local disk=$(run_on_host $host "df -h / | tail -1 | awk '{print \$4}'")
        echo "  $host: 负载$load 内存可用:$memory 根分区可用:$disk"
    done
    
    print_divider
    
    # 2. Zookeeper状态
    print_step "Zookeeper集群状态"
    $SCRIPTS_BASE/zookeeper/zk-manager.sh status
    
    print_divider
    
    # 3. Kafka状态
    print_step "Kafka集群状态"
    $SCRIPTS_BASE/kafka/kafka-manager.sh status
    
    print_divider
    
    # 4. Hadoop状态
    print_step "Hadoop集群状态"
    $SCRIPTS_BASE/hadoop/hadoop-manager.sh status
    
    print_divider
    
    # 5. Flume状态（如果配置了）
    if [ -d "$SCRIPTS_BASE/flume" ]; then
        print_step "Flume集群状态"
        $SCRIPTS_BASE/flume/flume-manager.sh status 2>/dev/null || echo "  Flume未配置或未运行"
    fi
    
    print_divider
    
    # 6. 服务端口检查
    print_step "服务端口检查"
    for host in "${CLUSTER_HOSTS[@]}"; do
        echo -n "  $host: "
        local ports=""
        $SSH_CMD $host "nc -z localhost 2181 2>/dev/null" && ports+="ZK "
        $SSH_CMD $host "nc -z localhost 9092 2>/dev/null" && ports+="Kafka "
        $SSH_CMD $host "nc -z localhost 9000 2>/dev/null" && ports+="HDFS "
        $SSH_CMD $host "nc -z localhost 8088 2>/dev/null" && ports+="YARN "
        echo "${ports:-无服务运行}"
    done
}

check_all_status