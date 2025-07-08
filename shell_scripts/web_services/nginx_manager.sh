#!/bin/bash

### === 脚本描述 === ###
# 名称: Nginx管理工具
# 功能: 安装、配置、优化Nginx服务器和SSL证书配置
# 作者: zjkal <https://www.nodeseek.com/space/25215>
# 创建日期: 2025-07-08
# 许可证: MIT


### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"
SCRIPT_NAME="Nginx管理工具"
SCRIPT_AUTHOR="zjkal <https://www.nodeseek.com/space/25215>"

echo -e "\033[33m[信息] $SCRIPT_NAME ，版本: $SCRIPT_VERSION\033[0m"
echo -e "\033[33m[作者] $SCRIPT_AUTHOR\033[0m"

### === 权限检查 === ###
[[ $EUID -ne 0 ]] && echo -e "\033[31m[错误] 请以root用户或sudo运行此脚本！\033[0m" && exit 1

### === 依赖检查 === ###
check_dependencies() {
    local deps=("curl" "wget" "awk" "sed" "grep")
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

### === 安装Nginx === ###
install_nginx() {
    info "开始安装Nginx..."
    log "INFO" "开始安装Nginx"
    
    case "$PACKAGE_MANAGER" in
        apt)
            $UPDATE_CMD
            $INSTALL_CMD nginx
            ;;
        yum)
            $INSTALL_CMD epel-release
            $UPDATE_CMD
            $INSTALL_CMD nginx
            ;;
        apk)
            $UPDATE_CMD
            $INSTALL_CMD nginx
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        success "Nginx安装成功！"
        log "INFO" "Nginx安装成功"
        
        # 启动Nginx
        if command -v systemctl >/dev/null 2>&1; then
            systemctl start nginx
            systemctl enable nginx
        elif command -v service >/dev/null 2>&1; then
            service nginx start
            # 添加开机启动
            if [ -f /etc/rc.local ]; then
                grep -q "service nginx start" /etc/rc.local || echo "service nginx start" >> /etc/rc.local
                chmod +x /etc/rc.local
            fi
        else
            warn "无法自动启动Nginx，请手动启动"
            log "WARN" "无法自动启动Nginx"
        fi
        
        # 显示Nginx状态
        info "Nginx状态:"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl status nginx
        elif command -v service >/dev/null 2>&1; then
            service nginx status
        else
            ps aux | grep nginx
        fi
    else
        danger "Nginx安装失败！"
        log "ERROR" "Nginx安装失败"
        exit $EXIT_ERROR
    fi
}

