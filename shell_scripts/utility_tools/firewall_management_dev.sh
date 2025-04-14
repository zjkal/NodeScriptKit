#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: firewall_management.sh
# 功能: 这是一个防火墙管理脚本，用于配置和管理 ufw、firewalld、iptables 或 nftables 的端口和 IP 规则# 作者: rouxyang <rouxyang@gmail.com>
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

# Validate port number
is_valid_port() {
    local port=$1
    [[ "$port" =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]
}

# Validate IP address
is_valid_ip() {
    local ip=$1
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

# Install ufw as fallback
install_ufw() {
    local sys_id=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2 | tr -d '"')
    info "正在安装 ufw..."
    case $sys_id in
        centos|rhel|fedora|rocky|almalinux)
            command -v dnf &>/dev/null && dnf install -y ufw &>/dev/null || yum install -y ufw &>/dev/null
            ;;
        debian|ubuntu|linuxmint)
            apt update -y &>/dev/null && apt install -y ufw &>/dev/null
            ;;
        arch|manjaro)
            pacman -Syu --noconfirm ufw &>/dev/null
            ;;
        opensuse|suse)
            zypper install -y ufw &>/dev/null
            ;;
        alpine)
            apk add ufw &>/dev/null
            ;;
        openwrt)
            opkg install ufw &>/dev/null
            ;;
        *)
            danger "未知系统: $sys_id，请手动安装 ufw"
            return 1
            ;;
    esac
    command -v ufw &>/dev/null && { ufw enable >/dev/null; success "ufw 已安装并启用"; return 0; }
    danger "无法安装 ufw"
    return 1
}

# Detect active firewall
detect_firewall() {
    if command -v nft &>/dev/null && nft list tables &>/dev/null; then
        echo "nftables"
    elif command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        echo "firewalld"
    elif command -v iptables &>/dev/null; then
        echo "iptables"
    else
        echo ""
    fi
}

# Get firewall running status
get_running_status() {
    local firewall=$1
    case $firewall in
        ufw)
            ufw status | grep -q "Status: active" && echo "运行中" || echo "已停止"
            ;;
        firewalld)
            systemctl is-active firewalld &>/dev/null && echo "运行中" || echo "已停止"
            ;;
        iptables)
            iptables -L INPUT -n | grep -q "Chain INPUT" && echo "运行中" || echo "已停止"
            ;;
        nftables)
            nft list tables &>/dev/null && echo "运行中" || echo "已停止"
            ;;
    esac
}

# Display firewall status
display_status() {
    local firewall=$1
    local status=$(get_running_status "$firewall")
    echo "当前状态: $status"
    case $firewall in
        ufw) ufw status ;;
        firewalld) firewall-cmd --list-all ;;
        iptables) iptables -L INPUT ;;
        nftables) nft list ruleset ;;
    esac
}

# Start firewall
start_firewall() {
    local firewall=$1
    case $firewall in
        ufw)
            ufw enable >/dev/null && success "ufw 已启动"
            ;;
        firewalld)
            systemctl start firewalld >/dev/null && systemctl enable firewalld >/dev/null && success "firewalld 已启动"
            ;;
        iptables)
            iptables-restore < /etc/iptables.rules 2>/dev/null || warn "没有保存的 iptables 规则，保持当前状态"
            success "iptables 已启动"
            ;;
        nftables)
            nft -f /etc/nftables.conf 2>/dev/null || warn "没有保存的 nftables 规则，保持当前状态"
            success "nftables 已启动"
            ;;
    esac
}

# Stop firewall
stop_firewall() {
    local firewall=$1
    case $firewall in
        ufw)
            ufw disable >/dev/null && success "ufw 已停止"
            ;;
        firewalld)
            systemctl stop firewalld >/dev/null && success "firewalld 已停止"
            ;;
        iptables)
            iptables -F INPUT && iptables -P INPUT ACCEPT
            command -v iptables-save &>/dev/null && iptables-save > /etc/iptables.rules 2>/dev/null
            success "iptables 已停止"
            ;;
        nftables)
            nft flush ruleset >/dev/null && success "nftables 已停止"
            ;;
    esac
}

