#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: port_management.sh
# 功能: 这是一个端口管理脚本，用于管理本机的端口。
# 作者: rouxyang <https://www.nodeseek.com/space/29457>
# 创建日期: 2025-04-13
# 许可证: MIT

### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"
SCRIPT_NAME="用于管理本机的端口"
SCRIPT_AUTHOR="[@Rouxyang] <https://www.nodeseek.com/space/29457>"

echo -e "\033[33m[信息] $SCRIPT_NAME ，版本: $SCRIPT_VERSION\033[0m"
echo -e "\033[33m[作者] $SCRIPT_AUTHOR\033[0m"

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


# System info
sys_id=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2 | tr -d '"')

# Software dependencies
software_list=("net-tools")  # 示例扩展列表

# 关联数组：映射软件包到检查命令，支持多命令和系统特定配置
# 格式：["包名@系统"]="命令1 命令2 ..." 或 ["包名"]="命令1 命令2 ..."
declare -A pkg_check_commands=(
    ["net-tools"]="ifconfig netstat"             # 默认检查 ifconfig 或 netstat
    ["net-tools@alpine"]="ifconfig"             # Alpine 特定的检查命令
)

# Install software
install_software() {
    if [ ${#software_list[@]} -eq 0 ]; then
        danger "software_list 中未指定任何软件包"
        exit 1
    fi

    # 检查命令是否存在
    check_command() {
        local cmd="$1"
        command -v "$cmd" &>/dev/null
    }

    # 使用包管理器检查包是否已安装
    check_package_installed() {
        local pkg="$1"
        case ${sys_id} in
            centos|rhel|fedora|rocky|almalinux)
                rpm -q "$pkg" &>/dev/null
                ;;
            debian|ubuntu|linuxmint)
                dpkg -l "$pkg" &>/dev/null
                ;;
            arch|manjaro)
                pacman -Qs "$pkg" &>/dev/null
                ;;
            opensuse|suse)
                zypper se -i "$pkg" &>/dev/null
                ;;
            alpine)
                apk info "$pkg" &>/dev/null
                ;;
            openwrt)
                opkg status "$pkg" &>/dev/null
                ;;
            *)
                return 1  # 未知系统，跳过包管理器检查
                ;;
        esac
    }

    # 动态检测系统特定的包名
    get_system_package_name() {
        local pkg="$1"
        local sys_pkg="$pkg"  # 默认使用原始包名

        case ${sys_id} in
            alpine)
                # Alpine 特定规则：尝试已知映射
                case "$pkg" in
                    iproute2)
                        sys_pkg="iproute"  # Alpine 上 iproute2 可能是 iproute
                        ;;
                    *)
                        # 使用 apk search 查找（避免每次都调用以提高性能）
                        if apk search "$pkg" | grep -q "^${pkg}-"; then
                            sys_pkg="$pkg"
                        fi
                        ;;
                esac
                ;;
            debian|ubuntu|linuxmint)
                # 使用 apt-cache search 查找
                if apt-cache show "$pkg" &>/dev/null; then
                    sys_pkg="$pkg"
                fi
                ;;
            centos|rhel|fedora|rocky|almalinux)
                # 使用 dnf/yum provides 查找
                if check_command dnf && dnf provides "$pkg" &>/dev/null; then
                    sys_pkg="$pkg"
                elif check_command yum && yum provides "$pkg" &>/dev/null; then
                    sys_pkg="$pkg"
                fi
                ;;
            arch|manjaro)
                # 使用 pacman -Ss 查找
                if pacman -Ss "^${pkg}$" &>/dev/null; then
                    sys_pkg="$pkg"
                fi
                ;;
            opensuse|suse)
                # 使用 zypper search 查找
                if zypper se "$pkg" &>/dev/null; then
                    sys_pkg="$pkg"
                fi
                ;;
            openwrt)
                # 使用 opkg list 查找
                if opkg list | grep -q "^${pkg} -"; then
                    sys_pkg="$pkg"
                fi
                ;;
            *)
                # 未知系统，直接使用原始包名
                ;;
        esac

        echo "$sys_pkg"
    }

    install_package() {
        local pkg="$1"
        # 动态获取系统特定的包名
        local install_pkg
        install_pkg=$(get_system_package_name "$pkg")
        # 获取检查命令，优先使用系统特定配置
        local check_key="${pkg}@${sys_id}"
        local check_cmds="${pkg_check_commands[$check_key]:-${pkg_check_commands[$pkg]:-$pkg}}"

        info "正在处理 $pkg (安装包名: $install_pkg)..."

        # 检查任意一个命令是否存在
        local cmd_found=0
        for cmd in $check_cmds; do
            if check_command "$cmd"; then
                cmd_found=1
                break
            fi
        done

        # 如果命令存在或包管理器确认已安装，则跳过安装
        if [ $cmd_found -eq 1 ] || check_package_installed "$install_pkg"; then
            success "$pkg 已安装"
            return 1
        fi

        info "正在安装 $install_pkg..."
        case ${sys_id} in
            centos|rhel|fedora|rocky|almalinux)
                if check_command dnf; then
                    dnf -y update &>/dev/null && dnf install -y epel-release &>/dev/null
                    dnf install -y "$install_pkg" &>/dev/null
                elif check_command yum; then
                    yum -y update &>/dev/null && yum install -y epel-release &>/dev/null
                    yum install -y "$install_pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 yum 或 dnf"
                    return 1
                fi
                ;;
            debian|ubuntu|linuxmint)
                apt update -y &>/dev/null
                apt install -y "$install_pkg" &>/dev/null
                ;;
            arch|manjaro)
                if check_command pacman; then
                    pacman -Syu --noconfirm &>/dev/null
                    pacman -S --noconfirm "$install_pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 pacman"
                    return 1
                fi
                ;;
            opensuse|suse)
                if check_command zypper; then
                    zypper refresh &>/dev/null
                    zypper install -y "$install_pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 zypper"
                    return 1
                fi
                ;;
            alpine)
                if check_command apk; then
                    apk update &>/dev/null
                    apk add "$install_pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 apk"
                    return 1
                fi
                ;;
            openwrt)
                if check_command opkg; then
                    opkg update &>/dev/null
                    opkg install "$install_pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 opkg"
                    return 1
                fi
                ;;
            *)
                danger "未知系统: ${sys_id}，请手动安装 $install_pkg"
                return 1
                ;;
        esac

        # 再次检查命令或包状态
        cmd_found=0
        for cmd in $check_cmds; do
            if check_command "$cmd"; then
                cmd_found=1
                break
            fi
        done

        if [ $cmd_found -eq 1 ] || check_package_installed "$install_pkg"; then
            success "$pkg 安装成功"
            return 0
        else
            danger "无法安装 $pkg"
            return 1
        fi
    }
}

