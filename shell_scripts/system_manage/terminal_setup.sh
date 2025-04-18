#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: terminal_setup.sh
# 功能: 这是一个终端优化与美化脚本，用于优化终端的展示效果与功能。
# 作者: rouxyang <https://www.nodeseek.com/space/29457>
# 创建日期: 2025-04-13
# 许可证: MIT

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

### === 信号捕获 === ###
cleanup() {
    log "INFO" "脚本被中断..."
    echo -e "${YELLOW}[警告] 脚本已退出！${NC}"
    exit $EXIT_INTERRUPT
}
trap cleanup SIGINT SIGTERM

# 日志文件
LOG_FILE="/tmp/terminal_setup.log"
echo "===== 终端配置脚本日志 ($(date)) =====" >> "$LOG_FILE"

### ==== 彩色输出函数 ==== ###
info()    { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[信息]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[成功]${NC} $1" | tee -a "$LOG_FILE"; }
warning() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[提示]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[错误]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }


### ==== 检测命令是否存在 ==== ###

check_command() {
    local pkg="$1"
    info "检查命令 $pkg 是否存在..."
    if [[ "$pkg" == "bash-completion" ]]; then
        case "$OS_ID" in
            debian|ubuntu|linuxmint)
                dpkg -s bash-completion >/dev/null 2>&1 && return 0
                return 1
                ;;
            centos|rhel|fedora|rocky|almalinux)
                rpm -q bash-completion >/dev/null 2>&1 && return 0
                return 1
                ;;
            arch|manjaro)
                pacman -Qs bash-completion >/dev/null 2>&1 && return 0
                return 1
                ;;
            opensuse|suse)
                rpm -q bash-completion >/dev/null 2>&1 && return 0
                return 1
                ;;
            alpine)
                apk info bash-completion >/dev/null 2>&1 && return 0
                return 1
                ;;
            openwrt)
                opkg list-installed | grep -q bash-completion && return 0
                return 1
                ;;
            *)
                warning "无法检查 $pkg 的安装状态（未知发行版：$OS_ID）"
                return 1
                ;;
        esac
    else
        command -v "$pkg" >/dev/null 2>&1 && return 0
        return 1
    fi
}

### ==== 检测发行版 ==== ###
detect_os() {
    echo "[信息] 检测操作系统..." >&2 | tee -a "$LOG_FILE"
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ -n "$ID" ]]; then
            echo "$ID" | tr -d '\n' | tr -s ' '
        else
            error "无法获取发行版 ID（/etc/os-release 格式错误）"
        fi
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -is | tr '[:upper:]' '[:lower:]' | tr -d '\n' | tr -s ' '
    elif [[ -f /etc/redhat-release ]]; then
        echo "centos"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        error "无法检测发行版（缺少 /etc/os-release 或其他标识文件）"
    fi
}
OS_ID=$(detect_os)
info "检测到发行版：$OS_ID"

### ==== 备份配置文件 ==== ###
backup_config() {
    local file="$1"
    info "检查备份 $file..."
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.bak-$(date +%F-%H%M%S)"
        success "已备份 $file"
    else
        warning "$file 不存在，无需备份"
    fi
}

