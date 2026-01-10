#!/bin/bash

# ============================================
# 组件管理脚本
# 用于单独管理组件的安装、卸载、状态检查
# ============================================

source $SCRIPTS_BASE/common/common.sh

show_component_status() {
    print_step "组件安装状态"
    
    local components=("Java" "Hadoop" "Zookeeper" "Kafka" "Flume")
    local paths=("$JDK_HOME" "$HADOOP_HOME" "$ZOOKEEPER_HOME" "$KAFKA_HOME" "$FLUME_HOME")
    
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
            esac
            
            if [ -n "$version" ]; then
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
    
    case $component in
        "jdk"|"java")
            install_component "jdk"
            setup_java
            ;;
        "hadoop")
            install_component "hadoop"
            setup_hadoop_config
            ;;
        "zookeeper"|"zk")
            install_component "zookeeper"
            setup_zookeeper_config
            ;;
        "kafka")
            install_component "kafka"
            setup_kafka_config
            ;;
        "flume")
            install_component "flume"
            setup_flume_config
            ;;
        *)
            print_error "未知组件: $component"
            return 1
            ;;
    esac
    
    # 更新环境变量
    setup_environment_variables
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
        *) print_error "未知组件: $component"; return 1 ;;
    esac
    
    if [ ! -d "$path" ]; then
        print_warning "组件 $component 未安装"
        return 0
    fi
    
    print_warning "即将删除组件 $component ($path)"
    read -p "确认删除？(y/n): " confirm
    
    if [ "$confirm" = "y" ]; then
        print_info "删除 $component ..."
        run_on_cluster "rm -rf $path"
        print_success "$component 已删除"
    else
        print_info "取消删除"
    fi
}

reinstall_component() {
    local component=$1
    
    print_info "重新安装 $component ..."
    
    # 先删除
    remove_component $component
    
    # 再安装
    install_single_component $component
}

case "$1" in
    "status")
        show_component_status
        ;;
        
    "install")
        if [ -z "$2" ]; then
            echo "用法: $0 install {jdk|hadoop|zookeeper|kafka|flume|all}"
            exit 1
        fi
        
        if [ "$2" = "all" ]; then
            $SCRIPTS_BASE/utils/install-all.sh components
        else
            install_single_component "$2"
        fi
        ;;
        
    "remove"|"uninstall")
        if [ -z "$2" ]; then
            echo "用法: $0 remove {jdk|hadoop|zookeeper|kafka|flume}"
            exit 1
        fi
        remove_component "$2"
        ;;
        
    "reinstall")
        if [ -z "$2" ]; then
            echo "用法: $0 reinstall {jdk|hadoop|zookeeper|kafka|flume}"
            exit 1
        fi
        reinstall_component "$2"
        ;;
        
    "list")
        print_info "可用的组件文件:"
        ls -la /vagrant/*.tar.gz /vagrant/*.tgz /vagrant/*.zip 2>/dev/null || echo "无文件"
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
        echo "可用组件: jdk, hadoop, zookeeper, kafka, flume"
        exit 1
esac