#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: ssh_management.sh
# 功能: 这是一个ssh管理脚本
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

### === 日志函数 === ###
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="/var/log/ssh_management.log"
    echo "[$timestamp] [$level] $message" >> "$log_file" 2>/dev/null || {
        echo "[$timestamp] [ERROR] 无法写入日志文件: $log_file" >&2
    }
}

### === 检测依赖工具 === ###
check_dependencies() {
    local missing_deps=()
    local commands=("ss" "awk" "sed" "grep")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    if [ ${#missing_deps[@]} -ne 0 ]; then
        danger "缺少以下依赖工具: ${missing_deps[*]}"
        log "ERROR" "缺少依赖: ${missing_deps[*]}"
        warn "请安装缺失工具，例如："
        warn "  Ubuntu/Debian: sudo apt install iproute2 gawk sed grep"
        warn "  CentOS/RHEL: sudo yum install iproute2 gawk sed grep"
        exit $EXIT_ERROR
    fi
}

### === 检测防火墙工具 === ###
detect_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        echo "ufw"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo "firewalld"
    elif command -v iptables >/dev/null 2>&1; then
        echo "iptables"
    elif command -v nft >/dev/null 2>&1; then
        echo "nftables"
    else
        echo "none"
    fi
}

### === 重启 SSH 服务 === ###
restart_ssh_service() {
    local ssh_service
    if systemctl is-active sshd >/dev/null 2>&1; then
        ssh_service="sshd"
    elif systemctl is-active ssh >/dev/null 2>&1; then
        ssh_service="ssh"
    else
        danger "无法检测 SSH 服务"
        log "ERROR" "未找到 SSH 服务"
        return 1
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "$ssh_service" || {
            danger "重启 $ssh_service 失败"
            log "ERROR" "重启 $ssh_service 失败"
            return 1
        }
    elif command -v service >/dev/null 2>&1; then
        service "$ssh_service" restart || {
            danger "重启 $ssh_service 失败"
            log "ERROR" "重启 $ssh_service 失败"
            return 1
        }
    else
        warn "未检测到支持的服务管理器，请手动重启 SSH"
        log "WARN" "未找到服务管理器"
        return 1
    fi
    success "SSH 服务 ($ssh_service) 已重启"
    log "INFO" "SSH 服务 ($ssh_service) 重启成功"
}

### === 备份 SSH 配置 === ###
backup_ssh_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="/etc/ssh/sshd_config.bak_$timestamp"
    if [ -f /etc/ssh/sshd_config ]; then
        cp /etc/ssh/sshd_config "$backup_file" || {
            danger "备份 SSH 配置失败"
            log "ERROR" "备份 SSH 配置失败: $backup_file"
            return 1
        }
        find /etc/ssh -name 'sshd_config.bak_*' -type f | sort -r | tail -n +6 | xargs -I {} rm -f {} || {
            warn "清理旧备份文件失败"
            log "WARN" "清理旧备份文件失败"
        }
        success "已生成备份文件: $backup_file"
        log "INFO" "SSH 配置备份: $backup_file"
        return 0
    else
        danger "SSH 配置文件不存在"
        log "ERROR" "SSH 配置文件 /etc/ssh/sshd_config 不存在"
        return 1
    fi
}

### === 验证 SSH 配置 === ###
validate_ssh_config() {
    if sshd -t >/dev/null 2>&1; then
        success "SSH 配置验证通过"
        log "INFO" "SSH 配置验证通过"
        return 0
    else
        local error_output
        error_output=$(sshd -t 2>&1)
        danger "SSH 配置验证失败: $error_output"
        log "ERROR" "SSH 配置验证失败: $error_output"
        return 1
    fi
}

