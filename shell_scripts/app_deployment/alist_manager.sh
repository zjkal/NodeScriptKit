#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: disk_test.sh
# 功能: 这是一个 AList 安装与管理脚本，用于安装、更新、卸载 AList 或显示其管理菜单。
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

### === 逻辑正式开始 === ###

# Install dependencies
install_dependencies() {
    local sys_id=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2 | tr -d '"')
    local pkg="curl"
    info "检查并安装依赖: $pkg..."
    command -v "$pkg" &>/dev/null && { success "$pkg 已安装"; return 0; }
    case $sys_id in
        centos|rhel|fedora|rocky|almalinux)
            command -v dnf &>/dev/null && dnf install -y "$pkg" &>/dev/null || yum install -y "$pkg" &>/dev/null
            ;;
        debian|ubuntu|linuxmint)
            apt update -y &>/dev/null && apt install -y "$pkg" &>/dev/null
            ;;
        arch|manjaro)
            pacman -Syu --noconfirm "$pkg" &>/dev/null
            ;;
        opensuse|suse)
            zypper install -y "$pkg" &>/dev/null
            ;;
        alpine)
            apk add "$pkg" &>/dev/null
            ;;
        openwrt)
            opkg install "$pkg" &>/dev/null
            ;;
        *)
            danger "未知系统: $sys_id，请手动安装 $pkg"
            exit 1
            ;;
    esac
    command -v "$pkg" &>/dev/null || { danger "无法安装 $pkg"; exit 1; }
    success "$pkg 已安装"
}

# Validate installation path
validate_install_path() {
    local path=$1
    [[ -z "$path" ]] && path="/opt/alist"
    [[ "$path" == /* ]] || { danger "安装路径必须为绝对路径"; return 1; }
    echo "$path"
}

# Execute AList command
execute_alist_command() {
    local cmd=$1
    info "正在执行命令: $cmd"
    bash -c "$cmd"
    [[ $? -eq 0 ]] && { success "命令执行成功"; return 0; }
    danger "命令执行失败，请检查输出"
    return 1
}

# Main menu for AList management
alist_management() {
    check_root
    install_dependencies
    info "欢迎使用 AList 安装与管理脚本！"
    local action=""
    local options=("install" "update" "uninstall" "menu")

    while true; do
        info "请选择操作："
        select action in "${options[@]}"; do
            case "$action" in
                install|update|uninstall|menu)
                    break
                    ;;
                *)
                    danger "无效选择，请重试"
                    continue
                    ;;
            esac
        done
        [[ -n "$action" ]] && break
    done

    local cmd=""
    case "$action" in
        install)
            read -p "请输入安装路径（默认 /opt/alist）: " install_path
            install_path=$(validate_install_path "$install_path") || exit 1
            cmd="bash <(curl -sL https://alist.nn.ci/v3.sh) install $install_path"
            ;;
        update)
            cmd="bash <(curl -sL https://alist.nn.ci/v3.sh) update"
            ;;
        uninstall)
            cmd="bash <(curl -sL https://alist.nn.ci/v3.sh) uninstall"
            ;;
        menu)
            cmd="bash <(curl -sL https://alist.nn.ci/v3.sh)"
            ;;
    esac

    info "即将执行命令: $cmd"
    read -p "确认执行？(y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        execute_alist_command "$cmd" || exit 1
    else
        info "已取消"
        exit 0
    fi
}

# Main execution
alist_management