### ==== 安装单个软件包 ==== ###
install_package() {
    local pkg="$1"
    info "处理软件包 $pkg..."

    if check_command "$pkg"; then
        success "$pkg 已安装，跳过"
        return 0
    fi

    # 验证 OS_ID
    info "当前 OS_ID：$OS_ID"
    if [[ -z "$OS_ID" || "$OS_ID" =~ [[:space:]] || "$OS_ID" =~ \[.*\] ]]; then
        error "无效的发行版 ID：$OS_ID"
    fi

    info "安装 $pkg..."
    case "$OS_ID" in
        debian|ubuntu|linuxmint)
            info "检查网络连接..."
            if ! curl -Is --connect-timeout 5 http://www.google.com >/dev/null; then
                warning "无法连接到网络，检查网络连接"
                return 1
            fi
            if ! apt update -y || ! apt install -y "$pkg"; then
                error "$pkg 安装失败，请检查包源（如 /etc/apt/sources.list）"
            fi
            ;;
        centos|rhel|fedora|rocky|almalinux)
            info "检测包管理器..."
            if command -v dnf >/dev/null 2>&1; then
                dnf -y update && dnf install -y epel-release && dnf install -y "$pkg" || error "$pkg 安装失败"
            elif command -v yum >/dev/null 2>&1; then
                yum -y update && yum install -y epel-release && yum install -y "$pkg" || error "$pkg 安装失败"
            else
                error "${OS_ID} 上未找到 yum 或 dnf"
            fi
            ;;
        arch|manjaro)
            pacman -Syu --noconfirm && pacman -S --noconfirm "$pkg" || error "$pkg 安装失败"
            ;;
        opensuse|suse)
            zypper refresh && zypper install -y "$pkg" || error "$pkg 安装失败"
            ;;
        alpine)
            apk update && apk add "$pkg" || error "$pkg 安装失败"
            ;;
        openwrt)
            opkg update && opkg install "$pkg" || error "$pkg 安装失败"
            ;;
        *)
            error "不支持的发行版：$OS_ID"
            ;;
    esac

    if check_command "$pkg"; then
        success "$pkg 安装成功"
    else
        error "$pkg 安装失败，请检查日志 $LOG_FILE"
    fi
}

### ==== 移除软件包 ==== ###
remove_package() {
    local pkg="$1"
    info "检查 $pkg 是否需要移除..."
    if ! check_command "$pkg"; then
        success "$pkg 未安装，跳过"
        return 0
    fi
    info "移除 $pkg..."
    case "$OS_ID" in
        debian|ubuntu|linuxmint)
            apt remove -y "$pkg" && apt autoremove -y
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                dnf remove -y "$pkg"
            elif command -v yum >/dev/null 2>&1; then
                yum remove -y "$pkg"
            fi
            ;;
        arch|manjaro)
            pacman -Rns --noconfirm "$pkg"
            ;;
        opensuse|suse)
            zypper remove -y "$pkg"
            ;;
        alpine)
            apk del "$pkg"
            ;;
        openwrt)
            opkg remove "$pkg"
            ;;
        *)
            warning "不支持的发行版：$OS_ID，无法移除 $pkg"
            return 1
            ;;
    esac
    if ! check_command "$pkg"; then
        success "$pkg 已移除"
    else
        warning "$pkg 移除失败，请检查日志 $LOG_FILE"
    fi
}

### ==== 恢复备份配置 ==== ###
restore_backup() {
    local file="$1"
    info "检查 $file 备份..."
    local backup
    backup=$(ls -t "${file}.bak-"* 2>/dev/null | head -n 1)
    if [[ -n "$backup" ]]; then
        info "恢复 $file 从 $backup..."
        cp "$backup" "$file"
        success "$file 已恢复"
    else
        warning "未找到 $file 的备份"
    fi
}

### ==== Bash 优化 ==== ###
bash_optimize() {
    info "开始 Bash 优化..."
    local packages=(git curl wget bash-completion)
    for pkg in "${packages[@]}"; do
        install_package "$pkg"
    done

    info "配置当前用户（$USER）的 Bash 环境..."
    bash_config
    info "自动加载 ~/.bashrc 以生效配置..."
    if [[ -f ~/.bashrc ]]; then
        source ~/.bashrc 2>/dev/null || warning "无法立即应用 .bashrc，请手动 source"
        success "已加载 ~/.bashrc"
    else
        warning "~/.bashrc 不存在，跳过自动加载"
    fi
}

