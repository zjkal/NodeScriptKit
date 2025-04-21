#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: geek_prompt.sh
# 功能: 增强 Shell 提示符显示效果，集成 Git 分支、高亮状态等信息
# 作者: 3az7qmfd <https://www.nodeseek.com/space/14846>
# 创建日期: 2025-04-21

### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"
echo -e "\033[32m[信息] 脚本版本: $SCRIPT_VERSION\033[0m"

### === 退出状态码 === ###
EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_INTERRUPT=130

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
    warn "脚本被中断..."
    exit $EXIT_INTERRUPT
}
trap cleanup SIGINT SIGTERM

### === 主逻辑 === ###
install_geek_prompt() {
    info "[开始] 安装 Geek Prompt..."
    cat > ~/.geek_prompt.sh <<"EOF"
#!/bin/bash

# 定义颜色（增强对比度）
RESET="\[\033[0m\]"
FG_WHITE="\[\033[1;97m\]"   # 用户名@主机
FG_BLUE="\[\033[1;94m\]"    # 当前路径
FG_YELLOW="\[\033[1;93m\]"  # Git 分支
FG_GREEN="\[\033[1;92m\]"   # 提示符
FG_RED="\[\033[1;91m\]"     # 错误提示

# macOS 与 Linux 的时间命令兼容性
if [[ "$OSTYPE" == "darwin"* ]]; then
    DATE_CMD='gdate'
else
    DATE_CMD='date'
fi

# 获取 Git 分支
git_branch() {
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    if [[ -n "$branch" ]]; then
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
            echo " [$FG_RED$branch$RESET]"
        else
            echo " [$FG_YELLOW$branch$RESET]"
        fi
    fi
}

__cmd_timer_start() {
    TIMER_START=$($DATE_CMD +%s)
}

__cmd_timer_end() {
    local TIMER_END=$($DATE_CMD +%s)
    local DIFF=$((TIMER_END - TIMER_START))
    if [[ $DIFF -gt 0 ]]; then
        CMD_TIME="(${FG_YELLOW}$(printf "%02d:%02d" $((DIFF/60)) $((DIFF%60)))$RESET) "
    else
        CMD_TIME=""
    fi
}

__cmd_exit_status() {
    local EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 ]]; then
        EXIT_STATUS="[${FG_RED}✘ $EXIT_CODE${RESET}] "
    else
        EXIT_STATUS=""
    fi
}

__update_prompt() {
    PS1="${EXIT_STATUS}${CMD_TIME}${FG_WHITE}\u@\h ${FG_BLUE}\w$(git_branch) ${FG_GREEN}❯ ${RESET}"
}

export PROMPT_COMMAND='__cmd_exit_status; __cmd_timer_end; __update_prompt; __cmd_timer_start'
EOF

    if ! grep -q "source ~/.geek_prompt.sh" ~/.bashrc; then
        echo "source ~/.geek_prompt.sh" >> ~/.bashrc
        success "已添加到 ~/.bashrc"
    else
        warn "已存在 ~/.bashrc 中，无需重复添加"
    fi

    # 立即生效
    source ~/.geek_prompt.sh
    success "[完成] Geek Bash Prompt 已安装并生效！"
}

# 执行安装
install_geek_prompt