# Apply firewall rule (port or IP)
apply_firewall_rule() {
    local firewall=$1 action=$2 target=$3 type=$4
    case $firewall in
        ufw)
            if [[ "$type" == "port" ]]; then
                ufw "$action" "$target/tcp" >/dev/null
                ufw "$action" "$target/udp" >/dev/null
            elif [[ "$type" == "ip" ]]; then
                ufw "$action" from "$target" >/dev/null
            fi
            ;;
        firewalld)
            if [[ "$type" == "port" ]]; then
                [[ "$action" == "allow" ]] && action="add" || action="remove"
                firewall-cmd --permanent "--$action-port=$target/tcp" >/dev/null
                firewall-cmd --permanent "--$action-port=$target/udp" >/dev/null
            elif [[ "$type" == "ip" ]]; then
                if [[ "$action" == "allow" ]]; then
                    firewall-cmd --permanent --add-source="$target" >/dev/null
                else
                    firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$target' reject" >/dev/null
                fi
            fi
            firewall-cmd --reload >/dev/null
            ;;
        iptables)
            if [[ "$type" == "port" ]]; then
                iptables -D INPUT -p tcp --dport "$target" -j "${action^}" 2>/dev/null
                iptables -D INPUT -p udp --dport "$target" -j "${action^}" 2>/dev/null
                iptables -A INPUT -p tcp --dport "$target" -j "${action^}"
                iptables -A INPUT -p udp --dport "$target" -j "${action^}"
            elif [[ "$type" == "ip" ]]; then
                iptables -A INPUT -s "$target" -j "${action^}"
            fi
            command -v iptables-save &>/dev/null && iptables-save > /etc/iptables.rules 2>/dev/null
            ;;
        nftables)
            if [[ "$type" == "port" ]]; then
                local chain="input"
                [[ "$action" == "allow" ]] && verdict="accept" || verdict="drop"
                nft add rule ip filter "$chain" tcp dport "$target" "$verdict" >/dev/null
                nft add rule ip filter "$chain" udp dport "$target" "$verdict" >/dev/null
            elif [[ "$type" == "ip" ]]; then
                [[ "$action" == "allow" ]] && verdict="accept" || verdict="drop"
                nft add rule ip filter input ip saddr "$target" "$verdict" >/dev/null
            fi
            nft list ruleset > /etc/nftables.conf 2>/dev/null
            ;;
    esac
    [[ $? -eq 0 ]]
}

# Clear IP rule
clear_ip_rule() {
    local firewall=$1 ip=$2
    case $firewall in
        ufw)
            ufw delete allow from "$ip" 2>/dev/null
            ufw delete deny from "$ip" 2>/dev/null
            ;;
        firewalld)
            firewall-cmd --permanent --remove-source="$ip" 2>/dev/null
            firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='$ip' reject" 2>/dev/null
            firewall-cmd --reload >/dev/null
            ;;
        iptables)
            iptables -D INPUT -s "$ip" -j ACCEPT 2>/dev/null
            iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
            command -v iptables-save &>/dev/null && iptables-save > /etc/iptables.rules 2>/dev/null
            ;;
        nftables)
            nft delete rule ip filter input ip saddr "$ip" accept 2>/dev/null
            nft delete rule ip filter input ip saddr "$ip" drop 2>/dev/null
            nft list ruleset > /etc/nftables.conf 2>/dev/null
            ;;
    esac
    [[ $? -eq 0 ]]
}

