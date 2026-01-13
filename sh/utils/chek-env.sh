#!/bin/bash

# ============================================
# 环境检查脚本
# ============================================

source $SCRIPTS_BASE/common/common.sh

check_environment() {
    print_step "大数据集群环境检查"
    
    # 1. 检查SSH
    check_all_ssh
    
    # 2. 检查Java
    print_info "检查Java安装..."
    for host in "${CLUSTER_HOSTS[@]}"; do
        local java_version=$(run_on_host $host "java -version 2>&1 | head -1")
        if [[ $java_version == *"version"* ]]; then
            print_success "$host: $java_version"
        else
            print_error "$host: Java未安装"
        fi
    done
    
    # 3. 检查软件安装
    print_info "检查软件安装..."
    local software=("Hadoop" "Zookeeper" "Kafka" "Flume")
    local paths=("$HADOOP_HOME" "$ZOOKEEPER_HOME" "$KAFKA_HOME" "$FLUME_HOME")
    
    for i in "${!software[@]}"; do
        local sw="${software[$i]}"
        local path="${paths[$i]}"
        
        if run_on_host $MASTER_NODE "[ -d '$path' ]"; then
            print_success "$sw: 已安装 ($path)"
        else
            print_warning "$sw: 未安装"
        fi
    done
    
    # 4. 检查目录权限
    print_info "检查目录权限..."
    for host in "${CLUSTER_HOSTS[@]}"; do
        local dirs=("$MODULE_BASE" "$LOG_DIR" "$ZK_DATA_DIR" "$KAFKA_LOG_DIR")
        for dir in "${dirs[@]}"; do
            if run_on_host $host "[ -w '$dir' ]"; then
                print_success "$host: $dir 可写"
            else
                print_error "$host: $dir 不可写"
            fi
        done
    done
    
    # 5. 检查防火墙
    print_info "检查防火墙..."
    for host in "${CLUSTER_HOSTS[@]}"; do
        local firewall=$(run_on_host $host "systemctl is-active firewalld 2>/dev/null || echo 'inactive'")
        if [ "$firewall" = "active" ]; then
            print_warning "$host: 防火墙运行中，确保相关端口开放"
        fi
    done
    
    print_divider
    print_success "环境检查完成"
}

check_environment