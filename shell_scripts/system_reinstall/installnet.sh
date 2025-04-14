#!/bin/bash

### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"

### === 权限检查 === ###
[[ $EUID -ne 0 ]] && echo -e "\033[31m[错误] 请以root用户或sudo运行此脚本！\033[0m" && exit 1

### === 工具检查 === ###
check_dependencies() {
  for tool in curl wget; do
    if ! command -v $tool >/dev/null 2>&1; then
      echo -e "\033[31m[错误] 缺少依赖：$tool，请先安装！\033[0m"
      exit 1
    fi
  done
}

### === 颜色与提示函数 === ###
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
BLUE='\033[34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warning() { echo -e "${YELLOW}[提示]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }

### === 函数：定义系统和版本 === ###
define_systems() {
    SYSTEMS=( "debian" "ubuntu" "centos" "alpine" "kali" "almalinux" "rockylinux" "fedora" "windows" )
    declare -gA VERSIONS
    VERSIONS["debian"]="12 11 10 9"
    VERSIONS["ubuntu"]="22.04 20.04 18.04 16.04"
    VERSIONS["centos"]="9 8 7"
    VERSIONS["alpine"]="edge 3.21 3.20 3.19 3.18"
    VERSIONS["kali"]="rolling"
    VERSIONS["almalinux"]="9 8"
    VERSIONS["rockylinux"]="9 8"
    VERSIONS["fedora"]="41 40 39 38"
    VERSIONS["windows"]="11 10"
    DEFAULT_PASSWORD="LeitboGi0ro"
    DEFAULT_PORT="22"
}

### === 函数：选择系统 === ###
select_system() {
    info "请选择要安装的系统："
    select SYSTEM in "${SYSTEMS[@]}"; do
        if [[ -n "$SYSTEM" ]]; then
            success "已选择系统：$SYSTEM"
            break
        else
            warning "无效选择，请重试"
        fi
    done
}

### === 函数：选择或自定义版本 === ###
select_version() {
    VERSION=""
    if [[ -n "${VERSIONS[$SYSTEM]}" ]]; then
        OPTIONS=(${VERSIONS[$SYSTEM]})
        info "可用版本（降序）："
        select CHOICE in "${OPTIONS[@]}" "手动输入版本" "跳过（不指定）"; do
            if [[ "$CHOICE" == "跳过（不指定）" ]]; then
                VERSION=""
                info "不指定版本"
                break
            elif [[ "$CHOICE" == "手动输入版本" ]]; then
                read -p "请输入自定义版本号: " VERSION
                break
            elif [[ -n "$CHOICE" ]]; then
                VERSION="$CHOICE"
                success "已选择版本：$VERSION"
                break
            else
                warning "无效选择，请重试"
            fi
        done
    else
        info "$SYSTEM 无需指定版本"
    fi
}

### === 函数：选择架构 === ###
select_arch() {
    ARCH_FLAG=""
    if [[ "$SYSTEM" != "windows" ]]; then
        info "请选择架构（默认自动检测）:"
        select ARCH in "64-bit" "32-bit" "arm64" "跳过（自动检测）"; do
            if [[ -z "$REPLY" ]]; then
                ARCH_FLAG=""
                break
            fi
            case "$ARCH" in
                "64-bit") ARCH_FLAG="-v 64"; break ;;
                "32-bit") ARCH_FLAG="-v 32"; break ;;
                "arm64") ARCH_FLAG="-v arm64"; break ;;
                "跳过（自动检测）") ARCH_FLAG=""; break ;;
                *) warning "无效选择，请重试" ;;
            esac
        done
    fi
}

### === 函数：设置密码 === ###
input_password() {
    warning "请输入密码（留空使用默认密码）: "
    read -rs PASSWORD
    echo
    PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
    PASSWORD_ARG="-pwd '$PASSWORD'"
    success "使用密码：$PASSWORD"
}

