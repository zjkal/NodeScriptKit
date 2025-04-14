#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: disk_test.sh
# 功能: 这是一个磁盘测试脚本，用于下载、运行 Hard Disk Sentinel 并测试磁盘写入量，完成后清理
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
    local packages=("wget" "gunzip")
    info "检查并安装依赖: ${packages[*]}..."
    for pkg in "${packages[@]}"; do
        command -v "$pkg" &>/dev/null && continue
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
    done
    success "所有依赖已安装"
}

# Download Hard Disk Sentinel
download_hdsentinel() {
    local url="https://www.hdsentinel.com/hdslin/hdsentinel-019c-x64.gz"
    local file="hdsentinel-019c-x64.gz"
    info "正在下载 Hard Disk Sentinel..."
    wget -c "$url" -O "$file" &>/dev/null
    [[ $? -eq 0 ]] && { success "下载完成"; return 0; }
    danger "下载失败，请检查网络连接或 URL 是否有效"
    exit 1
}

# Extract file
extract_hdsentinel() {
    local file="hdsentinel-019c-x64.gz"
    info "正在解压 $file..."
    gunzip "$file" &>/dev/null
    [[ $? -eq 0 ]] && { success "解压完成"; return 0; }
    danger "解压失败，请检查文件是否损坏"
    exit 1
}

# Set execute permissions
set_permissions() {
    local file="hdsentinel-019c-x64"
    info "设置执行权限..."
    chmod 755 "$file" &>/dev/null
    [[ -x "$file" ]] && { success "权限设置完成"; return 0; }
    danger "设置执行权限失败"
    exit 1
}

# Run test
run_test() {
    local file="hdsentinel-019c-x64"
    info "正在运行 Hard Disk Sentinel 测试..."
    ./"$file"
    [[ $? -eq 0 ]] && { success "测试完成，结果已输出"; return 0; }
    danger "测试执行失败，请检查工具输出"
    return 1
}

# Clean up
cleanup() {
    local file="hdsentinel-019c-x64"
    info "正在清理测试文件..."
    rm -f "$file" &>/dev/null
    [[ $? -eq 0 ]] && { success "测试文件已删除"; return 0; }
    warn "删除文件失败，请手动清理"
    return 1
}

# Main execution
main() {
    install_dependencies
    download_hdsentinel
    extract_hdsentinel
    set_permissions
    run_test
    cleanup
    success "脚本执行完毕"
}

main