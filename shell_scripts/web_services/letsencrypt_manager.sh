#!/bin/bash

### === 脚本描述 === ###
# 名称: Let's Encrypt证书管理工具
# 功能: 自动申请、续期和管理SSL证书
# 作者: zjkal <https://www.nodeseek.com/space/25215>
# 创建日期: 2025-07-08
# 许可证: MIT


### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"
SCRIPT_NAME="Let's Encrypt证书管理工具"
SCRIPT_AUTHOR="zjkal <https://www.nodeseek.com/space/25215>"

echo -e "\033[33m[信息] $SCRIPT_NAME ，版本: $SCRIPT_VERSION\033[0m"
echo -e "\033[33m[作者] $SCRIPT_AUTHOR\033[0m"

### === 权限检查 === ###
[[ $EUID -ne 0 ]] && echo -e "\033[31m[错误] 请以root用户或sudo运行此脚本！\033[0m" && exit 1

### === 依赖检查 === ###
check_dependencies() {
    local deps=("curl" "awk" "sed" "grep")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "\033[31m[错误] 缺少必要命令: $cmd\033[0m"
            exit 1
        fi
    done
}

### === 退出状态码 === ###
EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_INTERRUPT=130 # Ctrl+C 退出码

### === 颜色定义 === ###
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

### === 彩色输出函数 === ###
success() { printf "${GREEN}%b${NC} ${@:2}\n" "$1"; }
info() { printf "${CYAN}%b${NC} ${@:2}\n" "$1"; }
danger() { printf "\n${RED}[错误] %b${NC}\n" "$@"; }
warn() { printf "${YELLOW}[警告] %b${NC}\n" "$@"; }

### === 日志记录函数 === ###
LOG_FILE="/var/log/${SCRIPT_NAME:-$(basename "${0:-unknown.sh}")}.log"
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" 2>/dev/null
}

### === 信号捕获 === ###
cleanup() {
    log "INFO" "脚本被中断..."
    warn "[警告] 脚本已退出！"
    exit $EXIT_INTERRUPT
}
trap cleanup SIGINT SIGTERM

### === 检测系统类型 === ###
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VERSION=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VERSION=$DISTRIB_RELEASE
    else
        OS=$(uname -s)
        VERSION=$(uname -r)
    fi
    
    OS=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
    
    case "$OS" in
        ubuntu|debian)
            PACKAGE_MANAGER="apt"
            INSTALL_CMD="apt install -y"
            UPDATE_CMD="apt update"
            ;;
        centos|rhel|fedora)
            PACKAGE_MANAGER="yum"
            INSTALL_CMD="yum install -y"
            UPDATE_CMD="yum check-update"
            ;;
        alpine)
            PACKAGE_MANAGER="apk"
            INSTALL_CMD="apk add"
            UPDATE_CMD="apk update"
            ;;
        *)
            danger "不支持的操作系统: $OS"
            exit $EXIT_ERROR
            ;;
    esac
    
    info "检测到操作系统: $OS $VERSION"
    log "INFO" "操作系统: $OS $VERSION"
}

### === 检测Web服务器 === ###
detect_web_server() {
    if command -v nginx &>/dev/null; then
        if pgrep -x "nginx" &>/dev/null; then
            WEB_SERVER="nginx"
            info "检测到正在运行的Nginx服务器"
            log "INFO" "检测到Web服务器: Nginx"
            return 0
        fi
    fi
    
    if command -v apache2 &>/dev/null || command -v httpd &>/dev/null; then
        if pgrep -x "apache2" &>/dev/null || pgrep -x "httpd" &>/dev/null; then
            WEB_SERVER="apache"
            info "检测到正在运行的Apache服务器"
            log "INFO" "检测到Web服务器: Apache"
            return 0
        fi
    fi
    
    WEB_SERVER="none"
    warn "未检测到运行中的Web服务器"
    log "WARN" "未检测到运行中的Web服务器"
    return 1
}

### === 安装Certbot === ###
install_certbot() {
    info "正在安装Certbot..."
    log "INFO" "安装Certbot"
    
    case "$PACKAGE_MANAGER" in
        apt)
            $UPDATE_CMD
            $INSTALL_CMD certbot
            if [ "$WEB_SERVER" = "nginx" ]; then
                $INSTALL_CMD python3-certbot-nginx
            elif [ "$WEB_SERVER" = "apache" ]; then
                $INSTALL_CMD python3-certbot-apache
            fi
            ;;
        yum)
            $INSTALL_CMD epel-release
            $UPDATE_CMD
            $INSTALL_CMD certbot
            if [ "$WEB_SERVER" = "nginx" ]; then
                $INSTALL_CMD python3-certbot-nginx
            elif [ "$WEB_SERVER" = "apache" ]; then
                $INSTALL_CMD python3-certbot-apache
            fi
            ;;
        apk)
            $UPDATE_CMD
            $INSTALL_CMD certbot
            if [ "$WEB_SERVER" = "nginx" ]; then
                $INSTALL_CMD certbot-nginx
            elif [ "$WEB_SERVER" = "apache" ]; then
                $INSTALL_CMD certbot-apache
            fi
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        success "Certbot安装成功！"
        log "INFO" "Certbot安装成功"
        return 0
    else
        danger "Certbot安装失败！"
        log "ERROR" "Certbot安装失败"
        return 1
    fi
}

