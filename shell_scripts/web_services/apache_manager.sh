#!/bin/bash

### === 脚本描述 === ###
# 名称: Apache管理工具
# 功能: 安装、配置、优化Apache服务器
# 作者: zjkal <https://www.nodeseek.com/space/25215>
# 创建日期: 2025-07-08
# 许可证: MIT


### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"
SCRIPT_NAME="Apache管理工具"
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
            APACHE_SERVICE="apache2"
            APACHE_CONFIG="/etc/apache2/apache2.conf"
            APACHE_VHOST_DIR="/etc/apache2/sites-available"
            APACHE_MODS_DIR="/etc/apache2/mods-available"
            APACHE_USER="www-data"
            ;;
        centos|rhel|fedora)
            PACKAGE_MANAGER="yum"
            INSTALL_CMD="yum install -y"
            UPDATE_CMD="yum check-update"
            APACHE_SERVICE="httpd"
            APACHE_CONFIG="/etc/httpd/conf/httpd.conf"
            APACHE_VHOST_DIR="/etc/httpd/conf.d"
            APACHE_MODS_DIR="/etc/httpd/conf.modules.d"
            APACHE_USER="apache"
            ;;
        alpine)
            PACKAGE_MANAGER="apk"
            INSTALL_CMD="apk add"
            UPDATE_CMD="apk update"
            APACHE_SERVICE="apache2"
            APACHE_CONFIG="/etc/apache2/httpd.conf"
            APACHE_VHOST_DIR="/etc/apache2/conf.d"
            APACHE_MODS_DIR="/etc/apache2/conf.d"
            APACHE_USER="apache"
            ;;
        *)
            danger "不支持的操作系统: $OS"
            exit $EXIT_ERROR
            ;;
    esac
    
    info "检测到操作系统: $OS $VERSION"
    log "INFO" "操作系统: $OS $VERSION"
}

### === 安装Apache === ###
install_apache() {
    info "开始安装Apache..."
    log "INFO" "开始安装Apache"
    
    case "$PACKAGE_MANAGER" in
        apt)
            $UPDATE_CMD
            $INSTALL_CMD apache2
            ;;
        yum)
            $UPDATE_CMD
            $INSTALL_CMD httpd
            ;;
        apk)
            $UPDATE_CMD
            $INSTALL_CMD apache2
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        success "Apache安装成功！"
        log "INFO" "Apache安装成功"
        
        # 启动Apache
        if command -v systemctl >/dev/null 2>&1; then
            systemctl start $APACHE_SERVICE
            systemctl enable $APACHE_SERVICE
        elif command -v service >/dev/null 2>&1; then
            service $APACHE_SERVICE start
            # 添加开机启动
            if [ -f /etc/rc.local ]; then
                grep -q "service $APACHE_SERVICE start" /etc/rc.local || echo "service $APACHE_SERVICE start" >> /etc/rc.local
                chmod +x /etc/rc.local
            fi
        else
            warn "无法自动启动Apache，请手动启动"
            log "WARN" "无法自动启动Apache"
        fi
        
        # 显示Apache状态
        info "Apache状态:"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl status $APACHE_SERVICE
        elif command -v service >/dev/null 2>&1; then
            service $APACHE_SERVICE status
        else
            ps aux | grep apache
        fi
    else
        danger "Apache安装失败！"
        log "ERROR" "Apache安装失败"
        exit $EXIT_ERROR
    fi
}

### === 配置Apache === ###
configure_apache() {
    info "开始配置Apache..."
    log "INFO" "开始配置Apache"
    
    # 备份原配置
    local timestamp=$(date +%Y%m%d%H%M%S)
    local backup_file="${APACHE_CONFIG}.bak_${timestamp}"
    
    if [ -f "$APACHE_CONFIG" ]; then
        cp "$APACHE_CONFIG" "$backup_file"
        success "已备份原配置到: $backup_file"
        log "INFO" "备份配置: $backup_file"
    else
        danger "Apache配置文件不存在: $APACHE_CONFIG"
        log "ERROR" "Apache配置文件不存在"
        exit $EXIT_ERROR
    fi
    
    # 创建网站目录
    read -p "请输入网站根目录路径 [/var/www/html]: " web_root
    web_root=${web_root:-/var/www/html}
    
    mkdir -p "$web_root"
    chown -R $APACHE_USER:$APACHE_USER "$web_root" 2>/dev/null || true
    
    # 创建示例页面
    cat > "$web_root/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to Apache!</title>
    <style>
        body {
            width: 35em;
            margin: 0 auto;
            font-family: Tahoma, Verdana, Arial, sans-serif;
        }
    </style>
</head>
<body>
    <h1>Welcome to Apache!</h1>
    <p>If you see this page, the Apache web server is successfully installed and
    working.</p>

    <p>For online documentation and support please refer to
    <a href="https://httpd.apache.org/">httpd.apache.org</a>.</p>

    <p><em>Thank you for using Apache.</em></p>
</body>
</html>
EOF
    
    # 配置虚拟主机
    read -p "请输入域名 [example.com]: " domain
    domain=${domain:-example.com}
    
    case "$PACKAGE_MANAGER" in
        apt)
            local vhost_file="$APACHE_VHOST_DIR/$domain.conf"
            
            cat > "$vhost_file" << EOF
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias www.${domain}
    DocumentRoot ${web_root}
    
    <Directory ${web_root}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