### === 配置Nginx === ###
configure_nginx() {
    info "开始配置Nginx..."
    log "INFO" "开始配置Nginx"
    
    # 备份原配置
    local timestamp=$(date +%Y%m%d%H%M%S)
    local nginx_conf="/etc/nginx/nginx.conf"
    local backup_file="${nginx_conf}.bak_${timestamp}"
    
    if [ -f "$nginx_conf" ]; then
        cp "$nginx_conf" "$backup_file"
        success "已备份原配置到: $backup_file"
        log "INFO" "备份配置: $backup_file"
    else
        danger "Nginx配置文件不存在: $nginx_conf"
        log "ERROR" "Nginx配置文件不存在"
        exit $EXIT_ERROR
    fi
    
    # 创建网站目录
    read -p "请输入网站根目录路径 [/var/www/html]: " web_root
    web_root=${web_root:-/var/www/html}
    
    mkdir -p "$web_root"
    chown -R www-data:www-data "$web_root" 2>/dev/null || true
    
    # 创建示例页面
    cat > "$web_root/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to Nginx!</title>
    <style>
        body {
            width: 35em;
            margin: 0 auto;
            font-family: Tahoma, Verdana, Arial, sans-serif;
        }
    </style>
</head>
<body>
    <h1>Welcome to Nginx!</h1>
    <p>If you see this page, the nginx web server is successfully installed and
    working.</p>

    <p>For online documentation and support please refer to
    <a href="http://nginx.org/">nginx.org</a>.</p>

    <p><em>Thank you for using nginx.</em></p>
</body>
</html>
EOF
    
    # 配置虚拟主机
    read -p "请输入域名 [example.com]: " domain
    domain=${domain:-example.com}
    
    local vhost_file="/etc/nginx/conf.d/${domain}.conf"
    
    cat > "$vhost_file" << EOF
server {
    listen 80;
    server_name ${domain} www.${domain};
    root ${web_root};
    index index.html index.htm index.php;
    
    location / {
        try_files \$uri \$uri/ =404;
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
    
    # 测试配置
    if nginx -t; then
        success "Nginx配置测试通过！"
        log "INFO" "Nginx配置测试通过"
        
        # 重启Nginx
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart nginx
        elif command -v service >/dev/null 2>&1; then
            service nginx restart
        else
            nginx -s reload
        fi
        
        success "Nginx配置完成！虚拟主机已创建: $domain"
        log "INFO" "Nginx配置完成: $domain"
    else
        danger "Nginx配置测试失败！"
        log "ERROR" "Nginx配置测试失败"
        
        # 恢复备份
        cp "$backup_file" "$nginx_conf"
        rm -f "$vhost_file"
        
        warn "已恢复原配置"
        log "WARN" "已恢复原配置"
        exit $EXIT_ERROR
    fi
}

### === 优化Nginx === ###
optimize_nginx() {
    info "开始优化Nginx..."
    log "INFO" "开始优化Nginx"
    
    # 备份原配置
    local timestamp=$(date +%Y%m%d%H%M%S)
    local nginx_conf="/etc/nginx/nginx.conf"
    local backup_file="${nginx_conf}.bak_${timestamp}"
    
    if [ -f "$nginx_conf" ]; then
        cp "$nginx_conf" "$backup_file"
        success "已备份原配置到: $backup_file"
        log "INFO" "备份配置: $backup_file"
    else
        danger "Nginx配置文件不存在: $nginx_conf"
        log "ERROR" "Nginx配置文件不存在"
        exit $EXIT_ERROR
    fi
    
    # 获取系统信息
    local cpu_cores=$(grep -c processor /proc/cpuinfo)
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    
    # 计算优化参数
    local worker_processes=$cpu_cores
    local worker_connections=$((1024 * cpu_cores))
    local worker_rlimit_nofile=$((worker_connections * 2))
    
    # 创建优化配置
    cat > "$nginx_conf" << EOF
user www-data;
worker_processes $worker_processes;
worker_rlimit_nofile $worker_rlimit_nofile;

events {
    worker_connections $worker_connections;
    multi_accept on;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    # MIME类型
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # 日志格式
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;
    
    # Gzip压缩
    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    # 文件缓存
    open_file_cache max=1000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
    
    # 客户端缓冲区
    client_max_body_size 10m;
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    
    # 包含其他配置
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    # 测试配置
    if nginx -t; then
        success "Nginx配置测试通过！"
        log "INFO" "Nginx配置测试通过"
        
        # 重启Nginx
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart nginx
        elif command -v service >/dev/null 2>&1; then
            service nginx restart
        else
            nginx -s reload
        fi
        
        success "Nginx优化完成！"
        info "优化参数:"
        info "  - Worker进程: $worker_processes"
        info "  - 连接数: $worker_connections"
        info "  - 文件描述符限制: $worker_rlimit_nofile"
        log "INFO" "Nginx优化完成: worker_processes=$worker_processes, worker_connections=$worker_connections"
    else
        danger "Nginx配置测试失败！"
        log "ERROR" "Nginx配置测试失败"
        
        # 恢复备份
        cp "$backup_file" "$nginx_conf"
        
        warn "已恢复原配置"
        log "WARN" "已恢复原配置"
        exit $EXIT_ERROR
    fi
}

### === 配置SSL === ###
configure_ssl() {
    info "开始配置SSL证书..."
    log "INFO" "开始配置SSL证书"
    
    # 检查是否安装了certbot
    if ! command -v certbot &>/dev/null; then
        info "正在安装certbot..."
        log "INFO" "安装certbot"
        
        case "$PACKAGE_MANAGER" in
            apt)
                $UPDATE_CMD
                $INSTALL_CMD certbot python3-certbot-nginx
                ;;
            yum)
                $INSTALL_CMD epel-release
                $UPDATE_CMD
                $INSTALL_CMD certbot python3-certbot-nginx
                ;;
            apk)
                $UPDATE_CMD
                $INSTALL_CMD certbot certbot-nginx
                ;;
        esac
        
        if [ $? -ne 0 ]; then
            danger "安装certbot失败！"
            log "ERROR" "安装certbot失败"
            exit $EXIT_ERROR
        fi
    fi
    
    # 获取域名
    read -p "请输入要配置SSL的域名: " domain
    if [ -z "$domain" ]; then
        danger "域名不能为空！"
        log "ERROR" "域名为空"
        exit $EXIT_ERROR
    fi
    
    # 获取邮箱
    read -p "请输入邮箱地址 (用于Let's Encrypt通知): " email
    if [ -z "$email" ]; then
        danger "邮箱不能为空！"
        log "ERROR" "邮箱为空"
        exit $EXIT_ERROR
    fi
    
    # 运行certbot
    info "正在申请SSL证书..."
    log "INFO" "申请SSL证书: $domain"
    
    certbot --nginx -d "$domain" -d "www.$domain" --email "$email" --agree-tos --non-interactive
    
    if [ $? -eq 0 ]; then
        success "SSL证书配置成功！"
        log "INFO" "SSL证书配置成功: $domain"
        
        # 设置自动续期
        if ! crontab -l | grep -q certbot; then
            (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
            success "已设置证书自动续期（每天凌晨3点）"
            log "INFO" "设置证书自动续期"
        fi
    else
        danger "SSL证书配置失败！"
        log "ERROR" "SSL证书配置失败: $domain"
        exit $EXIT_ERROR
    fi
}

### === 主函数 === ###
main() {
    # 检查依赖
    check_dependencies
    
    # 检测系统类型
    detect_os
    
    # 根据参数执行相应功能
    case "$1" in
        install)
            install_nginx
            ;;
        config)
            configure_nginx
            ;;
        optimize)
            optimize_nginx
            ;;
        ssl)
            configure_ssl
            ;;
        *)
            info "Nginx管理工具"
            info "用法: $0 {install|config|optimize|ssl}"
            info "  install  - 安装Nginx"
            info "  config   - 配置Nginx虚拟主机"
            info "  optimize - 优化Nginx性能"
            info "  ssl      - 配置SSL证书"
            exit $EXIT_SUCCESS
            ;;
    esac
    
    exit $EXIT_SUCCESS
}

### === 脚本入口 === ###
main "$@"