### === 函数：设置 SSH 端口 === ###
input_ssh_port() {
    echo -en "${YELLOW}请输入 SSH 端口（默认 $DEFAULT_PORT）: ${NC}"
    read SSH_PORT
    SSH_PORT=${SSH_PORT:-$DEFAULT_PORT}
    SSH_PORT_ARG="-port $SSH_PORT"
    success "SSH 端口：$SSH_PORT"
}

### === 函数：设置镜像源或 Windows 镜像 === ###
input_mirror_or_url() {
    MIRROR_ARG=""
    if [[ "$SYSTEM" != "windows" ]]; then
        echo -en "${YELLOW}请输入自定义镜像源（留空使用默认）: ${NC}"
        read MIRROR
        [[ -n "$MIRROR" ]] && MIRROR_ARG="--mirror '$MIRROR'"
    else
        echo -en "${YELLOW}请输入 Windows 镜像 URL: ${NC}"
        read WINDOWS_URL
        if [[ -z "$WINDOWS_URL" ]]; then
            error "Windows 安装必须提供镜像 URL"
            exit 1
        fi
    fi
}

### === 函数：设置网络参数 === ###
input_network_params() {
    NET_ARG=""
    echo -en "${YELLOW}是否自定义网络参数？(y/n): ${NC}"
    read NET_CHOICE
    if [[ "$NET_CHOICE" =~ ^[Yy]$ ]]; then
        read -p "IPv4 地址（留空使用 DHCP）: " IP4_ADDR
        if [[ -n "$IP4_ADDR" ]]; then
            read -p "IPv4 子网掩码: " IP4_MASK
            read -p "IPv4 网关: " IP4_GATE
            read -p "IPv4 DNS（默认 8.8.8.8 1.1.1.1）: " IP4_DNS
            IP4_DNS=${IP4_DNS:-"8.8.8.8 1.1.1.1"}
            NET_ARG="$NET_ARG --ip-addr '$IP4_ADDR' --ip-mask '$IP4_MASK' --ip-gate '$IP4_GATE' --ip-dns '$IP4_DNS'"
        fi
        read -p "IPv6 地址（留空跳过）: " IP6_ADDR
        if [[ -n "$IP6_ADDR" ]]; then
            read -p "IPv6 前缀长度: " IP6_MASK
            read -p "IPv6 网关: " IP6_GATE
            read -p "IPv6 DNS（默认 2001:4860:4860::8888）: " IP6_DNS
            IP6_DNS=${IP6_DNS:-"2001:4860:4860::8888 2606:4700:4700::1111"}
            NET_ARG="$NET_ARG --ip6-addr '$IP6_ADDR' --ip6-mask '$IP6_MASK' --ip6-gate '$IP6_GATE' --ip6-dns '$IP6_DNS'"
        else
            NET_ARG="$NET_ARG --setipv6 '0'"
        fi
    fi
}

### === 函数：构建命令 === ###
build_command() {
    CMD="bash <(wget -qO- https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh)"
    case "$SYSTEM" in
        "windows") CMD="$CMD -dd '$WINDOWS_URL'" ;;
        *) CMD="$CMD -$SYSTEM $VERSION $ARCH_FLAG" ;;
    esac
    CMD="$CMD $PASSWORD_ARG $SSH_PORT_ARG $MIRROR_ARG $NET_ARG"
}

### === 函数：执行确认 === ###
confirm_and_run() {
    info "即将执行命令："
    echo -e "${BOLD}${CMD}${NC}"
    echo -en "${YELLOW}是否确认执行？此操作将格式化系统盘！(y/n): ${NC}"
    read CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        success "开始执行安装流程..."
        eval "$CMD"
    else
        warning "已取消执行。"
        exit 0
    fi
}

### === 主流程 === ###
main() {
    check_root
    check_dependencies
    define_systems
    
    info "欢迎使用 InstallNET.sh 安装脚本！"
    info "Github： https://github.com/leitbogioro/Tools"
    info "当前时间：$(date '+%Y-%m-%d %H:%M:%S')"

    select_system
    select_version
    select_arch
    input_password
    input_ssh_port
    input_mirror_or_url
    input_network_params
    build_command
    confirm_and_run
}

main
