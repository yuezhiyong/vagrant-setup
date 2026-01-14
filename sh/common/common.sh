#!/bin/bash
# ============================================
# 公共函数库
# ============================================

# 注意：$SCRIPTS_BASE需要在调用此脚本前设置好
unset SCRIPTS_BASE
SCRIPTS_BASE=$(cd "$(dirname "$0")/.." && pwd)
echo "common shell ,SCRIPTS_BASE: $SCRIPTS_BASE"
source $SCRIPTS_BASE/common/color.sh

# 检查命令是否存在
check_command() {
    command -v $1 >/dev/null 2>&1 || {
        print_error "命令 $1 不存在，请先安装"
        return 1
    }
}

# 检查SSH连接
check_ssh_connection() {
    local host=$1
    $SSH_CMD $host "echo 'SSH连接成功'" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        print_error "无法连接到主机: $host"
        return 1
    fi
    return 0
}

# 检查所有节点SSH连接
check_all_ssh() {
    print_info "检查集群SSH连接..."
    for host in "${CLUSTER_HOSTS[@]}"; do
        if check_ssh_connection $host; then
            print_success "主机 $host SSH连接正常"
        else
            print_error "主机 $host SSH连接失败"
            return 1
        fi
    done
    return 0
}

# 在集群所有节点执行命令
run_on_cluster() {
    local cmd=$1
    local background=${2:-false}
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "在 $host 上执行: $cmd"
        if [ "$background" = true ]; then
            $SSH_CMD $host "$cmd" &
        else
            $SSH_CMD $host "$cmd"
            if [ $? -ne 0 ]; then
                print_error "在 $host 上执行命令 $cmd 失败"
                return 1
            fi
        fi
    done
    return 0
}

# 在指定节点执行命令
run_on_host() {
    local host=$1
    shift
    local capture_output=${CAPTURE_OUTPUT:-false}
    if [ "$capture_output" = true ]; then
        # 返回 stdout
        ssh "$host" "$@"
        return $?
    else
        ssh "$host" "$@"
        local rc=$?
        if [ $rc -ne 0 ]; then
            print_error "在 $host 上执行失败: $*"
        fi
        return $rc
    fi
}

# 检查进程是否运行
check_process() {
    local host=$1
    local process_name=$2
    local pid_file=$3
    
    if [ -n "$pid_file" ]; then
        $SSH_CMD $host "if [ -f '$pid_file' ] && ps -p \$(cat '$pid_file') >/dev/null 2>&1; then echo 'running'; else echo 'stopped'; fi"
    else
        $SSH_CMD $host "if pgrep -f '$process_name' >/dev/null 2>&1; then echo 'running'; else echo 'stopped'; fi"
    fi
}

# 等待进程启动
wait_for_process() {
    local host=$1
    local process_name=$2
    local pid_file=$3
    local timeout=${4:-30}
    local interval=1
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(check_process $host "$process_name" "$pid_file")
        if [ "$status" = "running" ]; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    return 1
}

# 分发文件到集群
distribute_file() {
    local src_file=$1
    local dest_dir=$2
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "分发文件到 $host:$dest_dir"
        $SCP_CMD $src_file $host:$dest_dir/
        if [ $? -ne 0 ]; then
            print_error "分发文件到 $host 失败"
            return 1
        fi
    done
    return 0
}

# 同步目录到集群
sync_directory() {
    local src_dir=$1
    local dest_dir=$2
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        print_info "同步目录到 $host:$dest_dir"
        rsync -avz -e "ssh $SSH_OPTS" $src_dir/ $host:$dest_dir/
        if [ $? -ne 0 ]; then
            print_error "同步目录到 $host 失败"
            return 1
        fi
    done
    return 0
}

# 创建符号链接
create_symlink() {
    local target=$1
    local link_name=$2
    
    for host in "${CLUSTER_HOSTS[@]}"; do
        run_on_host $host "ln -sfn $target $link_name"
    done
}

# 设置环境变量
setup_env() {
    local host=$1
    local env_content=$2
    
    $SSH_CMD $host "echo '$env_content' >> ~/.bashrc && source ~/.bashrc"
}

# 获取主机IP
get_host_ip() {
    local host=$1
    $SSH_CMD $host "hostname -I | awk '{print \$1}'"
}