# Uninstall firewall
uninstall_firewall() {
    local firewall=$1 pkg=$2
    case $firewall in
        ufw)
            ufw disable >/dev/null
            ;;
        firewalld)
            systemctl stop firewalld >/dev/null
            systemctl disable firewalld >/dev/null
            ;;
        iptables)
            iptables -F
            ;;
        nftables)
            nft flush ruleset >/dev/null
            ;;
    esac

    local sys_id=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2 | tr -d '"')
    info "正在卸载 $firewall..."
    case $sys_id in
        centos|rhel|fedora|rocky|almalinux)
            command -v dnf &>/dev/null && dnf remove -y "$pkg" &>/dev/null || yum remove -y "$pkg" &>/dev/null
            ;;
        debian|ubuntu|linuxmint)
            apt purge -y "$pkg" &>/dev/null && apt autoremove -y &>/dev/null
            ;;
        arch|manjaro)
            pacman -Rns --noconfirm "$pkg" &>/dev/null
            ;;
        opensuse|suse)
            zypper remove -y "$pkg" &>/dev/null
            ;;
        alpine)
            apk del "$pkg" &>/dev/null
            ;;
        openwrt)
            opkg remove "$pkg" &>/dev/null
            ;;
        *)
            danger "未知系统: $sys_id，请手动卸载 $pkg"
            return 1
            ;;
    esac
    [[ ! -x "$(command -v "$pkg")" ]] && { success "$firewall 已卸载"; return 0; }
    danger "无法卸载 $firewall"
    return 1
}

# Open all ports
open_all_ports() {
    local firewall=$1
    case $firewall in
        ufw)
            ufw disable >/dev/null
            success "已开放所有端口 (ufw 已禁用)"
            ;;
        firewalld)
            firewall-cmd --set-default-zone=public >/dev/null
            firewall-cmd --permanent --zone=public --add-port=1-65535/tcp >/dev/null
            firewall-cmd --permanent --zone=public --add-port=1-65535/udp >/dev/null
            firewall-cmd --reload >/dev/null
            success "已开放所有端口"
            ;;
        iptables)
            iptables -F INPUT
            iptables -P INPUT ACCEPT
            command -v iptables-save &>/dev/null && iptables-save > /etc/iptables.rules 2>/dev/null
            success "已开放所有端口"
            ;;
        nftables)
            nft flush ruleset >/dev/null
            nft add table ip filter >/dev/null
            nft add chain ip filter input { type filter hook input priority 0 \; policy accept \; } >/dev/null
            nft list ruleset > /etc/nftables.conf 2>/dev/null
            success "已开放所有端口"
            ;;
    esac
}

# Close all ports
close_all_ports() {
    local firewall=$1
    case $firewall in
        ufw)
            ufw default deny incoming >/dev/null
            ufw enable >/dev/null
            success "已关闭所有端口 (允许现有规则)"
            ;;
        firewalld)
            firewall-cmd --set-default-zone=drop >/dev/null
            firewall-cmd --reload >/dev/null
            success "已关闭所有端口 (仅允许必要服务)"
            ;;
        iptables)
            iptables -F INPUT
            iptables -P INPUT DROP
            command -v iptables-save &>/dev/null && iptables-save > /etc/iptables.rules 2>/dev/null
            success "已关闭所有端口"
            ;;
        nftables)
            nft flush ruleset >/dev/null
            nft add table ip filter >/dev/null
            nft add chain ip filter input { type filter hook input priority 0 \; policy drop \; } >/dev/null
            nft list ruleset > /etc/nftables.conf 2>/dev/null
            success "已关闭所有端口"
            ;;
    esac
}

