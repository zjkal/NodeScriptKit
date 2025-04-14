#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: hostname_management.sh
# 功能: 这是一个主机名管理脚本，用于永久修改本机的主机名
# 作者: rouxyang <https://www.nodeseek.com/space/29457>
# 创建日期: 2025-04-13

### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"
echo -e "\033[32m[信息] 脚本版本: $SCRIPT_VERSION\033[0m"

### === 退出状态码 === ###
EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_INTERRUPT=130 # Ctrl+C 退出码

### === 权限检查 === ###
[[ $EUID -ne 0 ]] && echo -e "\033[31m[错误] 请以root用户或sudo运行此脚本！\033[0m" && exit 1

### === 颜色定义 === ###
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[34m';
NC='\033[0m'


### === 彩色输出函数 === ###
success() { printf "${GREEN}%b${NC} ${@:2}\n" "$1"; }
info() { printf "${CYAN}%b${NC} ${@:2}\n" "$1"; }
danger() { printf "\n${RED}[错误] %b${NC}\n" "$@"; }
warn() { printf "${YELLOW}[警告] %b${NC}\n" "$@"; }

### === 信号捕获 === ###
cleanup() {
    log "INFO" "脚本被中断..."
    echo -e "${YELLOW}[警告] 脚本已退出！${NC}"
    exit $EXIT_INTERRUPT
}
trap cleanup SIGINT SIGTERM

# Modify hostname
# Modify hostname
modify_hostname() {
    clear
    local current_hostname=$(hostname)
    info "当前主机名: $current_hostname"

    read -p "请输入新的主机名: " new_hostname
    if [ -z "$new_hostname" ]; then
        danger "主机名不能为空"
        return 1
    fi

    # Validate hostname (basic check for RFC 1123 compliance)
    if ! echo "$new_hostname" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9.-]{0,253}[a-zA-Z0-9]$'; then
        danger "无效的主机名！主机名应只包含字母、数字、点号和连字符，且长度不超过255字符"
        return 1
    fi

    # Update /etc/hostname (standard for most modern distributions)
    if [ -w /etc/hostname ]; then
        echo "$new_hostname" > /etc/hostname
    else
        warn "/etc/hostname 不可写，尝试其他配置路径"
    fi

    # Update /etc/hosts to ensure localhost mapping
    if [ -w /etc/hosts ]; then
        sed -i "s/127\.0\.1\.1\s\+$current_hostname/127.0.1.1\t$new_hostname/" /etc/hosts
        # Add entry if it doesn't exist
        if ! grep -q "127.0.1.1.*$new_hostname" /etc/hosts; then
            echo "127.0.1.1	$new_hostname" >> /etc/hosts
        fi
    else
        warn "/etc/hosts 不可写，可能影响主机名解析"
    fi

    # Handle distribution-specific hostname configurations
    # Red Hat-based systems (CentOS, RHEL, Fedora)
    if [ -w /etc/sysconfig/network ]; then
        sed -i "s/HOSTNAME=.*/HOSTNAME=$new_hostname/" /etc/sysconfig/network
        # Add if not present
        if ! grep -q "HOSTNAME=" /etc/sysconfig/network; then
            echo "HOSTNAME=$new_hostname" >> /etc/sysconfig/network
        fi
    fi

    # Slackware
    if [ -w /etc/HOSTNAME ]; then
        echo "$new_hostname" > /etc/HOSTNAME
    fi

    # Arch Linux (uses /etc/hostname, but ensure it's explicit)
    if [ -f /etc/arch-release ] && [ -w /etc/hostname ]; then
        echo "$new_hostname" > /etc/hostname
    fi

    # Gentoo
    if [ -w /etc/conf.d/hostname ]; then
        sed -i "s/hostname=.*/hostname=\"$new_hostname\"/" /etc/conf.d/hostname
        if ! grep -q "hostname=" /etc/conf.d/hostname; then
            echo "hostname=\"$new_hostname\"" >> /etc/conf.d/hostname
        fi
    fi

    # Apply hostname dynamically (optional, for current session)
    if command -v hostnamectl &>/dev/null; then
        hostnamectl set-hostname "$new_hostname"
    elif command -v hostname &>/dev/null; then
        hostname "$new_hostname"
    else
        warn "无法动态设置主机名，需重启以应用更改"
    fi

    success "主机名已永久更改为: $new_hostname"
    info "建议重启系统以确保所有服务识别新主机名"
}

# Main execution
modify_hostname