### ==== Bash 配置 ==== ###
bash_config() {
    info "配置 Bash 环境..."
    backup_config ~/.bashrc
    cat > ~/.bashrc <<'EOF'
# 确保脚本在 Bash 中运行
if [[ -z "$BASH_VERSION" ]]; then
    echo "错误：此脚本需在 Bash 中运行" >&2
    return 1
fi

# ==== PS1 美化 ====
# 加载 Git 提示脚本（如果存在）
for git_prompt in \
    "/usr/lib/git-core/git-prompt.sh" \
    "/usr/share/git-core/contrib/completion/git-prompt.sh" \
    "/etc/bash_completion.d/git-prompt"; do
    if [[ -f "$git_prompt" ]]; then
        source "$git_prompt"
        break
    fi
done

# 定义 PS1，包含 Git 分支
if declare -f __git_ps1 >/dev/null; then
    GIT_PS1_SHOWDIRTYSTATE=1
    GIT_PS1_SHOWSTASHSTATE=1
    GIT_PS1_SHOWUNTRACKEDFILES=1
    PS1='\[\033[1;32m\]\D{%Y-%m-%d %H:%M} \u@\h:\w$(__git_ps1 " (%s)")#\[\033[0m\]\n\[\033[1;32m\]➤ \[\033[0m\]'
else
    PS1='\[\033[1;32m\]\D{%Y-%m-%d %H:%M} \u@\h:\w#\[\033[0m\]\n\[\033[1;32m\]➤ \[\033[0m\]'
fi

# ==== 历史优化 ====
HISTCONTROL=ignoredups:erasedups
HISTSIZE=10000
HISTFILESIZE=20000
HISTTIMEFORMAT="%F %T "
if type shopt >/dev/null 2>&1; then
    shopt -s histappend
fi
export PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

# ==== 环境变量 ====
export EDITOR=nano

# ==== 常用命令别名 ====
alias ll='ls -l --color=auto'        # 长格式列出文件
alias la='ls -la --color=auto'       # 列出所有文件，包括隐藏文件
alias ls='ls --color=auto'           # 彩色 ls 输出
alias grep='grep --color=auto'       # 彩色 grep 输出
alias df='df -h'                     # 磁盘空间以人类可读格式显示
alias du='du -h'                     # 文件大小以人类可读格式显示
alias cp='cp -i'                     # 复制前确认
alias mv='mv -i'                     # 移动前确认
alias rm='rm -i'                     # 删除前确认
alias free='free -h'                 # 内存使用以人类可读格式显示
alias cls='clear'                    # 清除屏幕
alias ping='ping -c 4'               # ping 默认发送 4 次
alias tailf='tail -f'                # 实时查看文件尾部
alias g='git'                        # 简写 git 命令
alias v='vim'                        # 快速打开 vim
alias t='tree'                       # 显示目录树
alias c='clear'                      # 简写清除屏幕
alias h='history'                    # 查看命令历史
alias p='ps aux'                     # 查看所有进程
alias nt='netstat -tuln'             # 查看监听端口
EOF
    source ~/.bashrc
    success "Bash 配置已写入 & 生效"
}

### ==== 清理配置 ==== ###
clean_config() {
    info "清理用户配置..."
    restore_backup ~/.bashrc
    success "用户配置已清理并还原"
}

### ==== 还原&清理全部 ==== ###
cleanup_all() {
    info "开始还原配置..."
    info "清理当前用户（$USER）的配置..."
    clean_config
}

### ==== 主菜单 ==== ###
main_menu() {
    info "欢迎使用生产环境终端配置工具"
    echo -e "${YELLOW}请选择操作：${NC}"
    echo -e "1) bash 优化"
    echo -e "2) 还原&清理全部"
    read -t 30 -rp "请输入选项 [1-2，默认1]: " choice || choice="1"
    echo
    case "$choice" in
        1)
            bash_optimize
            ;;
        2)
            cleanup_all
            ;;
        *)
            warning "无效选项，默认执行 bash 优化"
            bash_optimize
            ;;
    esac
}

### ==== 配置入口 ==== ###
if [[ "$1" == "--bash-config" ]]; then
    bash_config
elif [[ "$1" == "--clean-config" ]]; then
    clean_config
elif [[ "$1" == "--help" ]]; then
    echo -e "${BLUE}生产环境终端配置工具${NC}"
    echo -e "用法：$0 [选项]"
    echo -e "选项："
    echo -e "  --bash-config       配置 Bash 环境"
    echo -e "  --clean-config      清理用户配置并还原备份"
    echo -e "  --help              显示此帮助信息"
    exit 0
else
    main_menu
fi

echo -e "${GREEN}✅ 操作完成！日志已保存到 $LOG_FILE${NC}"
echo -e "${GREEN}请运行 ${BLUE}source ~/.bashrc${GREEN} 以生效 Bash 配置，或重新打开终端。${NC}"