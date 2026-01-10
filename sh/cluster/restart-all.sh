#!/bin/bash

# ============================================
# 重启所有组件
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

echo -e "${YELLOW}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                大数据集群重启脚本                        ║"
echo "║                版本 1.0.0                                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

print_warning "即将重启整个集群，这会导致服务中断！"
read -p "确认重启？(y/n): " confirm

if [ "$confirm" != "y" ]; then
    print_info "取消重启操作"
    exit 0
fi

# 停止所有组件
print_step "停止所有组件..."
$SCRIPTS_BASE/cluster/stop-all.sh all

# 等待
print_info "等待10秒..."
sleep 10

# 启动所有组件
print_step "启动所有组件..."
$SCRIPTS_BASE/cluster/start-all.sh all

print_success "集群重启完成！"