### === 回滚 SSH 配置 === ###
rollback_ssh_config() {
    local latest_backup
    latest_backup=$(find /etc/ssh -name 'sshd_config.bak_*' -type f | sort -r | head -n 1)
    if [ -z "$latest_backup" ]; then
        danger "未找到可用的备份文件，无法回滚"
        log "ERROR" "未找到备份文件"
        return 1
    fi
    if cp "$latest_backup" /etc/ssh/sshd_config; then
        success "已回滚到备份: $latest_backup"
        log "INFO" "SSH 配置回滚: $latest_backup"
        if restart_ssh_service; then
            success "SSH 服务已重启以应用回滚"
        else
            warn "回滚成功，但重启 SSH 服务失败"
            log "WARN" "回滚后重启 SSH 服务失败"
        fi
        return 0
    else
        danger "回滚 SSH 配置失败"
        log "ERROR" "回滚 SSH 配置失败: $latest_backup"
        return 1
    fi
}

### === 修改 SSH 配置 === ###
modify_ssh_config() {
    local pattern="$1"
    local replacement="$2"
    backup_ssh_config || return 1
    if sed -i.bak -E "s|$pattern|$replacement|" /etc/ssh/sshd_config; then
        if validate_ssh_config; then
            if restart_ssh_service; then
                success "SSH 配置已更新"
                log "INFO" "SSH 配置修改: $pattern -> $replacement"
            else
                danger "SSH 服务重启失败，尝试回滚"
                log "ERROR" "SSH 服务重启失败"
                rollback_ssh_config || danger "回滚也失败，请手动检查 /etc/ssh/sshd_config"
                return 1
            fi
        else
            danger "SSH 配置无效，执行回滚"
            rollback_ssh_config || danger "回滚失败，请手动恢复"
            return 1
        fi
    else
        danger "修改 SSH 配置失败"
        log "ERROR" "修改 SSH 配置失败: $pattern -> $replacement"
        return 1
    fi
}

### === 检查 SSH 状态 === ###
check_ssh_status() {
    local port
    local auth
    local connections
    port=$(grep '^Port ' /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
    auth=$(grep '^PasswordAuthentication ' /etc/ssh/sshd_config | awk '{print $2}' || echo "未知")
    connections=$(ss -tun | grep ":$port" | wc -l || echo "未知")
    info "SSH 状态："
    info "  端口: $port"
    info "  密码认证: $auth"
    info "  活跃连接: $connections"
    log "INFO" "SSH 状态检查：端口=$port, 密码认证=$auth, 活跃连接=$connections"
}

### === 修改端口 === ###
change_port() {
    local port
    read -p "请输入新的 SSH 端口号（1-65535）: " port
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        if ss -tuln | grep ":$port" >/dev/null; then
            danger "端口 $port 已被占用"
            log "ERROR" "端口 $port 已被占用"
            return 1
        fi
        modify_ssh_config "^#?Port .*" "Port $port" || return 1
        success "SSH 端口已更改为 $port"
        log "INFO" "SSH 端口更改为 $port"
    else
        danger "无效的端口号"
        log "ERROR" "无效的端口号: $port"
        return 1
    fi
}

### === 添加公钥 === ###
add_key() {
    echo "请粘贴完整的公钥文本（例如 ssh-rsa AAA...），然后按 Enter 确认（或按 Ctrl+C 取消）："
    local public_key
    read -r public_key
    if [ -z "$public_key" ]; then
        danger "未输入公钥，添加失败"
        log "ERROR" "未输入公钥"
        return 1
    fi
    if [[ "$public_key" =~ ^ssh-(rsa|ed25519|ecdsa)\ [A-Za-z0-9+/=]+ ]]; then
        local auth_file="/root/.ssh/authorized_keys"
        mkdir -p /root/.ssh && chmod 700 /root/.ssh || {
            danger "创建 /root/.ssh 目录失败，添加失败"
            log "ERROR" "创建 /root/.ssh 目录失败"
            return 1
        }
        if [ -f "$auth_file" ] && grep -Fx "$public_key" "$auth_file" >/dev/null 2>&1; then
            warn "公钥已存在，无需重复添加"
            log "WARN" "公钥已存在: ${public_key:0:50}..."
            return 0
        fi
        touch "$auth_file" && chmod 600 "$auth_file" || {
            danger "设置 $auth_file 权限失败，添加失败"
            log "ERROR" "设置 $auth_file 权限失败"
            return 1
        }
        echo "$public_key" >> "$auth_file" || {
            danger "添加公钥到 $auth_file 失败"
            log "ERROR" "添加公钥失败: ${public_key:0:50}..."
            return 1
        }
        success "SSH 公钥添加成功"
        log "INFO" "添加 SSH 公钥: ${public_key:0:50}..."
        return 0
    else
        danger "无效的公钥格式，添加失败"
        log "ERROR" "无效的公钥格式: ${public_key:0:50}..."
        return 1
    fi
}

# 检查防火墙状态的函数
check_firewall_status() {
    local firewall
    firewall=$(detect_firewall) # 假设 detect_firewall 函数已定义

    case $firewall in
        ufw)
            if ufw status | grep -q "Status: active"; then
                success "UFW 防火墙已启用"
                return 0
            else
                warn "UFW 防火墙未启用"
                return 1
            fi
            ;;
        firewalld)
            if systemctl is-active firewalld >/dev/null 2>&1; then
                success "Firewalld 防火墙已启用"
                return 0
            else
                warn "Firewalld 防火墙未启用"
                return 1
            fi
            ;;
        iptables)
            if iptables -L >/dev/null 2>&1; then
                success "iptables 已安装且可用"
                return 0
            else
                danger "iptables 未安装或不可用"
                return 1
            fi
            ;;
        nftables)
            if nft list tables >/dev/null 2>&1; then
                success "nftables 已安装且可用"
                return 0
            else
                danger "nftables 未安装或不可用"
                return 1
            fi
            ;;
        *)
            danger "未检测到支持的防火墙（ufw、firewalld、iptables 或 nftables）"
            return 1
            ;;
    esac
}

