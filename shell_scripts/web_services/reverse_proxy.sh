#!/bin/bash

### === 脚本描述 === ###
# 名称: 反向代理配置工具
# 功能: 自动生成Nginx和Apache的反向代理配置
# 作者: zjkal <https://www.nodeseek.com/space/25215>
# 创建日期: 2025-07-08
# 许可证: MIT


### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"
SCRIPT_NAME="反向代理配置工具"
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
            NGINX_CONF_DIR="/etc/nginx/conf.d"
            APACHE_CONF_DIR="/etc/apache2/sites-available"
            ;;
        centos|rhel|fedora)
            PACKAGE_MANAGER="yum"
            INSTALL_CMD="yum install -y"
            UPDATE_CMD="yum check-update"
            NGINX_CONF_DIR="/etc/nginx/conf.d"
            APACHE_CONF_DIR="/etc/httpd/conf.d"
            ;;
        alpine)
            PACKAGE_MANAGER="apk"
            INSTALL_CMD="apk add"
            UPDATE_CMD="apk update"
            NGINX_CONF_DIR="/etc/nginx/conf.d"
            APACHE_CONF_DIR="/etc/apache2/conf.d"
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
    
    # 询问用户安装哪个Web服务器
    echo -e "\n请选择要安装的Web服务器:"
    echo "1) Nginx (推荐)"
    echo "2) Apache"
    echo "3) 退出"
    read -p "请输入选项 [1-3]: " choice
    
    case "$choice" in
        1)
            info "将安装Nginx..."
            log "INFO" "用户选择安装Nginx"
            $UPDATE_CMD
            $INSTALL_CMD nginx
            
            if [ $? -eq 0 ]; then
                WEB_SERVER="nginx"
                success "Nginx安装成功！"
                log "INFO" "Nginx安装成功"
                
                # 启动Nginx
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl start nginx
                    systemctl enable nginx
                elif command -v service >/dev/null 2>&1; then
                    service nginx start
                else
                    nginx
                fi
            else
                danger "Nginx安装失败！"
                log "ERROR" "Nginx安装失败"
                exit $EXIT_ERROR
            fi
            ;;
        2)
            info "将安装Apache..."
            log "INFO" "用户选择安装Apache"
            $UPDATE_CMD
            
            case "$PACKAGE_MANAGER" in
                apt)
                    $INSTALL_CMD apache2
                    ;;
                yum)
                    $INSTALL_CMD httpd
                    ;;
                apk)
                    $INSTALL_CMD apache2
                    ;;
            esac
            
            if [ $? -eq 0 ]; then
                WEB_SERVER="apache"
                success "Apache安装成功！"
                log "INFO" "Apache安装成功"
                
                # 启动Apache
                if command -v systemctl >/dev/null 2>&1; then
                    case "$PACKAGE_MANAGER" in
                        apt|apk)
                            systemctl start apache2
                            systemctl enable apache2
                            ;;
                        yum)
                            systemctl start httpd
                            systemctl enable httpd
                            ;;
                    esac
                elif command -v service >/dev/null 2>&1; then
                    case "$PACKAGE_MANAGER" in
                        apt|apk)
                            service apache2 start
                            ;;
                        yum)
                            service httpd start
                            ;;
                    esac
                fi
            else
                danger "Apache安装失败！"
                log "ERROR" "Apache安装失败"
                exit $EXIT_ERROR
            fi
            ;;
        3|*)
            info "退出安装"
            log "INFO" "用户选择退出"
            exit $EXIT_SUCCESS
            ;;
    esac
}

### === 创建Nginx反向代理配置 === ###
create_nginx_proxy() {
    local domain=$1
    local target_url=$2
    local ssl=$3
    local timestamp=$(date +%Y%m%d%H%M%S)
    local conf_file="$NGINX_CONF_DIR/${domain}.conf"
    
    # 备份原配置（如果存在）
    if [ -f "$conf_file" ]; then
        cp "$conf_file" "${conf_file}.bak_${timestamp}"
        success "已备份原配置到: ${conf_file}.bak_${timestamp}"
        log "INFO" "备份配置: ${conf_file}.bak_${timestamp}"
    fi
    
    # 创建基本配置
    if [ "$ssl" = "yes" ]; then
        cat > "$conf_file" << EOF
server {
    listen 80;
    server_name ${domain} www.${domain};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${domain} www.${domain};
    
    # SSL配置
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # 反向代理配置
    location / {
        proxy_pass ${target_url};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        proxy_connect_timeout 90;
        proxy_send_timeout 90;
        proxy_read_timeout 90;
    }
    
    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
    }
    
    # 日志配置
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
}
EOF
    else
        cat > "$conf_file" << EOF
