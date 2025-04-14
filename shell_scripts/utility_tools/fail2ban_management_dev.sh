#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

success() { printf "${GREEN}%b${NC} ${@:2}\n" "$1"; }
info() { printf "${CYAN}%b${NC} ${@:2}\n" "$1"; }
danger() { printf "\n${RED}[错误] %b${NC}\n" "$@"; }
warn() { printf "${YELLOW}[警告] %b${NC}\n" "$@"; }

# System info
sys_id=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2 | tr -d '"')

# Software dependencies
software_list=("fail2ban" "curl")

# Check root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        danger "请以root用户运行此脚本！"
        exit 1
    fi
}

# Install software
install_software() {
    check_root
    if [ ${#software_list[@]} -eq 0 ]; then
        danger "software_list 中未指定任何软件包"
        exit 1
    fi

    check_command() {
        command -v "$1" &>/dev/null
    }

    install_package() {
        local pkg="$1"
        info "正在处理 $pkg..."

        if check_command "$pkg"; then
            success "$pkg 已安装"
            return 0
        fi

        info "正在安装 $pkg..."
        case ${sys_id} in
            centos|rhel|fedora|rocky|almalinux)
                if check_command dnf; then
                    dnf -y update &>/dev/null && dnf install -y epel-release &>/dev/null
                    dnf install -y "$pkg" &>/dev/null
                elif check_command yum; then
                    yum -y update &>/dev/null && yum install -y epel-release &>/dev/null
                    yum install -y "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 yum 或 dnf"
                    return 1
                fi
                ;;
            debian|ubuntu|linuxmint)
                apt update -y &>/dev/null
                apt install -y "$pkg" &>/dev/null
                ;;
            arch|manjaro)
                if check_command pacman; then
                    pacman -Syu --noconfirm &>/dev/null
                    pacman -S --noconfirm "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 pacman"
                    return 1
                fi
                ;;
            opensuse|suse)
                if check_command zypper; then
                    zypper refresh &>/dev/null
                    zypper install -y "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 zypper"
                    return 1
                fi
                ;;
            alpine)
                if check_command apk; then
                    apk update &>/dev/null
                    apk add "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 apk"
                    return 1
                fi
                ;;
            openwrt)
                if check_command opkg; then
                    opkg update &>/dev/null
                    opkg install "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 opkg"
                    return 1
                fi
                ;;
            *)
                danger "未知系统: ${sys_id}，请手动安装 $pkg"
                return 1
                ;;
        esac

        if check_command "$pkg"; then
            success "$pkg 安装成功"
            return 0
        else
            danger "无法安装 $pkg"
            return 1
        fi
    }

    local failed=0
    for pkg in "${software_list[@]}"; do
        install_package "$pkg" || failed=1
    done

    if [ $failed -eq 1 ]; then
        danger "一个或多个软件包安装失败"
        exit 1
    fi
}

# Uninstall software
uninstall_software() {
    check_root
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then
        danger "未指定要卸载的软件包"
        return 1
    fi

    uninstall_package() {
        local pkg="$1"
        info "正在卸载 $pkg..."

        if ! command -v "$pkg" &>/dev/null && ! dpkg -l "$pkg" &>/dev/null 2>&1 && ! rpm -q "$pkg" &>/dev/null 2>&1; then
            success "$pkg 未安装"
            return 0
        fi

        case ${sys_id} in
            centos|rhel|fedora|rocky|almalinux)
                if command -v dnf; then
                    dnf remove -y "$pkg" &>/dev/null
                elif command -v yum; then
                    yum remove -y "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 yum 或 dnf"
                    return 1
                fi
                ;;
            debian|ubuntu|linuxmint)
                apt purge -y "$pkg" &>/dev/null
                apt autoremove -y &>/dev/null
                ;;
            arch|manjaro)
                if command -v pacman; then
                    pacman -Rns --noconfirm "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 pacman"
                    return 1
                fi
                ;;
            opensuse|suse)
                if command -v zypper; then
                    zypper remove -y "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 zypper"
                    return 1
                fi
                ;;
            alpine)
                if command -v apk; then
                    apk del "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 apk"
                    return 1
                fi
                ;;
            openwrt)
                if command -v opkg; then
                    opkg remove "$pkg" &>/dev/null
                else
                    danger "${sys_id} 上未找到 opkg"
                    return 1
                fi
                ;;
            *)
                danger "未知系统: ${sys_id}，请手动卸载 $pkg"
                return 1
                ;;
        esac

        if ! command -v "$pkg" &>/dev/null && ! dpkg -l "$pkg" &>/dev/null 2>&1 && ! rpm -q "$pkg" &>/dev/null 2>&1; then
            success "$pkg 卸载成功"
            return 0
        else
            danger "无法卸载 $pkg"
            return 1
        fi
    }

    local failed=0
    for pkg in "${packages[@]}"; do
        uninstall_package "$pkg" || failed=1
    done

    return $failed
}

# Manage fail2ban
manage_fail2ban() {
    clear
    check_root
    if command -v fail2ban-client &>/dev/null && [ -d "/etc/fail2ban" ]; then
        while true; do
            info "Fail2ban 已运行"
            echo "------------------------"
            echo "1. 查看 SSH 拦截记录"
            echo "2. 实时监控日志"
            echo "3. 列出被封禁的 IP"
            echo "4. 手动封禁 IP"
            echo "5. 手动解封 IP"
            echo "6. 卸载 Fail2ban"
            echo "0. 退出"
            echo "------------------------"
            read -p "请输入您的选择: " choice

            case $choice in
                1)
                    info "SSH 拦截记录"
                    fail2ban-client status sshd || danger "无法获取 SSH 拦截记录"
                    ;;
                2)
                    info "实时监控 Fail2ban 日志..."
                    tail -f /var/log/fail2ban.log
                    break
                    ;;
                3)
                    info "当前被封禁的 IP 列表"
                    fail2ban-client status sshd | grep "Banned IP list" || echo "无被封禁的 IP"
                    ;;
                4)
                    read -p "请输入要封禁的 IP 地址: " ip
                    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                        danger "无效的 IP 地址"
                        continue
                    fi
                    fail2ban-client set sshd banip "$ip" >/dev/null
                    success "IP $ip 已封禁"
                    ;;
                5)
                    read -p "请输入要解封的 IP 地址: " ip
                    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                        danger "无效的 IP 地址"
                        continue
                    fi
                    fail2ban-client set sshd unbanip "$ip" >/dev/null
                    success "IP $ip 已解封"
                    ;;
                6)
                    read -p "确定要卸载 Fail2ban 吗？(y/n): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        uninstall_software "fail2ban"
                        rm -rf /etc/fail2ban 2>/dev/null
                        success "Fail2ban 已卸载并清理配置文件"
                        break
                    fi
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
    else
        info "Fail2ban 是一个防止 SSH 暴力破解的工具"
        info "工作原理：检测恶意高频访问 SSH 端口的 IP 并自动封禁"
        read -p "是否安装 Fail2ban？(y/n): " install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            install_software
            if ! grep -q 'Alpine' /etc/issue 2>/dev/null; then
                rm -rf /etc/fail2ban/jail.d/* 2>/dev/null
                curl -sS -o /etc/fail2ban/jail.d/sshd.local https://raw.githubusercontent.com/kejilion/sh/main/sshd.local
            fi
            systemctl start fail2ban >/dev/null 2>&1
            systemctl enable fail2ban >/dev/null 2>&1
            success "Fail2ban 已安装并启用"
        else
            info "已取消安装"
        fi
    fi
}

# Main execution
manage_fail2ban