# 限制 SSH IP 的函数
restrict_ip() {
    # 先检查防火墙状态
    check_firewall_status
    if [ $? -ne 0 ]; then
        danger "防火墙未启用或不可用，无法设置 IP 限制"
        log "ERROR" "防火墙未启用或不可用，终止执行"
        return 1
    fi

    local ip
    read -p "请输入允许访问 SSH 的 IP 地址（例如 192.168.1.100）: " ip
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for i in {1..4}; do
            if [ "${BASH_REMATCH[$i]}" -gt 255 ]; then
                danger "无效的 IP 地址: $ip"
                log "ERROR" "无效的 IP 地址: $ip"
                return 1
            fi
        done
        local ssh_port
        ssh_port=$(grep '^Port ' /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
        local firewall
        firewall=$(detect_firewall)
        local firewall_active=0

        # 再次确认防火墙状态（与 check_firewall_status 保持一致）
        case $firewall in
            ufw)
                if ufw status | grep -q "Status: active"; then
                    firewall_active=1
                else
                    warn "UFW 防火墙未启用"
                    read -p "是否启用 UFW？（y/n）: " enable_ufw
                    if [[ "$enable_ufw" =~ ^[Yy]$ ]]; then
                        ufw enable || {
                            danger "启用 UFW 失败"
                            log "ERROR" "启用 UFW 失败"
                            return 1
                        }
                        firewall_active=1
                        success "UFW 已启用"
                        log "INFO" "UFW 防火墙已启用"
                    else
                        danger "UFW 未启用，无法设置 IP 限制"
                        log "ERROR" "UFW 未启用，用户选择不启用"
                        return 1
                    fi
                fi
                ;;
            firewalld)
                if systemctl is-active firewalld >/dev/null 2>&1; then
                    firewall_active=1
                else
                    warn "Firewalld 防火墙未启用"
                    read -p "是否启用 Firewalld？（y/n）: " enable_firewalld
                    if [[ "$enable_firewalld" =~ ^[Yy]$ ]]; then
                        systemctl start firewalld || {
                            danger "启用 Firewalld 失败"
                            log "ERROR" "启用 Firewalld 失败"
                            return 1
                        }
                        firewall_active=1
                        success "Firewalld 已启用"
                        log "INFO" "Firewalld 防火墙已启用"
                    else
                        danger "Firewalld 未启用，无法设置 IP 限制"
                        log "ERROR" "Firewalld 未启用，用户选择不启用"
                        return 1
                    fi
                fi
                ;;
            iptables)
                # iptables is always "active" if installed (no daemon)
                firewall_active=1
                warn "注意：iptables 规则不会在重启后自动持久化，请手动保存（例如使用 iptables-save）"
                log "WARN" "iptables 规则需手动持久化"
                ;;
            nftables)
                # nftables is always "active" if installed (no daemon)
                firewall_active=1
                warn "注意：nftables 规则不会在重启后自动持久化，请手动保存（例如使用 nft list ruleset）"
                log "WARN" "nftables 规则需手动持久化"
                ;;
            *)
                danger "未检测到支持的防火墙（ufw、firewalld、iptables 或 nftables）"
                log "ERROR" "未检测到支持的防火墙"
                return 1
                ;;
        esac

        # Apply firewall rules if active
        if [ "$firewall_active" -eq 1 ]; then
            case $firewall in
                ufw)
                    ufw allow from "$ip" to any port "$ssh_port" proto tcp || {
                        danger "设置 ufw 规则失败"
                        log "ERROR" "设置 ufw 规则失败: IP=$ip, 端口=$ssh_port"
                        return 1
                    }
                    ufw reload || {
                        danger "重载 ufw 失败"
                        log "ERROR" "重载 ufw 失败"
                        return 1
                    }
                    success "SSH 限制为仅 $ip 可访问（使用 ufw，端口 $ssh_port）"
                    log "INFO" "限制 SSH 访问: IP=$ip, 端口=$ssh_port, 防火墙=ufw"
                    ;;
                firewalld)
                    firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$ip port port=$ssh_port protocol=tcp accept" || {
                        danger "设置 firewalld 规则失败"
                        log "ERROR" "设置 firewalld 规则失败: IP=$ip, 端口=$ssh_port"
                        return 1
                    }
                    firewall-cmd --reload || {
                        danger "重载 firewalld 失败"
                        log "ERROR" "重载 firewalld 失败"
                        return 1
                    }
                    success "SSH 限制为仅 $ip 可访问（使用 firewalld，端口 $ssh_port）"
                    log "INFO" "限制 SSH 访问: IP=$ip, 端口=$ssh_port, 防火墙=firewalld"
                    ;;
                iptables)
                    iptables -A INPUT -p tcp --dport "$ssh_port" -s "$ip" -j ACCEPT || {
                        danger "设置 iptables 规则失败"
                        log "ERROR" "设置 iptables 规则失败: IP=$ip, 端口=$ssh_port"
                        return 1
                    }
                    iptables -A INPUT -p tcp --dport "$ssh_port" -j DROP || {
                        danger "设置 iptables 规则失败"
                        log "ERROR" "设置 iptables 规则失败: IP=$ip, 端口=$ssh_port"
                        return 1
                    }
                    success "SSH 限制为仅 $ip 可访问（使用 iptables，端口 $ssh_port）"
                    log "INFO" "限制 SSH 访问: IP=$ip, 端口=$ssh_port, 防火墙=iptables"
                    ;;
                nftables)
                    nft add table inet ssh_filter || {
                        danger "创建 nftables 表失败"
                        log "ERROR" "创建 nftables 表失败: IP=$ip, 端口=$ssh_port"
                        return 1
                    }
                    nft add chain inet ssh_filter input \{ type filter hook input priority 0 \; policy drop \; \} || {
                        danger "创建 nftables 链失败"
                        log "ERROR" "创建 nftables 链失败: IP=$ip, 端口=$ssh_port"
                        return 1
                    }
                    nft add rule inet ssh_filter input ip saddr "$ip" tcp dport "$ssh_port" accept || {
                        danger "设置 nftables 规则失败"
                        log "ERROR" "设置 nftables 规则失败: IP=$ip, 端口=$ssh_port"
                        return 1
                    }
                    success "SSH 限制为仅 $ip 可访问（使用 nftables，端口 $ssh_port）"
                    log "INFO" "限制 SSH 访问: IP=$ip, 端口=$ssh_port, 防火墙=nftables"
                    ;;
            esac
        else
            danger "防火墙未启用，无法设置 IP 限制"
            log "ERROR" "防火墙未启用，无法设置 IP 限制: $firewall"
            return 1
        fi
    else
        danger "无效的 IP 地址格式"
        log "ERROR" "无效的 IP 地址格式: $ip"
        return 1
    fi
}