# Manage ports
manage_ports() {
    clear
    install_software
    while true; do
        info "端口管理"
        echo "------------------------"
        echo "1. 查看所有端口"
        echo "2. 查看指定端口"
        echo "3. 强制停止使用端口的程序"
        echo "4. 关闭指定端口"
        echo "0. 退出"
        echo "------------------------"
        read -p "请输入您的选择: " choice

        case $choice in
            1)
                info "正在显示所有开放端口..."
                if command -v ss &>/dev/null; then
                    ss -tulnape
                elif command -v netstat &>/dev/null; then
                    netstat -tulnp
                else
                    danger "未找到 ss 或 netstat，正在安装 net-tools..."
                    software_list=("net-tools")
                    install_software
                    netstat -tulnp
                fi
                ;;
            2)
                read -p "请输入要查看的端口号 (多个端口用逗号分隔): " ports
                if [ -z "$ports" ]; then
                    danger "端口号不能为空"
                    continue
                fi
                info "正在检查端口: $ports..."
                IFS=',' read -ra port_array <<< "$ports"
                for port in "${port_array[@]}"; do
                    port=$(echo "$port" | tr -d '[:space:]')
                    if [[ ! "$port" =~ ^[0-9]+$ || $port -lt 1 || $port -gt 65535 ]]; then
                        danger "无效的端口号: $port"
                        continue
                    fi
                    if command -v ss &>/dev/null; then
                        result=$(ss -tulnape | grep ":$port " || echo "端口 $port 未被使用")
                        if [ -n "$result" ]; then
                            echo "$result"
                        fi
                    elif command -v netstat &>/dev/null; then
                        result=$(netstat -tulnp | grep ":$port " || echo "端口 $port 未被使用")
                        if [ -n "$result" ]; then
                            echo "$result"
                        fi
                    else
                        danger "未找到 ss 或 netstat，正在安装 net-tools..."
                        software_list=("net-tools")
                        install_software
                        netstat -tulnp | grep ":$port " || echo "端口 $port 未被使用"
                    fi
                done
                ;;
            3)
                read -p "请输入要停止的端口号: " port
                if [[ ! "$port" =~ ^[0-9]+$ || $port -lt 1 || $port -gt 65535 ]]; then
                    danger "无效的端口号"
                    continue
                fi
                info "正在查找使用端口 $port 的程序..."
                pids=$(ss -tulnape | grep ":$port " | awk '{print $NF}' | grep -o '[0-9]\+')
                if [ -z "$pids" ]; then
                    warn "未找到使用端口 $port 的程序"
                    continue
                fi
                for pid in $pids; do
                    proc_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "未知")
                    read -p "发现进程 $proc_name (PID: $pid) 使用端口 $port，是否强制终止？(y/n): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        kill -9 "$pid" 2>/dev/null
                        if ! ps -p "$pid" &>/dev/null; then
                            success "进程 $proc_name (PID: $pid) 已终止"
                        else
                            danger "无法终止进程 $proc_name (PID: $pid)"
                        fi
                    fi
                done
                ;;
            4)
                read -p "请输入要关闭的端口号 (多个端口用逗号分隔): " ports
                if [ -z "$ports" ]; then
                    danger "端口号不能为空"
                    continue
                fi
                IFS=',' read -ra port_array <<< "$ports"
                firewall_tool=""
                if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
                    firewall_tool="ufw"
                elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
                    firewall_tool="firewalld"
                elif command -v iptables &>/dev/null; then
                    firewall_tool="iptables"
                else
                    warn "未找到 ufw、firewalld 或 iptables，正在安装 ufw..."
                    software_list=("ufw")
                    install_software
                    ufw enable
                    firewall_tool="ufw"
                fi

                info "使用 $firewall_tool 关闭端口..."
                for port in "${port_array[@]}"; do
                    port=$(echo "$port" | tr -d '[:space:]')
                    if [[ ! "$port" =~ ^[0-9]+$ || $port -lt 1 || $port -gt 65535 ]]; then
                        danger "无效的端口号: $port"
                        continue
                    fi
                    case $firewall_tool in
                        ufw)
                            ufw deny "$port/tcp" >/dev/null
                            ufw deny "$port/udp" >/dev/null
                            success "端口 $port 已关闭 (TCP/UDP)"
                            ;;
                        firewalld)
                            firewall-cmd --permanent --add-port="$port/tcp" --add-port="$port/udp" >/dev/null
                            firewall-cmd --reload >/dev/null
                            success "端口 $port 已关闭 (TCP/UDP)"
                            ;;
                        iptables)
                            iptables -A INPUT -p tcp --dport "$port" -j DROP
                            iptables -A INPUT -p udp --dport "$port" -j DROP
                            success "端口 $port 已关闭 (TCP/UDP)"
                            if command -v iptables-save &>/dev/null; then
                                iptables-save > /etc/iptables.rules 2>/dev/null
                                success "iptables 规则已保存"
                            fi
                            ;;
                    esac
                done
                ;;
            0)
                break
                ;;
            *)
                danger "无效的选择"
                ;;
        esac
        echo ""
        info "按回车继续..."
        read -r
    done
}

# Main execution
manage_ports