#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: crontab_management.sh
# 功能: 这是一个计划任务管理脚本
# 作者: rouxyang <https://www.nodeseek.com/space/29457>
# 创建日期: 2025-04-13

### === 版本信息 === ###
SCRIPT_VERSION="0.0.1" # Updated version
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

# Manage crontab
manage_crontab() {
    clear
    while true; do
        info "定时任务列表"
        crontab -l 2>/dev/null || echo "未找到定时任务"
        echo ""
        info "操作选项"
        echo "------------------------"
        echo "1. 添加定时任务"
        echo "2. 删除定时任务"
        echo "0. 退出"
        echo "------------------------"
        read -p "请输入您的选择: " choice

        case $choice in
            1)
                read -p "请输入要调度的命令: " command
                if [ -z "$command" ]; then
                    danger "命令不能为空"
                    continue
                fi
                echo "------------------------"
                echo "1. 每周任务"
                echo "2. 每日任务"
                echo "3. 每分钟任务"
                read -p "选择调度类型: " schedule_type

                case $schedule_type in
                    1)
                        read -p "选择星期几执行 (0-6，0=星期日): " weekday
                        if [[ ! "$weekday" =~ ^[0-6]$ ]]; then
                            danger "无效的星期值，必须为 0-6"
                            continue
                        fi
                        (crontab -l 2>/dev/null; echo "0 0 * * $weekday $command") | crontab - >/dev/null 2>&1
                        success "已添加每周定时任务"
                        ;;
                    2)
                        read -p "选择每天的执行小时 (0-23): " hour
                        if [[ ! "$hour" =~ ^[0-9]+$ || $hour -lt 0 || $hour -gt 23 ]]; then
                            danger "无效的小时值，必须为 0-23"
                            continue
                        fi
                        (crontab -l 2>/dev/null; echo "0 $hour * * * $command") | crontab - >/dev/null 2>&1
                        success "已添加每日定时任务"
                        ;;
                    3)
                        (crontab -l 2>/dev/null; echo "* * * * * $command") | crontab - >/dev/null 2>&1
                        success "已添加每分钟定时任务"
                        ;;
                    *)
                        danger "无效的调度类型"
                        ;;
                esac
                ;;
            2)
                read -p "请输入要删除的任务关键字: " keyword
                if [ -z "$keyword" ]; then
                    danger "关键字不能为空"
                    continue
                fi
                crontab -l | grep -v "$keyword" | crontab - >/dev/null 2>&1
                success "已删除包含 '$keyword' 的定时任务"
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
manage_crontab