</VirtualHost>
EOF
            
            # 启用站点
            a2ensite $domain.conf
            ;;
        yum|apk)
            local vhost_file="$APACHE_VHOST_DIR/$domain.conf"
            
            cat > "$vhost_file" << EOF
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias www.${domain}
    DocumentRoot ${web_root}
    
    <Directory ${web_root}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog logs/${domain}_error.log
    CustomLog logs/${domain}_access.log combined
</VirtualHost>
EOF
            ;;
    esac
    
    # 启用必要模块（仅Debian/Ubuntu）
    if [ "$PACKAGE_MANAGER" = "apt" ]; then
        a2enmod rewrite
        a2enmod ssl
    fi
    
    # 测试配置
    if apachectl configtest; then
        success "Apache配置测试通过！"
        log "INFO" "Apache配置测试通过"
        
        # 重启Apache
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart $APACHE_SERVICE
        elif command -v service >/dev/null 2>&1; then
            service $APACHE_SERVICE restart
        else
            apachectl restart
        fi
        
        success "Apache配置完成！虚拟主机已创建: $domain"
        log "INFO" "Apache配置完成: $domain"
    else
        danger "Apache配置测试失败！"
        log "ERROR" "Apache配置测试失败"
        
        # 恢复备份
        cp "$backup_file" "$APACHE_CONFIG"
        rm -f "$vhost_file"
        
        warn "已恢复原配置"
        log "WARN" "已恢复原配置"
        exit $EXIT_ERROR
    fi
}

### === 优化Apache === ###
optimize_apache() {
    info "开始优化Apache..."
    log "INFO" "开始优化Apache"
    
    # 备份原配置
    local timestamp=$(date +%Y%m%d%H%M%S)
    local backup_file="${APACHE_CONFIG}.bak_${timestamp}"
    
    if [ -f "$APACHE_CONFIG" ]; then
        cp "$APACHE_CONFIG" "$backup_file"
        success "已备份原配置到: $backup_file"
        log "INFO" "备份配置: $backup_file"
    else
        danger "Apache配置文件不存在: $APACHE_CONFIG"
        log "ERROR" "Apache配置文件不存在"
        exit $EXIT_ERROR
    fi
    
    # 获取系统信息
    local cpu_cores=$(grep -c processor /proc/cpuinfo)
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    
    # 计算优化参数
    local max_clients=$((cpu_cores * 150))
    local server_limit=$((max_clients / 150 + 1))
    local max_requests_per_child=10000
    
    # 根据不同系统优化配置
    case "$PACKAGE_MANAGER" in
        apt)
            # 启用MPM Event模块
            a2dismod mpm_prefork
            a2enmod mpm_event
            
            # 创建MPM配置
            local mpm_conf="$APACHE_MODS_DIR/mpm_event.conf"
            cat > "$mpm_conf" << EOF
<IfModule mpm_event_module>
    StartServers             $cpu_cores
    ServerLimit              $server_limit
    MinSpareThreads          25
    MaxSpareThreads          75
    ThreadLimit              64
    ThreadsPerChild          25
    MaxRequestWorkers        $max_clients
    MaxConnectionsPerChild   $max_requests_per_child
</IfModule>
EOF
            
            # 启用性能相关模块
            a2enmod expires
            a2enmod headers
            a2enmod deflate
            ;;
        yum)
            # 创建MPM配置
            local mpm_conf="$APACHE_MODS_DIR/00-mpm.conf"
            cat > "$mpm_conf" << EOF
<IfModule mpm_event_module>
    StartServers             $cpu_cores
    ServerLimit              $server_limit
    MinSpareThreads          25
    MaxSpareThreads          75
    ThreadLimit              64
    ThreadsPerChild          25
    MaxRequestWorkers        $max_clients
    MaxConnectionsPerChild   $max_requests_per_child
