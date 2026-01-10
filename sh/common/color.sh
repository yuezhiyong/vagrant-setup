#!/bin/bash

# ============================================
# 颜色输出函数
# ============================================

# 颜色定义
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[1;37m'
export NC='\033[0m' # No Color

# 带颜色的打印函数
print_color() {
    local color=$1
    local level=$2
    local message=$3
    echo -e "${color}[$level]${NC} $message"
}

print_info() {
    print_color "$BLUE" "INFO" "$1"
}

print_success() {
    print_color "$GREEN" "SUCCESS" "$1"
}

print_warning() {
    print_color "$YELLOW" "WARNING" "$1"
}

print_error() {
    print_color "$RED" "ERROR" "$1"
}

print_debug() {
    print_color "$MAGENTA" "DEBUG" "$1"
}

print_step() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

print_divider() {
    echo -e "${WHITE}----------------------------------------${NC}"
}

# 带时间的日志
log_with_time() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case $level in
        "INFO") print_color "$BLUE" "$timestamp INFO" "$message" ;;
        "SUCCESS") print_color "$GREEN" "$timestamp SUCCESS" "$message" ;;
        "WARNING") print_color "$YELLOW" "$timestamp WARNING" "$message" ;;
        "ERROR") print_color "$RED" "$timestamp ERROR" "$message" ;;
        *) print_color "$NC" "$timestamp $level" "$message" ;;
    esac
}