# Main firewall management function
firewall_management() {
    check_root
    local firewall=$(detect_firewall)
    if [[ -z "$firewall" ]]; then
        warn "未找到 ufw、firewalld、iptables 或 nftables"
        read -p "是否安装 ufw 作为默认防火墙？(y/n): " install_choice
        [[ ! "$install_choice" =~ ^[Yy]$ ]] && { danger "未安装防火墙，无法继续"; exit 1; }
        install_ufw || exit 1
        firewall="ufw"
    fi
    local firewall_pkg=$([[ "$firewall" == "nftables" ]] && echo "nftables" || echo "$firewall")

    while true; do
        clear
        info "防火墙已安装: $firewall"
        echo "------------------------"
        display_status "$firewall"
        echo ""
        info "防火墙管理"
        echo "------------------------"
        echo "1. 开放指定端口"
        echo "2. 关闭指定端口"
        echo "3. 开放所有端口"
        echo "4. 关闭所有端口"
        echo "------------------------"
        echo "5. IP白名单"
        echo "6. IP黑名单"
        echo "7. 清除指定IP"
        echo "------------------------"
        echo "8. 启动防火墙"
        echo "9. 停止防火墙"
        echo "10. 卸载防火墙"
        echo "0. 退出"
        echo "------------------------"
        read -p "请输入您的选择: " choice

        case $choice in
            1)
                read -p "请输入要开放的端口号 (多个端口用逗号分隔): " ports
                [[ -z "$ports" ]] && { danger "端口号不能为空"; continue; }
                IFS=',' read -ra port_array <<< "$ports"
                for port in "${port_array[@]}"; do
                    port=$(echo "$port" | tr -d '[:space:]')
                    is_valid_port "$port" || { danger "无效的端口号: $port"; continue; }
                    apply_firewall_rule "$firewall" "allow" "$port" "port" && success "端口 $port 已开放 (TCP/UDP)"
                done
                ;;
            2)
                read -p "请输入要关闭的端口号 (多个端口用逗号分隔): " ports
                [[ -z "$ports" ]] && { danger "端口号不能为空"; continue; }
                IFS=',' read -ra port_array <<< "$ports"
                for port in "${port_array[@]}"; do
                    port=$(echo "$port" | tr -d '[:space:]')
                    is_valid_port "$port" || { danger "无效的端口号: $port"; continue; }
                    apply_firewall_rule "$firewall" "deny" "$port" "port" && success "端口 $port 已关闭 (TCP/UDP)"
                done
                ;;
            3)
                read -p "确定要开放所有端口？(y/n): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && open_all_ports "$firewall"
                ;;
            4)
                read -p "确定要关闭所有端口？(y/n): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && close_all_ports "$firewall"
                ;;
            5)
                read -p "请输入要加入白名单的 IP 地址 (多个 IP 用逗号分隔): " ips
                [[ -z "$ips" ]] && { danger "IP 地址不能为空"; continue; }
                IFS=',' read -ra ip_array <<< "$ips"
                for ip in "${ip_array[@]}"; do
                    ip=$(echo "$ip" | tr -d '[:space:]')
                    is_valid_ip "$ip" || { danger "无效的 IP 地址: $ip"; continue; }
                    apply_firewall_rule "$firewall" "allow" "$ip" "ip" && success "IP $ip 已加入白名单"
                done
                ;;
            6)
                read -p "请输入要加入黑名单的 IP 地址 (多个 IP 用逗号分隔): " ips
                [[ -z "$ips" ]] && { danger "IP 地址不能为空"; continue; }
                IFS=',' read -ra ip_array <<< "$ips"
                for ip in "${ip_array[@]}"; do
                    ip=$(echo "$ip" | tr -d '[:space:]')
                    is_valid_ip "$ip" || { danger "无效的 IP 地址: $ip"; continue; }
                    apply_firewall_rule "$firewall" "deny" "$ip" "ip" && success "IP $ip 已加入黑名单"
                done
                ;;
            7)
                read -p "请输入要清除的 IP 地址 (多个 IP 用逗号分隔): " ips
                [[ -z "$ips" ]] && { danger "IP 地址不能为空"; continue; }
                IFS=',' read -ra ip_array <<< "$ips"
                for ip in "${ip_array[@]}"; do
                    ip=$(echo "$ip" | tr -d '[:space:]')
                    is_valid_ip "$ip" || { danger "无效的 IP 地址: $ip"; continue; }
                    clear_ip_rule "$firewall" "$ip" && success "IP $ip 已从规则中清除"
                done
                ;;
            8)
                start_firewall "$firewall"
                ;;
            9)
                stop_firewall "$firewall"
                ;;
            10)
                read -p "确定要卸载防火墙 $firewall 吗？(y/n): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && uninstall_firewall "$firewall" "$firewall_pkg" && break
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
firewall_management