</IfModule>

# 加载MPM Event模块
LoadModule mpm_event_module modules/mod_mpm_event.so
EOF
            
            # 确保其他MPM模块被注释掉
            sed -i 's/^LoadModule mpm_prefork_module/#LoadModule mpm_prefork_module/' "$APACHE_CONFIG"
            sed -i 's/^LoadModule mpm_worker_module/#LoadModule mpm_worker_module/' "$APACHE_CONFIG"
            ;;
        apk)
            # 创建MPM配置
            local mpm_conf="$APACHE_MODS_DIR/mpm.conf"
            cat > "$mpm_conf" << EOF
<IfModule mpm_event_module>
    StartServers             $cpu_cores
    ServerLimit              $server_limit
    MinSpareThreads          25
    MaxSpareThreads          75
    ThreadLimit              64
    ThreadsPerChild          25
    MaxRequestWorkers        $max_clients
    MaxConnectionsPerChild   $max_requests_per_child
</IfModule>
EOF
            ;;
    esac
    
    # 创建性能优化配置
    local perf_conf="$APACHE_VHOST_DIR/performance.conf"
    cat > "$perf_conf" << EOF
# 启用Gzip压缩
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript application/x-javascript application/json
    BrowserMatch ^Mozilla/4 gzip-only-text/html
    BrowserMatch ^Mozilla/4\.0[678] no-gzip
    BrowserMatch \bMSIE !no-gzip !gzip-only-text/html
</IfModule>

# 启用浏览器缓存
<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresDefault "access plus 1 month"
    ExpiresByType image/jpg "access plus 1 year"
    ExpiresByType image/jpeg "access plus 1 year"
    ExpiresByType image/gif "access plus 1 year"
    ExpiresByType image/png "access plus 1 year"
    ExpiresByType image/svg+xml "access plus 1 year"
    ExpiresByType text/css "access plus 1 month"
    ExpiresByType text/javascript "access plus 1 month"
    ExpiresByType application/javascript "access plus 1 month"
    ExpiresByType application/x-javascript "access plus 1 month"
    ExpiresByType application/x-shockwave-flash "access plus 1 month"
    ExpiresByType image/ico "access plus 1 year"
    ExpiresByType image/x-icon "access plus 1 year"
    ExpiresByType text/html "access plus 1 week"
</IfModule>

# 设置ETags
<IfModule mod_headers.c>
    Header unset ETag
    FileETag None
</IfModule>

# 关闭KeepAlive以减少内存使用（高流量站点可能需要启用）
KeepAlive Off

# 如果启用KeepAlive，设置合理的超时时间
# KeepAlive On
# KeepAliveTimeout 2
# MaxKeepAliveRequests 100

# 禁用不需要的模块（根据实际需求调整）
# 示例：如果不需要CGI，可以禁用
# <IfModule mod_cgi.c>
#     <Location />
#         Options -ExecCGI
#     </Location>
# </IfModule>
EOF
    
    # 测试配置
    if apachectl configtest; then
        success "Apache配置测试通过！"
        log "INFO" "Apache配置测试通过"
        
        # 重启Apache
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart $APACHE_SERVICE
        elif command -v service >/dev/null 2>&1; then
            service $APACHE_SERVICE restart
        else
            apachectl restart
        fi
        
        success "Apache优化完成！"
        info "优化参数:"
        info "  - 最大客户端连接数: $max_clients"
        info "  - 服务器限制: $server_limit"
        info "  - 每个子进程最大请求数: $max_requests_per_child"
        log "INFO" "Apache优化完成: max_clients=$max_clients, server_limit=$server_limit"
    else
        danger "Apache配置测试失败！"
        log "ERROR" "Apache配置测试失败"
        
        # 恢复备份
        cp "$backup_file" "$APACHE_CONFIG"
        rm -f "$perf_conf"
        
        warn "已恢复原配置"
        log "WARN" "已恢复原配置"
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
            install_apache
            ;;
        config)
            configure_apache
            ;;
        optimize)
            optimize_apache
            ;;
        *)
            info "Apache管理工具"
            info "用法: $0 {install|config|optimize}"
            info "  install  - 安装Apache"
            info "  config   - 配置Apache虚拟主机"
            info "  optimize - 优化Apache性能"
            exit $EXIT_SUCCESS
            ;;
    esac
    
    exit $EXIT_SUCCESS
}

### === 脚本入口 === ###
main "$@"