server {
    listen 80;
    server_name ${domain} www.${domain};
    
    # 反向代理配置
    location / {
        proxy_pass ${target_url};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        proxy_connect_timeout 90;
        proxy_send_timeout 90;
        proxy_read_timeout 90;
    }
    
    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
    }
    
    # 日志配置
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
}
EOF
    fi
    
    # 测试配置
    if nginx -t; then
        success "Nginx配置测试通过！"
        log "INFO" "Nginx配置测试通过"
        
        # 重启Nginx
        if command -v systemctl >/dev/null 2>&1; then
            systemctl reload nginx
        elif command -v service >/dev/null 2>&1; then
            service nginx reload
        else
            nginx -s reload
        fi
        
        success "Nginx反向代理配置完成！域名: $domain -> $target_url"
        log "INFO" "Nginx反向代理配置完成: $domain -> $target_url"
        return 0
    else
        danger "Nginx配置测试失败！"
        log "ERROR" "Nginx配置测试失败"
        
        # 恢复备份或删除失败的配置
        if [ -f "${conf_file}.bak_${timestamp}" ]; then
            cp "${conf_file}.bak_${timestamp}" "$conf_file"
            warn "已恢复原配置"
            log "WARN" "已恢复原配置"
        else
            rm -f "$conf_file"
        fi
        
        return 1
    fi
}

### === 创建Apache反向代理配置 === ###
create_apache_proxy() {
    local domain=$1
    local target_url=$2
    local ssl=$3
    local timestamp=$(date +%Y%m%d%H%M%S)
    
    # 确定Apache配置文件名
    case "$PACKAGE_MANAGER" in
        apt)
            local conf_file="$APACHE_CONF_DIR/${domain}.conf"
            ;;
        yum|apk)
            local conf_file="$APACHE_CONF_DIR/${domain}.conf"
            ;;
    esac
    
    # 备份原配置（如果存在）
    if [ -f "$conf_file" ]; then
        cp "$conf_file" "${conf_file}.bak_${timestamp}"
        success "已备份原配置到: ${conf_file}.bak_${timestamp}"
        log "INFO" "备份配置: ${conf_file}.bak_${timestamp}"
    fi
    
    # 确保必要的模块已启用
    case "$PACKAGE_MANAGER" in
        apt)
            a2enmod proxy
            a2enmod proxy_http
            a2enmod proxy_balancer
            a2enmod lbmethod_byrequests
            a2enmod rewrite
            a2enmod headers
            if [ "$ssl" = "yes" ]; then
                a2enmod ssl
            fi
            ;;
        yum|apk)
            # 在CentOS/RHEL/Alpine中，模块通常默认已加载或在配置文件中启用
            ;;
    esac
    
    # 创建基本配置
    if [ "$ssl" = "yes" ]; then
        cat > "$conf_file" << EOF
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias www.${domain}
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName ${domain}
    ServerAlias www.${domain}
    
    # SSL配置
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${domain}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${domain}/privkey.pem
    
    # 反向代理配置
    ProxyPreserveHost On
    ProxyPass / ${target_url}/
    ProxyPassReverse / ${target_url}/
    
    # 添加代理相关头信息
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"
    
    # 日志配置
    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
</VirtualHost>
EOF
    else
        cat > "$conf_file" << EOF
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias www.${domain}
    
    # 反向代理配置
    ProxyPreserveHost On
    ProxyPass / ${target_url}/
    ProxyPassReverse / ${target_url}/
    
    # 添加代理相关头信息
    RequestHeader set X-Forwarded-Proto "http"
    RequestHeader set X-Forwarded-Port "80"
    
    # 日志配置
    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
</VirtualHost>
EOF
    fi
    
    # 启用站点（仅Debian/Ubuntu）
    if [ "$PACKAGE_MANAGER" = "apt" ]; then
        a2ensite ${domain}.conf
    fi
    
    # 测试配置
    if apachectl configtest; then
        success "Apache配置测试通过！"
        log "INFO" "Apache配置测试通过"
        
        # 重启Apache
        if command -v systemctl >/dev/null 2>&1; then
            case "$PACKAGE_MANAGER" in
                apt|apk)
                    systemctl reload apache2
                    ;;
                yum)
                    systemctl reload httpd
                    ;;
            esac
        elif command -v service >/dev/null 2>&1; then
            case "$PACKAGE_MANAGER" in
                apt|apk)
                    service apache2 reload
                    ;;
                yum)
                    service httpd reload
                    ;;
            esac
        else
            apachectl graceful
        fi
        
        success "Apache反向代理配置完成！域名: $domain -> $target_url"
        log "INFO" "Apache反向代理配置完成: $domain -> $target_url"
        return 0
    else
        danger "Apache配置测试失败！"
        log "ERROR" "Apache配置测试失败"
        
        # 恢复备份或删除失败的配置
        if [ -f "${conf_file}.bak_${timestamp}" ]; then
            cp "${conf_file}.bak_${timestamp}" "$conf_file"
            warn "已恢复原配置"
            log "WARN" "已恢复原配置"
        else
            rm -f "$conf_file"
            # 禁用站点（仅Debian/Ubuntu）
            if [ "$PACKAGE_MANAGER" = "apt" ]; then
                a2dissite ${domain}.conf 2>/dev/null || true
            fi
        fi
        
        return 1
    fi
}

