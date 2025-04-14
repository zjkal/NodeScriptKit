#!/bin/bash

### === 脚本描述 === ###
# 脚本名称: auto_mount_disk.sh
# 功能: 这是一个脚本挂载脚本
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
BLUE='\033[34m';
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

### === 逻辑正式开始 === ###

# System info
sys_id=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2 | tr -d '"')

# Software dependencies
software_list=("parted" "util-linux")


# Install software
install_software() {

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

# Auto-mount disk
auto_mount_disk() {
    clear
    install_software
    info "正在检测可用磁盘..."
    local sys_disk=$(cat /proc/partitions | grep -v name | grep -v ram | awk '{print $4}' | grep -v '^$' | grep -v '[0-9]$' | grep -v 'vda' | grep -v 'xvda' | grep -v 'sda' | grep -e 'vd' -e 'sd' -e 'xvd')
    if [ -z "$sys_disk" ]; then
        danger "此服务器只有一块磁盘，无法挂载"
        return 1
    fi

    lsblk -d -o NAME,SIZE,MODEL | grep -v "NAME" || warn "未检测到可用磁盘"

    read -p "请输入磁盘设备名 (例如 sdb): " disk
    if [ ! -b "/dev/$disk" ]; then
        danger "磁盘 /dev/$disk 不存在"
        return 1
    fi

    if lsblk "/dev/$disk" | grep -q "/"; then
        warn "磁盘 /dev/$disk 已被挂载"
        return 0
    fi

    if fdisk -l "/dev/$disk" 2>/dev/null | grep -q "NTFS\|FAT32"; then
        danger "检测到 Windows 分区，为数据安全，请手动挂载"
        return 1
    fi

    info "选择文件系统格式"
    echo "1. ext4 (默认)"
    echo "2. xfs"
    echo "3. btrfs"
    read -p "请输入选择 (1-3，默认为 ext4): " fs_choice
    case $fs_choice in
        2) 
            filesystem="xfs"
            software_list=("xfsprogs")
            install_software
            ;;
        3) 
            filesystem="btrfs"
            software_list=("btrfs-progs")
            install_software
            ;;
        *) 
            filesystem="ext4"
            ;;
    esac

    read -p "请输入挂载点 (默认为 /mnt/$disk): " mount_point
    mount_point=${mount_point:-/mnt/$disk}
    mkdir -p "$mount_point"

    if mount | grep -q "$mount_point"; then
        danger "挂载点 $mount_point 已被使用"
        return 1
    fi

    info "正在为 /dev/$disk 分区..."
    parted -s "/dev/$disk" mklabel gpt
    parted -s "/dev/$disk" mkpart primary "$filesystem" 0% 100%
    sleep 2

    info "正在格式化 /dev/${disk}1 为 $filesystem..."
    case $filesystem in
        ext4) mkfs.ext4 "/dev/${disk}1" >/dev/null 2>&1 ;;
        xfs) mkfs.xfs "/dev/${disk}1" >/dev/null 2>&1 ;;
        btrfs) mkfs.btrfs "/dev/${disk}1" >/dev/null 2>&1 ;;
    esac
    if [ $? -ne 0 ]; then
        danger "无法格式化 /dev/${disk}1"
        return 1
    fi

    info "正在挂载 /dev/${disk}1 到 $mount_point..."
    mount "/dev/${disk}1" "$mount_point"
    if [ $? -ne 0 ]; then
        danger "无法挂载 /dev/${disk}1"
        return 1
    fi

    disk_uuid=$(blkid -s UUID -o value "/dev/${disk}1")
    if ! grep -q "$disk_uuid" /etc/fstab; then
        echo "UUID=$disk_uuid $mount_point $filesystem defaults 0 2" >> /etc/fstab
        info "已将 /dev/${disk}1 添加到 /etc/fstab"
    fi

    mount -a
    if mount | grep -q "$mount_point"; then
        success "磁盘 /dev/${disk}1 已成功挂载到 $mount_point"
    else
        danger "挂载验证失败"
        return 1
    fi
}

# Main execution
auto_mount_disk