### === 禁用密码登录 === ###
disable_password() {
    modify_ssh_config "^#?PasswordAuthentication .*" "PasswordAuthentication no" || return 1
    success "密码登录已禁用"
    log "INFO" "禁用 SSH 密码登录"
}

### === 启用密码登录 === ###
enable_password() {
    modify_ssh_config "^#?PasswordAuthentication .*" "PasswordAuthentication yes" || return 1
    success "密码登录已启用"
    log "INFO" "启用 SSH 密码登录"
}

### === 优化 SSH 速度 === ###
optimize_ssh_speed() {
    backup_ssh_config || return 1
    {
        echo 'Ciphers aes256-ctr,aes192-ctr,aes128-ctr'
        echo 'TCPKeepAlive yes'
        echo 'LoginGraceTime 30'
    } >> /etc/ssh/sshd_config || {
        danger "优化 SSH 配置失败"
        log "ERROR" "优化 SSH 配置失败"
        return 1
    }
    if validate_ssh_config; then
        restart_ssh_service || return 1
        success "SSH 连接速度已优化"
        log "INFO" "优化 SSH 连接速度"
    else
        danger "SSH 配置无效，执行回滚"
        rollback_ssh_config || danger "回滚失败，请手动恢复"
        return 1
    fi
}

### === 一键优化安全性 === ###
secure_ssh() {
    backup_ssh_config || return 1
    sed -i.bak -E 's|^#?PasswordAuthentication .*|PasswordAuthentication no|' /etc/ssh/sshd_config &&
    sed -i.bak -E 's|^#?PermitEmptyPasswords .*|PermitEmptyPasswords no|' /etc/ssh/sshd_config &&
    echo 'MaxAuthTries 3' >> /etc/ssh/sshd_config &&
    echo 'Ciphers aes256-ctr,aes192-ctr,aes128-ctr' >> /etc/ssh/sshd_config || {
        danger "优化 SSH 安全性失败"
        log "ERROR" "优化 SSH 安全性失败"
        return 1
    }
    if validate_ssh_config; then
        restart_ssh_service || return 1
        success "SSH 安全性已优化"
        log "INFO" "一键优化 SSH 安全性"
    else
        danger "SSH 配置无效，执行回滚"
        rollback_ssh_config || danger "回滚失败，请手动恢复"
        return 1
    fi
}