### === 主函数 === ###
main() {
    # 检查依赖
    check_dependencies
    
    # 检测系统类型
    detect_os
    
    # 检测Web服务器
    detect_web_server
    
    # 获取反向代理配置信息
    echo -e "\n请输入反向代理配置信息:"
    read -p "域名 (例如: example.com): " domain
    if [ -z "$domain" ]; then
        danger "域名不能为空！"
        log "ERROR" "域名为空"
        exit $EXIT_ERROR
    fi
    
    read -p "目标URL (例如: http://localhost:8080): " target_url
    if [ -z "$target_url" ]; then
        danger "目标URL不能为空！"
        log "ERROR" "目标URL为空"
        exit $EXIT_ERROR
    fi
    
    # 检查目标URL格式
    if ! [[ "$target_url" =~ ^https?:// ]]; then
        warn "目标URL应以http://或https://开头，正在自动添加http://"
        log "WARN" "目标URL格式不正确，自动添加http://"
        target_url="http://$target_url"
    fi
    
    read -p "是否配置SSL (y/n): " ssl_choice
    if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
        ssl="yes"
        
        # 检查是否已安装certbot
        if ! command -v certbot &>/dev/null; then
            warn "未检测到certbot，SSL配置需要certbot"
            log "WARN" "未检测到certbot"
            
            read -p "是否安装certbot (y/n): " install_certbot
            if [[ "$install_certbot" =~ ^[Yy]$ ]]; then
                info "正在安装certbot..."
                log "INFO" "安装certbot"
                
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
                
                if [ $? -ne 0 ]; then
                    danger "安装certbot失败！将继续配置HTTP反向代理"
                    log "ERROR" "安装certbot失败"
                    ssl="no"
                fi
            else
                info "跳过SSL配置，将配置HTTP反向代理"
                log "INFO" "用户选择跳过SSL配置"
                ssl="no"
            fi
        fi
        
        # 如果选择了SSL并且certbot可用，获取证书
        if [ "$ssl" = "yes" ] && command -v certbot &>/dev/null; then
            read -p "请输入邮箱地址 (用于Let's Encrypt通知): " email
            if [ -z "$email" ]; then
                danger "邮箱不能为空！将继续配置HTTP反向代理"
                log "ERROR" "邮箱为空"
                ssl="no"
            else
                info "正在申请SSL证书..."
                log "INFO" "申请SSL证书: $domain"
                
                if [ "$WEB_SERVER" = "nginx" ]; then
                    certbot --nginx -d "$domain" -d "www.$domain" --email "$email" --agree-tos --non-interactive
                elif [ "$WEB_SERVER" = "apache" ]; then
                    certbot --apache -d "$domain" -d "www.$domain" --email "$email" --agree-tos --non-interactive
                fi
                
                if [ $? -ne 0 ]; then
                    danger "SSL证书申请失败！将继续配置HTTP反向代理"
                    log "ERROR" "SSL证书申请失败"
                    ssl="no"
                else
                    success "SSL证书申请成功！"
                    log "INFO" "SSL证书申请成功"
                    
                    # 设置自动续期
                    if ! crontab -l | grep -q certbot; then
                        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
                        success "已设置证书自动续期（每天凌晨3点）"
                        log "INFO" "设置证书自动续期"
                    fi
                fi
            fi
        fi
    else
        ssl="no"
    fi
    
    # 创建反向代理配置
    if [ "$WEB_SERVER" = "nginx" ]; then
        create_nginx_proxy "$domain" "$target_url" "$ssl"
    elif [ "$WEB_SERVER" = "apache" ]; then
        create_apache_proxy "$domain" "$target_url" "$ssl"
    else
        danger "未检测到支持的Web服务器！"
        log "ERROR" "未检测到支持的Web服务器"
        exit $EXIT_ERROR
    fi
    
    if [ $? -eq 0 ]; then
        success "反向代理配置完成！"
        info "域名: $domain"
        info "目标URL: $target_url"
        info "SSL: $ssl"
        log "INFO" "反向代理配置完成: domain=$domain, target=$target_url, ssl=$ssl"
    else
        danger "反向代理配置失败！"
        log "ERROR" "反向代理配置失败"
        exit $EXIT_ERROR
    fi
    
    exit $EXIT_SUCCESS
}

### === 脚本入口 === ###
main