### === 申请证书 === ###
issue_certificate() {
    local domain=$1
    local email=$2
    local webroot=$3
    
    info "正在为 $domain 申请SSL证书..."
    log "INFO" "申请SSL证书: $domain"
    
    # 检查是否已安装certbot
    if ! command -v certbot &>/dev/null; then
        warn "未检测到certbot，尝试安装..."
        install_certbot
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    
    # 根据Web服务器类型选择申请方式
    if [ -n "$webroot" ]; then
        # 使用webroot方式申请
        certbot certonly --webroot -w "$webroot" -d "$domain" -d "www.$domain" --email "$email" --agree-tos --non-interactive
    elif [ "$WEB_SERVER" = "nginx" ]; then
        # 使用nginx插件申请
        certbot --nginx -d "$domain" -d "www.$domain" --email "$email" --agree-tos --non-interactive
    elif [ "$WEB_SERVER" = "apache" ]; then
        # 使用apache插件申请
        certbot --apache -d "$domain" -d "www.$domain" --email "$email" --agree-tos --non-interactive
    else
        # 使用standalone模式申请
        warn "未检测到Web服务器，使用standalone模式申请证书"
        log "WARN" "使用standalone模式申请证书"
        certbot certonly --standalone -d "$domain" -d "www.$domain" --email "$email" --agree-tos --non-interactive
    fi
    
    if [ $? -eq 0 ]; then
        success "SSL证书申请成功！"
        log "INFO" "SSL证书申请成功: $domain"
        return 0
    else
        danger "SSL证书申请失败！"
        log "ERROR" "SSL证书申请失败: $domain"
        return 1
    fi
}

### === 续期证书 === ###
renew_certificates() {
    info "正在检查并续期所有证书..."
    log "INFO" "检查并续期证书"
    
    # 检查是否已安装certbot
    if ! command -v certbot &>/dev/null; then
        danger "未安装certbot，无法续期证书！"
        log "ERROR" "未安装certbot，无法续期证书"
        return 1
    fi
    
    # 执行续期操作
    certbot renew --non-interactive
    
    if [ $? -eq 0 ]; then
        success "证书续期检查完成！"
        log "INFO" "证书续期检查完成"
        return 0
    else
        danger "证书续期过程中出现错误！"
        log "ERROR" "证书续期过程中出现错误"
        return 1
    fi
}

### === 设置自动续期 === ###
setup_auto_renewal() {
    info "正在设置证书自动续期..."
    log "INFO" "设置证书自动续期"
    
    # 检查是否已安装certbot
    if ! command -v certbot &>/dev/null; then
        danger "未安装certbot，无法设置自动续期！"
        log "ERROR" "未安装certbot，无法设置自动续期"
        return 1
    fi
    
    # 检查crontab中是否已有续期任务
    if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        warn "自动续期任务已存在！"
        log "WARN" "自动续期任务已存在"
    else
        # 添加每天凌晨3点执行续期的crontab任务
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
        
        if [ $? -eq 0 ]; then
            success "已设置证书自动续期（每天凌晨3点）"
            log "INFO" "设置证书自动续期成功"
            return 0
        else
            danger "设置证书自动续期失败！"
            log "ERROR" "设置证书自动续期失败"
            return 1
        fi
    fi
}

### === 列出所有证书 === ###
list_certificates() {
    info "正在列出所有证书..."
    log "INFO" "列出所有证书"
    
    # 检查是否已安装certbot
    if ! command -v certbot &>/dev/null; then
        danger "未安装certbot，无法列出证书！"
        log "ERROR" "未安装certbot，无法列出证书"
        return 1
    fi
    
    # 列出所有证书
    certbot certificates
    
    return 0
}

### === 删除证书 === ###
delete_certificate() {
    local domain=$1
    
    info "正在删除 $domain 的证书..."
    log "INFO" "删除证书: $domain"
    
    # 检查是否已安装certbot
    if ! command -v certbot &>/dev/null; then
        danger "未安装certbot，无法删除证书！"
        log "ERROR" "未安装certbot，无法删除证书"
        return 1
    fi
    
    # 删除证书
    certbot delete --cert-name "$domain"
    
    if [ $? -eq 0 ]; then
        success "证书删除成功！"
        log "INFO" "证书删除成功: $domain"
        return 0
    else
        danger "证书删除失败！"
        log "ERROR" "证书删除失败: $domain"
        return 1
    fi
}