### === 主菜单 === ###
build_command() {
    echo "请根据以下选项输入对应的数字来执行操作："
    echo "1 - 修改 SSH 端口"
    echo "2 - 添加 SSH 公钥"
    echo "3 - 限制 SSH 的 IP 访问"
    echo "4 - 禁用 SSH 密码登录"
    echo "5 - 启用 SSH 密码登录"
    echo "6 - 优化 SSH 连接速度"
    echo "7 - 一键优化 SSH 安全性"
    echo "8 - 检查 SSH 状态"
    echo "9 - 退出"
    local choice
    read -p "请输入选择 (1-9): " choice
    case $choice in
        1) change_port ;;
        2) add_key ;;
        3) restrict_ip ;;
        4) disable_password ;;
        5) enable_password ;;
        6) optimize_ssh_speed ;;
        7) secure_ssh ;;
        8) check_ssh_status ;;
        9) success "退出脚本"; exit $EXIT_SUCCESS ;;
        *) danger "无效选择，请输入 1-9"; build_command ;;
    esac
}

### === 主函数入口 === ###
main() {
    log "INFO" "脚本启动: 本地执行"
    check_dependencies
    if ! whoami >/dev/null; then
        danger "本地命令测试失败，请检查环境"
        log "ERROR" "本地命令测试失败"
        exit $EXIT_ERROR
    fi
    build_command
}

main