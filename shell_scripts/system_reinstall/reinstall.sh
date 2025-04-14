#!/bin/bash

### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"

### === 权限检查 === ###
[[ $EUID -ne 0 ]] && echo -e "\033[31m[错误] 请以root用户或sudo运行此脚本！\033[0m" && exit 1

### === 工具检查 === ###
check_dependencies() {
  for tool in curl wget; do
    if ! command -v $tool >/dev/null 2>&1; then
      echo -e "\033[31m[错误] 缺少依赖：$tool，请先安装！\033[0m"
      exit 1
    fi
  done
}

### === 颜色与提示函数 === ###
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
BLUE='\033[34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warning() { echo -e "${YELLOW}[提示]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }

### === 变量定义 === ###
SYSTEM=""
VERSION=""
IMAGE_URL=""
SSH_PORT=22
PASSWORD=""
CMD=""
MODE=""

### === 系统选择 === ###
select_system() {
  SYSTEMS=("ubuntu" "debian" "centos" "alpine" "kali" "almalinux" "rocky" "arch" "fedora" "opensuse" "oracle"
            "windows" "dd" "alpine-live" "netboot.xyz")

  info "请选择安装模式或系统："
  select SYSTEM in "${SYSTEMS[@]}"; do
    if [[ -n "$SYSTEM" ]]; then
      success "已选择系统/模式：$SYSTEM"
      break
    else
      warning "无效选择，请重试"
    fi
  done
}

### === 版本选择 === ###
select_version() {
  declare -A VERSIONS
  VERSIONS["ubuntu"]="24.10 24.04 22.04 20.04 18.04 16.04"
  VERSIONS["debian"]="12 11 10 9"
  VERSIONS["centos"]="10 9 8 7"
  VERSIONS["alpine"]="3.21 3.20 3.19 3.18"
  VERSIONS["fedora"]="41 40 39"
  VERSIONS["opensuse"]="tumbleweed 15.6"
  VERSIONS["almalinux"]="9 8"
  VERSIONS["rocky"]="9 8"
  VERSIONS["oracle"]="9 8"

  if [[ -n "${VERSIONS[$SYSTEM]}" ]]; then
    info "请选择版本或手动输入："
    select CHOICE in ${VERSIONS[$SYSTEM]} "手动输入" "跳过"; do
      if [[ "$CHOICE" == "跳过" ]]; then
        VERSION=""
        break
      elif [[ "$CHOICE" == "手动输入" ]]; then
        read -p "请输入版本号: " VERSION
        break
      elif [[ -n "$CHOICE" ]]; then
        VERSION="$CHOICE"
        break
      else
        warning "无效选择，请重试"
      fi
    done
  else
    info "$SYSTEM 无需指定版本"
  fi
}

### === 获取密码 === ###
get_password() {
  warning "请输入密码（留空则使用默认密码）:"
  read -rs PASSWORD
  echo
  if [[ -z "$PASSWORD" ]]; then
    PASSWORD="123@@@"
    success "已使用默认密码：$PASSWORD"
  else
    success "您设置的密码是：$PASSWORD"
  fi
}

### === 获取 SSH 端口 === ###
get_ssh_port() {
  echo -en "${YELLOW}请输入 SSH 端口（默认 22）: ${NC}"
  read SSH_PORT
  SSH_PORT=${SSH_PORT:-22}
  success "使用的 SSH 端口为：$SSH_PORT"
}

### === 获取镜像地址 === ###
get_image_url() {
  if [[ "$SYSTEM" == "dd" ]]; then
    read -p "请输入 DD 镜像地址（支持 http/https/gz/xz/zst/tar 等）: " IMAGE_URL
    [[ -z "$IMAGE_URL" ]] && error "必须输入镜像地址！" && exit 1
  elif [[ "$SYSTEM" == "windows" ]]; then
    read -p "请输入 ISO 镜像名称或 image-name（例如 Windows 11 Pro）: " IMAGE_NAME
    read -p "是否指定 ISO 下载地址？（可留空自动查找）: " ISO_URL
  fi
}

### === 构建安装命令 === ###
build_command() {
  BASE_CMD="bash <(curl -sL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh)"

  case "$SYSTEM" in
    dd)
      CMD="$BASE_CMD dd --img "$IMAGE_URL" --password "$PASSWORD" --ssh-port $SSH_PORT"
      ;;
    alpine-live)
      CMD="$BASE_CMD alpine --password "$PASSWORD" --ssh-port $SSH_PORT --hold=1"
      ;;
    netboot.xyz)
      CMD="$BASE_CMD netboot.xyz"
      ;;
    windows)
      CMD="$BASE_CMD windows --image-name "$IMAGE_NAME""
      [[ -n "$ISO_URL" ]] && CMD="$CMD --iso "$ISO_URL""
      CMD="$CMD --password "$PASSWORD" --ssh-port $SSH_PORT"
      ;;
    *)
      CMD="$BASE_CMD "$SYSTEM""
      [[ -n "$VERSION" ]] && CMD="$CMD "$VERSION""
      CMD="$CMD --password "$PASSWORD" --ssh-port $SSH_PORT"
      ;;
  esac
}

### === 执行确认 === ###
confirm_and_execute() {
  info "即将执行命令："
  echo -e "${BOLD}${CMD}${NC}"
  echo -en "${YELLOW}是否确认执行？执行后将抹除当前系统所有数据！！！(y/n): ${NC}"
  read CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    success "开始执行安装..."
    eval "$CMD"
  else
    warning "已取消安装流程"
    exit 0
  fi
}

### === 主函数入口 === ###
main() {

  check_dependencies

  info "欢迎使用 一键DD/重装脚本 (One-click reinstall OS on VPS)"
  info "Github： https://github.com/bin456789/reinstall"
  info "当前时间：$(date '+%Y-%m-%d %H:%M:%S')"

  select_system

  case "$SYSTEM" in
    dd|getimg|windows)
      get_image_url
      ;;
    netboot.xyz|alpine-live)
      ;;
    *)
      select_version
      ;;
  esac

  get_password
  get_ssh_port
  build_command
  confirm_and_execute
}

main
