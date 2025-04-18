#!/bin/bash

### === 脚本描述 === ###
# 名称: manage_services.sh
# 功能: 交互式列举、管理、卸载 systemd 服务；优先显示[用户安装]服务再显示[系统]服务，卸载后生成清单
# 作者: rouxyang <https://www.nodeseek.com/space/29457>
# 创建日期: 2025-04-17
# 许可证: MIT

### === 版本信息 === ###
SCRIPT_VERSION="1.0.2"
SCRIPT_NAME="manage_services.sh"
SCRIPT_AUTHOR="[你的名称] <你的联系方式或主页>"

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
success() { printf "${GREEN}%b${NC}\n" "$1"; }
info()    { printf "${CYAN}%b${NC}\n" "$1"; }
danger()  { printf "\n${RED}[错误] %b${NC}\n" "$@"; }
warn()    { printf "${YELLOW}[警告] %b${NC}\n" "$@"; }

### === 日志记录函数 === ###
LOG_FILE="/var/log/${SCRIPT_NAME:-$(basename "${0:-unknown.sh}")}.log"
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" 2>/dev/null
}

### === 权限和依赖检查 === ###
check_systemctl() {
    if ! command -v systemctl &>/dev/null; then
        danger "未检测到 systemctl，此脚本仅适用于 systemd 系统！"
        exit $EXIT_ERROR
    fi
}
check_root() {
    [[ $EUID -ne 0 ]] && danger "请以root用户或sudo运行此脚本!" && exit $EXIT_ERROR
}
check_dependencies() {
    local deps=("awk" "sort")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            danger "缺少必要命令: $cmd"
            exit $EXIT_ERROR
        fi
    done
}

### === 信号捕获 === ###
cleanup() {
    log "INFO" "脚本被中断..."
    warn "[警告] 脚本已退出!"
    exit $EXIT_INTERRUPT
}
trap cleanup SIGINT SIGTERM