### === 检查证书状态 === ###
check_certificate_status() {
    local domain=$1
    
    info "正在检查 $domain 的证书状态..."
    log "INFO" "检查证书状态: $domain"
    
    # 检查证书是否存在
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        # 获取证书过期时间
        local expiry_date
        expiry_date=$(openssl x509 -in "/etc/letsencrypt/live/$domain/cert.pem" -noout -enddate | cut -d= -f2)
        local expiry_epoch
        expiry_epoch=$(date -d "$expiry_date" +%s)
        local now_epoch
        now_epoch=$(date +%s)
        local days_left
        days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
        
        info "域名: $domain"
        info "证书过期时间: $expiry_date"
        info "剩余天数: $days_left 天"
        
        # 检查是否即将过期（小于30天）
        if [ "$days_left" -lt 30 ]; then
            warn "证书即将过期！建议立即续期"
            log "WARN" "证书即将过期: $domain, 剩余 $days_left 天"
        else
            success "证书状态良好"
            log "INFO" "证书状态良好: $domain, 剩余 $days_left 天"
        fi
        
        return 0
    else
        danger "未找到 $domain 的证书！"
        log "ERROR" "未找到证书: $domain"
        return 1
    fi
}

### === 显示菜单 === ###
show_menu() {
    echo -e "\n${CYAN}===== Let's Encrypt证书管理工具 =====${NC}\n"
    echo "1) 申请新证书"
    echo "2) 续期所有证书"
    echo "3) 设置自动续期"
    echo "4) 列出所有证书"
    echo "5) 删除证书"
    echo "6) 检查证书状态"
    echo "0) 退出"
    echo -e "\n${YELLOW}请输入选项 [0-6]:${NC} "
}

### === 主函数 === ###
main() {
    # 检查依赖
    check_dependencies
    
    # 检测系统类型
    detect_os
    
    # 检测Web服务器
    detect_web_server
    
    # 显示菜单并处理用户选择
    while true; do
        show_menu
        read -r choice
        
        case "$choice" in
            1) # 申请新证书
                echo -e "\n${CYAN}===== 申请新证书 =====${NC}\n"
                read -p "请输入域名 (例如: example.com): " domain
                if [ -z "$domain" ]; then
                    danger "域名不能为空！"
                    continue
                fi
                
                read -p "请输入邮箱地址 (用于Let's Encrypt通知): " email
                if [ -z "$email" ]; then
                    danger "邮箱不能为空！"
                    continue
                fi
                
                read -p "是否使用webroot方式申请？(y/n): " use_webroot
                if [[ "$use_webroot" =~ ^[Yy]$ ]]; then
                    read -p "请输入网站根目录路径: " webroot
                    if [ -z "$webroot" ]; then
                        danger "网站根目录不能为空！"
                        continue
                    fi
                    
                    if [ ! -d "$webroot" ]; then
                        danger "网站根目录不存在！"
                        continue
                    fi
                else
                    webroot=""
                fi
                
                issue_certificate "$domain" "$email" "$webroot"
                ;;
                
            2) # 续期所有证书
                echo -e "\n${CYAN}===== 续期所有证书 =====${NC}\n"
                renew_certificates
                ;;
                
            3) # 设置自动续期
                echo -e "\n${CYAN}===== 设置自动续期 =====${NC}\n"
                setup_auto_renewal
                ;;
                
            4) # 列出所有证书
                echo -e "\n${CYAN}===== 列出所有证书 =====${NC}\n"
                list_certificates
                ;;
                
            5) # 删除证书
                echo -e "\n${CYAN}===== 删除证书 =====${NC}\n"
                read -p "请输入要删除的域名: " domain
                if [ -z "$domain" ]; then
                    danger "域名不能为空！"
                    continue
                fi
                
                delete_certificate "$domain"
                ;;
                
            6) # 检查证书状态
                echo -e "\n${CYAN}===== 检查证书状态 =====${NC}\n"
                read -p "请输入要检查的域名: " domain
                if [ -z "$domain" ]; then
                    danger "域名不能为空！"
                    continue
                fi
                
                check_certificate_status "$domain"
                ;;
                
            0) # 退出
                echo -e "\n${GREEN}感谢使用Let's Encrypt证书管理工具！${NC}\n"
                exit $EXIT_SUCCESS
                ;;
                
            *) # 无效选项
                danger "无效选项，请重新选择！"
                ;;
        esac
        
        echo -e "\n${YELLOW}按Enter键继续...${NC}"
        read -r
    done
}

### === 脚本入口 === ###
main