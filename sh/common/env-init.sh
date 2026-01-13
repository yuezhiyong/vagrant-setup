#!/bin/bash
# 环境初始化脚本

source /opt/sh/common/config.sh

# 初始化所有节点
init_all_nodes() {
    print_info "开始初始化所有集群节点..."
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "初始化节点: $host"
        
        # 创建目录结构
        ssh $host "mkdir -p $DATA_HOME/{zookeeper,kafka,hadoop/{namenode,datanode}}"
        ssh $host "mkdir -p $LOG_HOME/{zookeeper,kafka,flume,hadoop}"
        ssh $host "mkdir -p $MODULE_HOME"
        
        # 设置环境变量
        ssh $host "echo 'export JAVA_HOME=$JAVA_HOME' >> /etc/profile"
        ssh $host "echo 'export PATH=\$PATH:\$JAVA_HOME/bin' >> /etc/profile"
        ssh $host "source /etc/profile"
    done
    
    print_success "集群节点初始化完成"
}

# 检查Java安装
check_java() {
    print_info "检查Java安装..."
    for host in "${CLUSTER_HOSTS[@]}"; do
        java_version=$(ssh $host "$JAVA_HOME/bin/java -version 2>&1 | head -1")
        if [[ $java_version == *"version"* ]]; then
            print_info "$host: Java已安装 - $java_version"
        else
            print_error "$host: Java未安装或配置错误"
        fi
    done
}

# 分发组件到所有节点
distribute_component() {
    local component=$1
    local local_path=$2
    
    print_info "分发 $component 到所有节点..."
    distribute_file $local_path $MODULE_HOME/
}

# 主函数
main() {
    case "$1" in
        init)
            init_all_nodes
            ;;
        check-java)
            check_java
            ;;
        *)
            echo "用法: $0 {init|check-java}"
            exit 1
            ;;
    esac
}

main "$@"