### === 生成自查清单函数 === ###
generate_checklist() {
    local svc="$1"
    local checklist="$HOME/${svc}-uninstall-checklist.txt"

    {
        echo "【$svc 残留检查及手工处理建议清单】"
        echo

        # 1. systemd unit 文件及自启设置
        echo "1. systemd unit 文件及自启设置："
        for p in /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system /usr/local/lib/systemd/system; do
            [ -f "$p/${svc}.service" ] && echo "   $p/${svc}.service"
        done
        systemctl_status=$(systemctl is-enabled "$svc" 2>/dev/null)
        echo "   systemctl is-enabled $svc : $systemctl_status"
        systemctl_statustxt=$(systemctl status "$svc" 2>/dev/null | grep -E 'Loaded:|Active:' | sed 's/^/   /')
        echo "$systemctl_statustxt"
        echo

        # 2. 定时任务自启（crontab）
        echo "2. 定时任务自启（crontab）："
        found_cron=0
        for user in $(cut -d: -f1 /etc/passwd); do
            crontab -u "$user" -l 2>/dev/null | grep -i "$svc" && { echo "   用户 $user 的crontab含相关内容"; found_cron=1; }
        done
        grep -i "$svc" /etc/crontab 2>/dev/null && { echo "   /etc/crontab 含相关内容"; found_cron=1; }
        for cronf in /etc/cron.d/*; do
            grep -i "$svc" "$cronf" 2>/dev/null && { echo "   $cronf 含相关内容"; found_cron=1; }
        done
        [ "$found_cron" = "0" ] && echo "   未发现 crontab 相关条目"
        echo

        # 3. rc.local / profile / XDG autostart
        echo "3. rc.local / profile / XDG autostart 相关自启："
        for pf in /etc/rc.local /etc/profile /etc/bashrc /home/*/.bashrc /home/*/.profile /home/*/.bash_profile; do
            grep -i "$svc" "$pf" 2>/dev/null && echo "   $pf 含相关内容"
        done
        for af in ~/.config/autostart/* /etc/xdg/autostart/*; do
            grep -i "$svc" "$af" 2>/dev/null && echo "   $af 含相关内容"
        done
        echo

        # 4. init.d/sysvinit（老系统）
        echo "4. init.d/sysvinit 相关："
        [ -f "/etc/init.d/$svc" ] && echo "   /etc/init.d/$svc"
        for r in /etc/rc*.d/*; do
            grep -i "$svc" "$r" 2>/dev/null && echo "   $r 含相关内容"
        done
        echo

        # 5. 常见配置、数据、日志目录
        echo "5. 相关配置、数据、日志目录（实际存在的项）："
        for p in /etc/${svc}* ~/.config/${svc}* /var/lib/${svc}* /var/log/${svc}* /usr/local/etc/${svc}* /opt/${svc}*; do
            [ -e "$p" ] && echo "   $p"
        done
        echo

        # 6. 服务相关用户和组
        echo "6. 服务相关用户和组："
        grep "$svc" /etc/passwd && echo "   /etc/passwd"
        grep "$svc" /etc/group && echo "   /etc/group"
        echo

        echo "请人工确认以上项目后再手动清理！如有重要数据请提前备份。"
    } > "$checklist"

    success "已在 $checklist 生成 $svc 服务残留建议清单（均为实际查找到的项）。请查阅并按需手动处理。"
    info "部分清单内容如下："
    head -20 "$checklist"
}

### === 服务管理主逻辑 === ###
manage_services() {
    info "正在收集服务列表，请稍候..."

    CUSTOM_UNIT_PATHS=(
        "/etc/systemd/system"
        "/usr/local/lib/systemd/system"
    )
    SYSTEM_UNIT_PATHS=(
        "/lib/systemd/system"
        "/usr/lib/systemd/system"
    )

    services_file=$(mktemp)
    systemctl list-unit-files --type=service | awk '/\.service/ {print $1}' | sort > "$services_file"

    declare -a all_svc
    declare -a all_type
    declare -a all_path
    declare -a all_active
    declare -a all_enabled

    idx=1
    while read -r svc; do
        path="-"
        type="系统"
        for u in "${CUSTOM_UNIT_PATHS[@]}"; do
            if [ -f "$u/$svc" ]; then
                path="$u/$svc"
                type="用户安装"
                break
            fi
        done
        if [ "$type" = "系统" ]; then
            for u in "${SYSTEM_UNIT_PATHS[@]}"; do
                if [ -f "$u/$svc" ]; then
                    path="$u/$svc"
                    break
                fi
            done
        fi
        all_svc[$idx]="$svc"
        all_type[$idx]="$type"
        all_path[$idx]="$path"
        all_active[$idx]="$(systemctl is-active "$svc" 2>/dev/null)"
        all_enabled[$idx]="$(systemctl is-enabled "$svc" 2>/dev/null)"
        idx=$((idx+1))
    done < "$services_file"
    rm -f "$services_file"

    # 展示“用户安装”优先
    declare -A idx_map
    show_idx=1
    echo
    printf "%-3s | %-45s | %-9s | %-8s | %-8s | %-8s\n" "No." "Service Name" "类型" "Active" "Enabled" "UnitPath"
    echo "-----------------------------------------------------------------------------------------------------"

    for i in "${!all_svc[@]}"; do
        if [[ "${all_type[$i]}" == "用户安装" && -n "${all_svc[$i]}" ]]; then
            printf "%-3s | %-45s | %-9s | %-8s | %-8s | %-8s\n" "$show_idx" "${all_svc[$i]}" "${all_type[$i]}" "${all_active[$i]}" "${all_enabled[$i]}" "${all_path[$i]}"
            idx_map[$show_idx]=$i
            show_idx=$((show_idx+1))
        fi
    done
    for i in "${!all_svc[@]}"; do
        if [[ "${all_type[$i]}" == "系统" && -n "${all_svc[$i]}" ]]; then
            printf "%-3s | %-45s | %-9s | %-8s | %-8s | %-8s\n" "$show_idx" "${all_svc[$i]}" "${all_type[$i]}" "${all_active[$i]}" "${all_enabled[$i]}" "${all_path[$i]}"
            idx_map[$show_idx]=$i
            show_idx=$((show_idx+1))
        fi
    done

    total=$((show_idx-1))

    echo ""
    read -p "请输入要操作的服务编号（如 12），多个用空格分隔，留空退出: " -a nums
    if [ "${#nums[@]}" = 0 ]; then
        info "无操作，退出。"
        exit $EXIT_SUCCESS
    fi

    echo ""
    echo "支持的操作:"
    echo "1. 关闭自启 (disable)"
    echo "2. 停止服务 (stop)"
    echo "3. 卸载服务（停止+关闭自启+删除unit文件+刷新，仅限用户安装服务）"
    echo "4. 仅查看状态 (status)"
    read -p "请输入操作编号 [1/2/3/4]: " action

    for n in "${nums[@]}"; do
        if ! [[ $n =~ ^[0-9]+$ ]] || [ "$n" -gt "$total" ] || [ "$n" -lt 1 ]; then
            warn "非法编号: $n 跳过"
            continue
        fi

        i=${idx_map[$n]}
        svc="${all_svc[$i]}"
        type="${all_type[$i]}"
        upath="${all_path[$i]}"

        echo ""
        info "处理服务: $svc [$type] ($upath)"

        case $action in
          1)
            info "-> 关闭自启"
            systemctl disable "$svc"
            log "INFO" "禁用 $svc"
            ;;
          2)
            info "-> 停止服务"
            systemctl stop "$svc"
            log "INFO" "停止 $svc"
            ;;
          3)
            if [[ "$type" == "用户安装" ]]; then
                info "-> 停止服务"
                systemctl stop "$svc"
                info "-> 关闭自启"
                systemctl disable "$svc"
                if [[ -f "$upath" ]]; then
                    read -p "确认要删除unit文件 $upath ? (y/n): " yn
                    [[ "$yn" =~ ^[Yy]$ ]] && rm "$upath" && success "已删除 $upath" || warn "已取消删除"
                    systemctl daemon-reload
                else
                    warn "找不到 unit 文件，可能已被删除"
                fi

                # 插入生成清单和提示
                generate_checklist "$svc"

                success "用户安装服务 $svc 已尝试卸载"
                log "INFO" "用户安装服务 $svc 已卸载"
            else
                warn "系统服务不建议自动卸载！"
            fi
            ;;
          4)
            systemctl status "$svc"
            ;;
          *)
            warn "不支持的操作"
            ;;
        esac
    done

    success "全部操作完成。"
    log "INFO" "全部操作完成"
}

### === 主函数 === ###
main() {
    echo -e "\033[33m[信息] $SCRIPT_NAME ,版本: $SCRIPT_VERSION\033[0m"
    echo -e "\033[33m[作者] $SCRIPT_AUTHOR\033[0m"

    log "INFO" "脚本 $SCRIPT_NAME (版本: $SCRIPT_VERSION) 开始执行"
    check_systemctl
    check_root
    check_dependencies
    manage_services

    exit $EXIT_SUCCESS
}

### === 脚本入口 === ###
main