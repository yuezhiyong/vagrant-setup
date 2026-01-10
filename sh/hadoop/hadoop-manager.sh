#!/bin/bash

# ============================================
# Hadoop集群启动脚本
# ============================================

source $SCRIPTS_BASE/common/common.sh

start_hdfs() {
    print_step "启动HDFS"
    
    # 格式化NameNode（仅在第一次启动时）
    if [ "$1" = "format" ]; then
        print_warning "格式化NameNode，这将清除所有HDFS数据！"
        read -p "确认格式化？(y/n): " confirm
        if [ "$confirm" = "y" ]; then
            run_on_host $MASTER_NODE "$HADOOP_HOME/bin/hdfs namenode -format -force"
        fi
    fi
    
    # 启动NameNode
    print_info "启动NameNode..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/hadoop-daemon.sh start namenode"
    wait_for_process $MASTER_NODE "NameNode" "/tmp/hadoop-*-namenode.pid"
    
    # 启动DataNodes
    print_info "启动DataNodes..."
    run_on_cluster "$HADOOP_HOME/sbin/hadoop-daemon.sh start datanode" true
    sleep 3
    
    # 启动SecondaryNameNode
    print_info "启动SecondaryNameNode..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/hadoop-daemon.sh start secondarynamenode"
    
    # 检查HDFS状态
    print_info "检查HDFS状态..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/bin/hdfs dfsadmin -report"
}

stop_hdfs() {
    print_step "停止HDFS"
    
    # 停止SecondaryNameNode
    print_info "停止SecondaryNameNode..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/hadoop-daemon.sh stop secondarynamenode"
    
    # 停止DataNodes
    print_info "停止DataNodes..."
    run_on_cluster "$HADOOP_HOME/sbin/hadoop-daemon.sh stop datanode"
    
    # 停止NameNode
    print_info "停止NameNode..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/hadoop-daemon.sh stop namenode"
}

start_yarn() {
    print_step "启动YARN"
    
    # 启动ResourceManager
    print_info "启动ResourceManager..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/yarn-daemon.sh start resourcemanager"
    
    # 启动NodeManagers
    print_info "启动NodeManagers..."
    run_on_cluster "$HADOOP_HOME/sbin/yarn-daemon.sh start nodemanager" true
    
    # 启动JobHistoryServer
    print_info "启动JobHistoryServer..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/mr-jobhistory-daemon.sh start historyserver"
    
    # 检查YARN状态
    print_info "检查YARN状态..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/bin/yarn node -list"
}

stop_yarn() {
    print_step "停止YARN"
    
    # 停止JobHistoryServer
    print_info "停止JobHistoryServer..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/mr-jobhistory-daemon.sh stop historyserver"
    
    # 停止NodeManagers
    print_info "停止NodeManagers..."
    run_on_cluster "$HADOOP_HOME/sbin/yarn-daemon.sh stop nodemanager"
    
    # 停止ResourceManager
    print_info "停止ResourceManager..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/yarn-daemon.sh stop resourcemanager"
}

start_historyserver() {
    print_info "启动JobHistoryServer..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/mr-jobhistory-daemon.sh start historyserver"
}

stop_historyserver() {
    print_info "停止JobHistoryServer..."
    run_on_host $MASTER_NODE "$HADOOP_HOME/sbin/mr-jobhistory-daemon.sh stop historyserver"
}

check_hadoop_status() {
    print_step "Hadoop集群状态"
    
    print_info "HDFS进程状态:"
    for host in "${CLUSTER_HOSTS[@]}"; do
        local nn_status=$(check_process $host "NameNode")
        local dn_status=$(check_process $host "DataNode")
        local snn_status=$(check_process $host "SecondaryNameNode")
        echo "  $host: NameNode[$nn_status] DataNode[$dn_status] SecondaryNameNode[$snn_status]"
    done
    
    print_info "YARN进程状态:"
    for host in "${CLUSTER_HOSTS[@]}"; do
        local rm_status=$(check_process $host "ResourceManager")
        local nm_status=$(check_process $host "NodeManager")
        local jhs_status=$(check_process $host "JobHistoryServer")
        echo "  $host: ResourceManager[$rm_status] NodeManager[$nm_status] JobHistoryServer[$jhs_status]"
    done
}

case "$1" in
    start)
        start_hdfs "$2"
        start_yarn
        start_historyserver
        check_hadoop_status
        ;;
        
    stop)
        stop_yarn
        stop_hdfs
        stop_historyserver
        check_hadoop_status
        ;;
        
    restart)
        stop_yarn
        stop_hdfs
        sleep 3
        start_hdfs
        start_yarn
        check_hadoop_status
        ;;
        
    status)
        check_hadoop_status
        ;;
        
    start-hdfs)
        start_hdfs "$2"
        ;;
        
    stop-hdfs)
        stop_hdfs
        ;;
        
    start-yarn)
        start_yarn
        ;;
        
    stop-yarn)
        stop_yarn
        ;;
        
    format)
        start_hdfs "format"
        ;;
        
    *)
        echo "用法: $0 {start|stop|restart|status|start-hdfs|stop-hdfs|start-yarn|stop-yarn|format}"
        echo ""
        echo "命令说明:"
        echo "  start [format]   启动整个Hadoop集群，可选格式化"
        echo "  stop             停止整个Hadoop集群"
        echo "  restart          重启整个Hadoop集群"
        echo "  status           查看Hadoop集群状态"
        echo "  start-hdfs       只启动HDFS"
        echo "  stop-hdfs        只停止HDFS"
        echo "  start-yarn       只启动YARN"
        echo "  stop-yarn        只停止YARN"
        echo "  format           格式化NameNode并启动"
        exit 1
esac