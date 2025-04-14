#!/usr/bin/env bash

### === 版本信息 === ###
SCRIPT_VERSION="0.0.1"

### === 权限检查 === ###
[[ $EUID -ne 0 ]] && echo -e "\033[31m[错误] 请以root用户或sudo运行此脚本！\033[0m" && exit 1

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

### === 工具检查 === ###
check_dependencies() {
  for tool in curl docker tar; do
    if ! command -v $tool >/dev/null 2>&1; then
      error "缺少依赖：$tool，请先安装！"
      exit 1
    fi
  done
  if ! command -v docker-compose >/dev/null 2>&1; then
    info "安装 docker-compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    [[ $? -ne 0 ]] && error "docker-compose 安装失败！" && exit 1
  fi
}

### === 安装 Docker === ###
install_docker() {
  if command -v docker >/dev/null 2>&1; then
    success "Docker 已安装，版本：$(docker --version)"
    return 0
  fi

  info "正在安装 Docker..."
  if [[ -f "/etc/alpine-release" ]]; then
    apk update
    apk add docker docker-compose
    rc-update add docker default
    service docker start
  else
    curl -fsSL https://get.docker.com | sh
    if [[ $? -ne 0 ]]; then
      error "Docker 安装失败，请检查网络或手动安装！"
      exit 1
    fi
    systemctl start docker
    systemctl enable docker
  fi
  success "Docker 安装完成！"
  log_operation "Installed Docker"
}

### === 查看 Docker 状态 === ###
view_docker_status() {
  clear
  info "Docker 全局状态："
  echo -e "${BOLD}Docker 版本${NC}"
  docker --version
  docker-compose --version 2>/dev/null || echo "docker-compose 未安装"
  echo
  echo -e "${BOLD}镜像列表${NC}"
  docker image ls
  echo
  echo -e "${BOLD}容器列表${NC}"
  docker ps -a
  echo
  echo -e "${BOLD}卷列表${NC}"
  docker volume ls
  echo
  echo -e "${BOLD}网络列表${NC}"
  docker network ls
  echo
  read -p "按回车键返回..."
  log_operation "Viewed Docker status"
}

### === 容器管理菜单 === ###
manage_containers() {
  while true; do
    clear
    info "Docker 容器管理"
    echo -e "${BOLD}当前容器列表${NC}"
    docker ps -a
    echo
    echo "1. 创建新容器"
    echo "2. 启动容器"
    echo "3. 停止容器"
    echo "4. 删除容器"
    echo "5. 重启容器"
    echo "6. 进入容器"
    echo "7. 查看容器日志"
    echo "8. 查看容器网络"
    echo "9. 管理所有容器"
    echo "0. 返回上级菜单"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        read -p "请输入镜像名称（例如 nginx:latest）: " image
        read -p "请输入容器名称（留空自动生成）: " name
        read -p "请输入端口映射（例如 80:80，留空跳过）: " port
        cmd="docker run -d"
        [[ -n "$name" ]] && cmd="$cmd --name $name"
        [[ -n "$port" ]] && cmd="$cmd -p $port"
        cmd="$cmd $image"
        info "即将执行：$cmd"
        read -p "确认执行？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          eval "$cmd" && success "容器创建成功！" || error "容器创建失败！"
          log_operation "Created container: $name from $image"
        else
          warning "已取消操作"
          log_operation "Cancelled container creation"
        fi
        ;;
      2)
        read -p "请输入容器名称或ID: " name
        docker start "$name" && success "容器 $name 已启动！" || error "启动失败！"
        log_operation "Started container: $name"
        ;;
      3)
        read -p "请输入容器名称或ID: " name
        docker stop "$name" && success "容器 $name 已停止！" || error "停止失败！"
        log_operation "Stopped container: $name"
        ;;
      4)
        read -p "请输入容器名称或ID: " name
        read -p "确认删除容器 $name？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          docker rm -f "$name" && success "容器 $name 已删除！" || error "删除失败！"
          log_operation "Deleted container: $name"
        else
          warning "已取消操作"
          log_operation "Cancelled container deletion: $name"
        fi
        ;;
      5)
        read -p "请输入容器名称或ID: " name
        docker restart "$name" && success "容器 $name 已重启！" || error "重启失败！"
        log_operation "Restarted container: $name"
        ;;
      6)
        read -p "请输入容器名称或ID: " name
        docker exec -it "$name" /bin/bash || docker exec -it "$name" /bin/sh || error "无法进入容器！"
        log_operation "Entered container: $name"
        ;;
      7)
        read -p "请输入容器名称或ID: " name
        docker logs "$name" || error "查看日志失败！"
        log_operation "Viewed logs for container: $name"
        read -p "按回车键返回..."
        ;;
      8)
        clear
        info "容器网络信息"
        container_ids=$(docker ps -q)
        if [[ -z "$container_ids" ]]; then
          warning "没有运行中的容器！"
        else
          printf "%-25s %-25s %-25s\n" "容器名称" "网络名称" "IP地址"
          for id in $container_ids; do
            container_info=$(docker inspect --format '{{ .Name }} {{ range $network, $config := .NetworkSettings.Networks }} {{ $network }} {{ $config.IPAddress }} {{ end }}' "$id")
            container_name=$(echo "$container_info" | awk '{print $1}' | sed 's/^\///')
            network_info=$(echo "$container_info" | cut -d' ' -f2-)
            while IFS= read -r line; do
              network_name=$(echo "$line" | awk '{print $1}')
              ip_address=$(echo "$line" | awk '{print $2}')
              printf "%-25s %-25s %-25s\n" "$container_name" "$network_name" "$ip_address"
            done <<< "$network_info"
          done
        fi
        log_operation "Viewed container network info"
        read -p "按回车键返回..."
        ;;
      9)
        clear
        echo "1. 启动所有容器"
        echo "2. 停止所有容器"
        echo "3. 重启所有容器"
        echo "4. 删除所有容器"
        echo "0. 返回"
        read -p "请输入你的选择: " sub_choice
        case $sub_choice in
          1)
            docker start $(docker ps -a -q) && success "所有容器已启动！" || error "启动失败！"
            log_operation "Started all containers"
            ;;
          2)
            docker stop $(docker ps -q) && success "所有容器已停止！" || error "停止失败！"
            log_operation "Stopped all containers"
            ;;
          3)
            docker restart $(docker ps -q) && success "所有容器已重启！" || error "重启失败！"
            log_operation "Restarted all containers"
            ;;
          4)
            read -p "确认删除所有容器？(y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
              docker rm -f $(docker ps -a -q) && success "所有容器已删除！" || error "删除失败！"
              log_operation "Deleted all containers"
            else
              warning "已取消操作"
              log_operation "Cancelled deletion of all containers"
            fi
            ;;
          0)
            continue
            ;;
          *)
            warning "无效选择！"
            ;;
        esac
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
  done
}

### === 镜像管理菜单 === ###
manage_images() {
  while true; do
    clear
    info "Docker 镜像管理"
    echo -e "${BOLD}当前镜像列表${NC}"
    docker image ls
    echo
    echo "1. 拉取新镜像"
    echo "2. 删除镜像"
    echo "3. 删除所有镜像"
    echo "0. 返回上级菜单"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        read -p "请输入镜像名称（例如 nginx:latest）: " image
        docker pull "$image" && success "镜像 $image 拉取成功！" || error "拉取失败！"
        log_operation "Pulled image: $image"
        ;;
      2)
        read -p "请输入镜像名称或ID: " image
        read -p "确认删除镜像 $image？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          docker rmi -f "$image" && success "镜像 $image 已删除！" || error "删除失败！"
          log_operation "Deleted image: $image"
        else
          warning "已取消操作"
          log_operation "Cancelled image deletion: $image"
        fi
        ;;
      3)
        read -p "确认删除所有镜像？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          docker rmi -f $(docker images -q | sort -u) && success "所有镜像已删除！" || error "删除失败！"
          log_operation "Deleted all images"
        else
          warning "已取消操作"
          log_operation "Cancelled deletion of all images"
        fi
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
  done
}

### === 网络管理菜单 === ###
manage_networks() {
  while true; do
    clear
    info "Docker 网络管理"
    echo -e "${BOLD}当前网络列表${NC}"
    docker network ls
    echo
    echo "1. 创建新网络"
    echo "2. 删除网络"
    echo "3. 连接容器到网络"
    echo "4. 断开容器网络"
    echo "0. 返回上级菜单"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        read -p "请输入新网络名称: " network
        docker network create "$network" && success "网络 $network 创建成功！" || error "创建失败！"
        log_operation "Created network: $network"
        ;;
      2)
        read -p "请输入网络名称或ID: " network
        read -p "确认删除网络 $network？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          docker network rm "$network" && success "网络 $network 已删除！" || error "删除失败！"
          log_operation "Deleted network: $network"
        else
          warning "已取消操作"
          log_operation "Cancelled network deletion: $network"
        fi
        ;;
      3)
        read -p "请输入网络名称或ID: " network
        read -p "请输入容器名称或ID: " container
        docker network connect "$network" "$container" && success "容器 $container 已连接到 $network！" || error "连接失败！"
        log_operation "Connected container $container to network $network"
        ;;
      4)
        read -p "请输入网络名称或ID: " network
        read -p "请输入容器名称或ID: " container
        docker network disconnect "$network" "$container" && success "容器 $container 已从 $network 断开！" || error "断开失败！"
        log_operation "Disconnected container $container from network $network"
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
  done
}

### === 卷管理菜单 === ###
manage_volumes() {
  while true; do
    clear
    info "Docker 卷管理"
    echo -e "${BOLD}当前卷列表${NC}"
    docker volume ls
    echo
    echo "1. 创建新卷"
    echo "2. 删除卷"
    echo "0. 返回上级菜单"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        read -p "请输入新卷名称: " volume
        docker volume create "$volume" && success "卷 $volume 创建成功！" || error "创建失败！"
        log_operation "Created volume: $volume"
        ;;
      2)
        read -p "请输入卷名称: " volume
        read -p "确认删除卷 $volume？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          docker volume rm "$volume" && success "卷 $volume 已删除！" || error "删除失败！"
          log_operation "Deleted volume: $volume"
        else
          warning "已取消操作"
          log_operation "Cancelled volume deletion: $volume"
        fi
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
  done
}

### === 查看容器监控（带图形化输出） === ###
draw_bar() {
  local value=$1
  local max=$2
  local label=$3
  local width=50
  local scaled=$((value * width / max))
  local bar=""
  for ((i=0; i<scaled; i++)); do
    bar="${bar}█"
  done
  printf "%-20s |%-50s| %s%%\n" "$label" "$bar" "$value"
}

monitor_containers() {
  while true; do
    clear
    info "Docker 容器监控"
    echo -e "${BOLD}当前容器状态${NC}"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
    echo -e "${BOLD}资源使用情况（ASCII 图表）${NC}"
    if [[ -n "$(docker ps -q)" ]]; then
      echo "容器名称             | 使用率                                              | 百分比"
      echo "--------------------+----------------------------------------------------+--------"
      for container in $(docker ps -q); do
        name=$(docker inspect --format '{{.Name}}' "$container" | sed 's/^\///')
        stats=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemUsage}}" "$container")
        cpu=$(echo "$stats" | awk '{print $1}' | sed 's/%//')
        mem=$(echo "$stats" | awk '{print $2}' | cut -d'/' -f1 | grep -oP '\d+\.?\d*')
        mem_unit=$(echo "$stats" | awk '{print $2}' | cut -d'/' -f1 | grep -oP '[a-zA-Z]+')
        [[ "$mem_unit" == "GiB" ]] && mem=$(echo "$mem * 1024" | bc)
        draw_bar "${cpu%.*}" 100 "CPU: $name"
        draw_bar "${mem%.*}" 2048 "Mem: $name"
      done
    else
      warning "没有运行中的容器！"
    fi
    echo
    echo -e "${BOLD}健康检查${NC}"
    for container in $(docker ps -q); do
      name=$(docker inspect --format '{{.Name}}' "$container" | sed 's/^\///')
      ports=$(docker inspect --format '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}} {{end}}' "$container")
      if [[ $ports =~ 80 || $ports =~ 8080 ]]; then
        ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container")
        if curl -s -I "http://$ip" | grep -q "200 OK"; then
          success "$name: HTTP 服务正常"
        else
          warning "$name: HTTP 服务异常"
        fi
      elif [[ $ports =~ 3306 ]]; then
        if docker exec "$container" mysqladmin ping -uroot -p"${MYSQL_ROOT_PASSWORD:-mysql}" 2>/dev/null | grep -q "alive"; then
          success "$name: MySQL 服务正常"
        else
          warning "$name: MySQL 服务异常"
        fi
      else
        info "$name: 未检测特定服务"
      fi
    done
    echo
    echo "1. 重启异常容器"
    echo "2. 刷新监控"
    echo "0. 返回"
    read -p "请输入你的选择: " choice
    case $choice in
      1)
        read -p "请输入容器名称或ID: " name
        docker restart "$name" && success "容器 $name 已重启！" || error "重启失败！"
        log_operation "Restarted container: $name"
        ;;
      2)
        continue
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
  done
  log_operation "Viewed container monitoring"
}

### === 备份与恢复管理 === ###
manage_backup() {
  while true; do
    clear
    info "备份与恢复管理"
    echo "------------------------"
    echo "1. 备份容器"
    echo "2. 备份应用栈"
    echo "3. 备份所有内容"
    echo "4. 恢复容器"
    echo "5. 恢复应用栈"
    echo "6. 查看备份文件"
    echo "0. 返回"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        backup_container
        ;;
      2)
        backup_stack
        ;;
      3)
        backup_all
        ;;
      4)
        restore_container
        ;;
      5)
        restore_stack
        ;;
      6)
        ls -lh backups 2>/dev/null | while read line; do
          info "备份文件：$line"
        done
        [[ ! -d backups ]] && warning "备份目录为空！"
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
    read -p "按回车键继续..."
  done
}

backup_container() {
  clear
  info "备份容器"
  echo -e "${BOLD}当前容器列表${NC}"
  docker ps -a
  read -p "请输入容器名称或ID: " name
  read -p "请输入备份路径（默认 ./backups/$name-$(date +%Y%m%d%H%M%S).tar.gz）: " backup_path

  if ! docker inspect "$name" >/dev/null 2>&1; then
    error "容器 $name 不存在！"
    return 1
  fi

  backup_path=${backup_path:-./backups/$name-$(date +%Y%m%d%H%M%S).tar.gz}
  mkdir -p "$(dirname "$backup_path")"

  info "正在备份容器 $name..."
  image=$(docker inspect --format '{{.Config.Image}}' "$name")
  docker save "$image" -o "/tmp/$name-image.tar"
  volumes=$(docker inspect --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' "$name")
  volume_dir="/tmp/$name-volumes"
  mkdir -p "$volume_dir"
  for vol in $volumes; do
    src=$(echo "$vol" | cut -d':' -f1)
    dst=$(echo "$vol" | cut -d':' -f2)
    [[ -d "$src" ]] && cp -r "$src" "$volume_dir/$(basename "$dst")"
  done
  tar -czf "$backup_path" -C /tmp "$name-image.tar" "$name-volumes"
  rm -rf "/tmp/$name-image.tar" "/tmp/$name-volumes"
  [[ $? -eq 0 ]] && success "容器 $name 备份完成：$backup_path" || error "备份失败！"
  log_operation "Backed up container: $name to $backup_path"
}

backup_stack() {
  clear
  info "备份应用栈"
  ls -d *-stack 2>/dev/null | while read stack; do
    info "可用栈：${stack%-stack}"
  done
  read -p "请输入栈名称（例如 lamp, lemp）: " stack_name
  read -p "请输入备份路径（默认 ./backups/$stack_name-$(date +%Y%m%d%H%M%S).tar.gz）: " backup_path

  if [[ ! -d "$stack_name-stack" ]]; then
    error "栈 $stack_name 不存在！"
    return 1
  fi

  backup_path=${backup_path:-./backups/$stack_name-$(date +%Y%m%d%H%M%S).tar.gz}
  mkdir -p "$(dirname "$backup_path")"

  info "正在备份栈 $stack_name..."
  tar -czf "$backup_path" "$stack_name-stack"
  [[ $? -eq 0 ]] && success "栈 $stack_name 备份完成：$backup_path" || error "备份失败！"
  log_operation "Backed up stack: $stack_name to $backup_path"
}

backup_all() {
  clear
  info "备份所有内容"
  read -p "请输入备份路径（默认 ./backups/all-$(date +%Y%m%d%H%M%S).tar.gz）: " backup_path

  backup_path=${backup_path:-./backups/all-$(date +%Y%m%d%H%M%S).tar.gz}
  mkdir -p "$(dirname "$backup_path")"

  info "正在备份所有容器和栈..."
  temp_dir="/tmp/docker-backup-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$temp_dir/containers" "$temp_dir/stacks"
  for name in $(docker ps -a -q | sort -u); do
    image=$(docker inspect --format '{{.Config.Image}}' "$name")
    container_name=$(docker inspect --format '{{.Name}}' "$name" | sed 's/^\///')
    docker save "$image" -o "$temp_dir/containers/$container_name-image.tar"
    volumes=$(docker inspect --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' "$name")
    volume_dir="$temp_dir/containers/$container_name-volumes"
    mkdir -p "$volume_dir"
    for vol in $volumes; do
      src=$(echo "$vol" | cut -d':' -f1)
      dst=$(echo "$vol" | cut -d':' -f2)
      [[ -d "$src" ]] && cp -r "$src" "$volume_dir/$(basename "$dst")"
    done
  done
  cp -r *-stack "$temp_dir/stacks" 2>/dev/null
  tar -czf "$backup_path" -C "$temp_dir" .
  rm -rf "$temp_dir"
  [[ $? -eq 0 ]] && success "所有内容备份完成：$backup_path" || error "备份失败！"
  log_operation "Backed up all containers and stacks to $backup_path"
}

restore_container() {
  clear
  info "恢复容器"
  read -p "请输入备份文件路径: " backup_path
  read -p "请输入容器名称（默认从备份提取）: " name

  if [[ ! -f "$backup_path" ]]; then
    error "备份文件 $backup_path 不存在！"
    return 1
  fi

  temp_dir="/tmp/docker-restore-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$temp_dir"
  tar -xzf "$backup_path" -C "$temp_dir"
  image_file=$(find "$temp_dir" -name "*-image.tar")
  volume_dir=$(find "$temp_dir" -name "*-volumes")

  if [[ -z "$image_file" ]]; then
    error "备份文件中缺少镜像文件！"
    rm -rf "$temp_dir"
    return 1
  fi

  if [[ -z "$name" ]]; then
    name=$(basename "$image_file" | sed 's/-image.tar//')
  fi

  info "正在恢复容器 $name..."
  docker load -i "$image_file"
  image=$(docker images --format '{{.Repository}}:{{.Tag}}' | head -n 1)
  if [[ -d "$volume_dir" ]]; then
    for vol in "$volume_dir"/*; do
      vol_name=$(basename "$vol")
      mkdir -p "$(pwd)/$name-data/$vol_name"
      cp -r "$vol"/* "$(pwd)/$name-data/$vol_name"
    done
  fi
  cmd="docker run -d --name $name"
  [[ -d "$(pwd)/$name-data" ]] && cmd="$cmd -v $(pwd)/$name-data:/data"
  cmd="$cmd $image"
  eval "$cmd" || { error "容器恢复失败！"; rm -rf "$temp_dir"; return 1; }
  rm -rf "$temp_dir"
  success "容器 $name 恢复完成！"
  echo "进入容器：docker exec -it $name bash"
  log_operation "Restored container: $name from $backup_path"
}

restore_stack() {
  clear
  info "恢复应用栈"
  read -p "请输入备份文件路径: " backup_path
  read -p "请输入栈名称（默认从备份提取）: " stack_name

  if [[ ! -f "$backup_path" ]]; then
    error "备份文件 $backup_path 不存在！"
    return 1
  fi

  temp_dir="/tmp/docker-restore-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$temp_dir"
  tar -xzf "$backup_path" -C "$temp_dir"

  if [[ -z "$stack_name" ]]; then
    stack_name=$(ls "$temp_dir" | grep -oP '.*(?=-stack)' | head -n 1)
  fi

  if [[ -z "$stack_name" ]]; then
    error "无法提取栈名称！"
    rm -rf "$temp_dir"
    return 1
  fi

  info "正在恢复栈 $stack_name..."
  mv "$temp_dir/$stack_name-stack" .
  docker-compose -f "$stack_name-stack/docker-compose.yml" up -d || { error "栈恢复失败！"; rm -rf "$temp_dir"; return 1; }
  rm -rf "$temp_dir"
  success "栈 $stack_name 恢复完成！"
  echo "查看栈状态：docker-compose -f $stack_name-stack/docker-compose.yml ps"
  log_operation "Restored stack: $stack_name from $backup_path"
}

### === 配置文件管理 === ###
manage_config() {
  local config_file=~/.docker_manager.conf
  while true; do
    clear
    info "配置文件管理"
    echo "------------------------"
    echo "1. 查看当前配置"
    echo "2. 编辑配置"
    echo "3. 重置配置"
    echo "0. 返回"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        if [[ -f "$config_file" ]]; then
          cat "$config_file"
        else
          warning "配置文件不存在！"
        fi
        ;;
      2)
        nano "$config_file" || vi "$config_file" || error "无法编辑配置文件！"
        success "配置文件已保存！"
        log_operation "Edited configuration file: $config_file"
        ;;
      3)
        read -p "确认重置配置文件？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          rm -f "$config_file"
          success "配置文件已重置！"
          log_operation "Reset configuration file: $config_file"
        else
          warning "已取消操作"
          log_operation "Cancelled configuration reset"
        fi
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
    read -p "按回车键继续..."
  done
}

### === 日志管理 === ###
manage_logs() {
  while true; do
    clear
    info "Docker 日志管理"
    echo "------------------------"
    echo "1. 查看容器日志"
    echo "2. 导出容器日志"
    echo "3. 查看操作日志"
    echo "4. 分析容器日志（错误/警告）"
    echo "0. 返回"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        read -p "请输入容器名称或ID: " name
        docker logs "$name" || error "查看日志失败！"
        log_operation "Viewed logs for container: $name"
        ;;
      2)
        read -p "请输入容器名称或ID: " name
        read -p "请输入导出路径（默认 ./$name.log）: " log_path
        log_path=${log_path:-./$name.log}
        docker logs "$name" > "$log_path" 2>&1 && success "日志已导出到 $log_path" || error "导出失败！"
        log_operation "Exported logs for container: $name to $log_path"
        ;;
      3)
        if [[ -f "/var/log/docker_manager.log" ]]; then
          cat /var/log/docker_manager.log
        else
          warning "操作日志不存在！"
        fi
        log_operation "Viewed operation logs"
        ;;
      4)
        read -p "请输入容器名称或ID: " name
        if docker logs "$name" 2>&1 | grep -i -E "error|warning|fatal|exception" > /tmp/docker_log_analysis; then
          info "发现以下错误/警告："
          cat /tmp/docker_log_analysis
          rm -f /tmp/docker_log_analysis
        else
          success "未发现错误或警告！"
        fi
        log_operation "Analyzed logs for container: $name"
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
    read -p "按回车键继续..."
  done
}

### === 记录操作日志 === ###
log_operation() {
  local message=$1
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $message" >> /var/log/docker_manager.log
}

### === 批量操作容器 === ###
manage_batch() {
  while true; do
    clear
    info "批量操作容器"
    echo -e "${BOLD}当前容器列表${NC}"
    docker ps -a
    echo
    echo "1. 启动多个容器"
    echo "2. 停止多个容器"
    echo "3. 删除多个容器"
    echo "0. 返回"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        read -p "请输入容器名称或ID（空格分隔）: " names
        docker start $names && success "容器已启动！" || error "启动失败！"
        log_operation "Started containers: $names"
        ;;
      2)
        read -p "请输入容器名称或ID（空格分隔）: " names
        docker stop $names && success "容器已停止！" || error "停止失败！"
        log_operation "Stopped containers: $names"
        ;;
      3)
        read -p "请输入容器名称或ID（空格分隔）: " names
        read -p "确认删除这些容器？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          docker rm -f $names && success "容器已删除！" || error "删除失败！"
          log_operation "Deleted containers: $names"
        else
          warning "已取消操作"
          log_operation "Cancelled container deletion: $names"
        fi
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
    read -p "按回车键继续..."
  done
}

### === 部署应用栈 === ###
deploy_stack() {
  while true; do
    clear
    info "部署应用栈"
    echo "------------------------"
    echo "1. LAMP 栈（Linux + Apache + MySQL + PHP）"
    echo "2. LEMP 栈（Linux + Nginx + MySQL + PHP）"
    echo "3. 查看已部署栈"
    echo "4. 停止栈"
    echo "5. 删除栈"
    echo "0. 返回"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        deploy_lamp_stack
        ;;
      2)
        deploy_lemp_stack
        ;;
      3)
        ls -d *-stack 2>/dev/null | while read stack; do
          info "栈：${stack%-stack}"
          docker-compose -f "$stack/docker-compose.yml" ps
        done
        [[ -z "$(ls -d *-stack 2>/dev/null)" ]] && warning "没有已部署的栈！"
        log_operation "Viewed deployed stacks"
        ;;
      4)
        read -p "请输入栈名称（例如 lamp, lemp）: " stack_name
        if [[ -d "$stack_name-stack" ]]; then
          docker-compose -f "$stack_name-stack/docker-compose.yml" stop && success "栈 $stack_name 已停止！" || error "停止失败！"
          log_operation "Stopped stack: $stack_name"
        else
          error "栈 $stack_name 不存在！"
        fi
        ;;
      5)
        read -p "请输入栈名称（例如 lamp, lemp）: " stack_name
        if [[ -d "$stack_name-stack" ]]; then
          read -p "确认删除栈 $stack_name？(y/n): " confirm
          if [[ "$confirm" =~ ^[Yy]$ ]]; then
            docker-compose -f "$stack_name-stack/docker-compose.yml" down -v
            rm -rf "$stack_name-stack" && success "栈 $stack_name 已删除！" || error "删除失败！"
            log_operation "Deleted stack: $stack_name"
          else
            warning "已取消操作"
            log_operation "Cancelled stack deletion: $stack_name"
          fi
        else
          error "栈 $stack_name 不存在！"
        fi
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
    read -p "按回车键继续..."
  done
}

deploy_lamp_stack() {
  clear
  info "部署 LAMP 栈"
  local mysql_versions=("8.0" "8.1" "5.7")
  local php_versions=("8.2" "8.1" "7.4")
  local mysql_version=$(select_version "MySQL" "${mysql_versions[@]}")
  local php_version=$(select_version "PHP" "${php_versions[@]}")
  read -p "请输入栈名称（默认 lamp）: " stack_name
  read -p "请输入 Apache 端口映射（默认 8080:80）: " apache_port
  read -p "请输入 MySQL 根用户密码（默认 mysql）: " mysql_password
  read -p "请输入默认数据库名称（默认 app）: " db_name

  stack_name=${stack_name:-lamp}
  apache_port=${apache_port:-8080:80}
  mysql_password=${mysql_password:-mysql}
  db_name=${db_name:-app}

  mkdir -p "$stack_name-stack"
  cat > "$stack_name-stack/docker-compose.yml" <<EOF
version: '3.8'
services:
  mysql:
    image: mysql:$mysql_version
    container_name: ${stack_name}-mysql
    environment:
      MYSQL_ROOT_PASSWORD: $mysql_password
      MYSQL_DATABASE: $db_name
    volumes:
      - ./mysql-data:/var/lib/mysql
    restart: always
  php:
    image: php:${php_version}-apache
    container_name: ${stack_name}-php
    ports:
      - $apache_port
    volumes:
      - ./html:/var/www/html
    depends_on:
      - mysql
    restart: always
EOF

  info "即将部署 LAMP 栈..."
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p "$stack_name-stack/mysql-data" "$stack_name-stack/html"
    echo "<?php phpinfo();" > "$stack_name-stack/html/index.php"
    docker-compose -f "$stack_name-stack/docker-compose.yml" up -d || { error "部署失败！"; rm -rf "$stack_name-stack"; return 1; }
    success "LAMP 栈部署完成！"
    echo "访问地址：http://$(hostname -i):${apache_port%%:*}"
    echo "MySQL 数据目录：$(pwd)/$stack_name-stack/mysql-data"
    echo "网站根目录：$(pwd)/$stack_name-stack/html"
    echo "进入 PHP 容器：docker exec -it ${stack_name}-php bash"
    echo "进入 MySQL 容器：docker exec -it ${stack_name}-mysql mysql -uroot -p"
    log_operation "Deployed LAMP stack: $stack_name"
  else
    warning "已取消操作"
    rm -rf "$stack_name-stack"
    log_operation "Cancelled LAMP stack deployment"
  fi
}

deploy_lemp_stack() {
  clear
  info "部署 LEMP 栈"
  local nginx_versions=("1.26" "1.25" "1.24")
  local mysql_versions=("8.0" "8.1" "5.7")
  local php_versions=("8.2" "8.1" "7.4")
  local nginx_version=$(select_version "Nginx" "${nginx_versions[@]}")
  local mysql_version=$(select_version "MySQL" "${mysql_versions[@]}")
  local php_version=$(select_version "PHP" "${php_versions[@]}")
  read -p "请输入栈名称（默认 lemp）: " stack_name
  read -p "请输入 Nginx 端口映射（默认 8080:80）: " nginx_port
  read -p "请输入 MySQL 根用户密码（默认 mysql）: " mysql_password
  read -p "请输入默认数据库名称（默认 app）: " db_name

  stack_name=${stack_name:-lemp}
  nginx_port=${nginx_port:-8080:80}
  mysql_password=${mysql_password:-mysql}
  db_name=${db_name:-app}

  mkdir -p "$stack_name-stack"
  cat > "$stack_name-stack/docker-compose.yml" <<EOF
version: '3.8'
services:
  mysql:
    image: mysql:$mysql_version
    container_name: ${stack_name}-mysql
    environment:
      MYSQL_ROOT_PASSWORD: $mysql_password
      MYSQL_DATABASE: $db_name
    volumes:
      - ./mysql-data:/var/lib/mysql
    restart: always
  php:
    image: php:${php_version}-fpm
    container_name: ${stack_name}-php
    volumes:
      - ./html:/var/www/html
    depends_on:
      - mysql
    restart: always
  nginx:
    image: nginx:$nginx_version
    container_name: ${stack_name}-nginx
    ports:
      - $nginx_port
    volumes:
      - ./html:/var/www/html
      - ./nginx-conf:/etc/nginx/conf.d
    depends_on:
      - php
    restart: always
EOF

  info "即将部署 LEMP 栈..."
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p "$stack_name-stack/mysql-data" "$stack_name-stack/html" "$stack_name-stack/nginx-conf"
    echo "<?php phpinfo();" > "$stack_name-stack/html/index.php"
    cat > "$stack_name-stack/nginx-conf/default.conf" <<EOF
server {
    listen 80;
    server_name localhost;
    root /var/www/html;
    index index.php index.html;
    location ~ \.php$ {
        fastcgi_pass ${stack_name}-php:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
    docker-compose -f "$stack_name-stack/docker-compose.yml" up -d || { error "部署失败！"; rm -rf "$stack_name-stack"; return 1; }
    success "LEMP 栈部署完成！"
    echo "访问地址：http://$(hostname -i):${nginx_port%%:*}"
    echo "MySQL 数据目录：$(pwd)/$stack_name-stack/mysql-data"
    echo "网站根目录：$(pwd)/$stack_name-stack/html"
    echo "进入 Nginx 容器：docker exec -it ${stack_name}-nginx bash"
    echo "进入 PHP 容器：docker exec -it ${stack_name}-php bash"
    echo "进入 MySQL 容器：docker exec -it ${stack_name}-mysql mysql -uroot -p"
    log_operation "Deployed LEMP stack: $stack_name"
  else
    warning "已取消操作"
    rm -rf "$stack_name-stack"
    log_operation "Cancelled LEMP stack deployment"
  fi
}

### === 一键部署应用 === ###
deploy_app() {
  while true; do
    clear
    info "一键部署常用应用"
    echo "------------------------"
    echo "基础软件"
    echo "  1. Nginx 服务器"
    echo "  2. Caddy 服务器"
    echo "  3. Apache 服务器"
    echo "数据库"
    echo "  4. MySQL 数据库"
    echo "  5. PostgreSQL 数据库"
    echo "  6. MongoDB 数据库"
    echo "  7. Redis 缓存"
    echo "开发环境"
    echo "  8. Python 环境"
    echo "  9. Node.js 环境"
    echo "  10. PHP 环境"
    echo "应用"
    echo "  11. WordPress 网站"
    echo "------------------------"
    echo "0. 返回上级菜单"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        deploy_nginx
        ;;
      2)
        deploy_caddy
        ;;
      3)
        deploy_apache
        ;;
      4)
        deploy_mysql
        ;;
      5)
        deploy_postgres
        ;;
      6)
        deploy_mongodb
        ;;
      7)
        deploy_redis
        ;;
      8)
        deploy_python
        ;;
      9)
        deploy_nodejs
        ;;
      10)
        deploy_php
        ;;
      11)
        deploy_wordpress
        ;;
      0)
        break
        ;;
      *)
        warning "无效选择！"
        ;;
    esac
    read -p "按回车键继续..."
  done
}

### === 选择版本通用函数 === ###
select_version() {
  local software=$1
  shift
  local versions=("$@")
  local version=""

  info "请选择 $software 版本（默认 latest）："
  select choice in "${versions[@]}" "手动输入" "使用 latest"; do
    if [[ "$choice" == "使用 latest" ]]; then
      version="latest"
      break
    elif [[ "$choice" == "手动输入" ]]; then
      read -p "请输入版本号（例如 1.25）: " version
      [[ -z "$version" ]] && version="latest"
      break
    elif [[ -n "$choice" ]]; then
      version="$choice"
      break
    else
      warning "无效选择，请重试"
    fi
  done
  echo "$version"
}

### === 生成配置文件模板 === ###
generate_config_template() {
  local software=$1
  local config_dir=$2
  case $software in
    nginx)
      cat > "$config_dir/nginx.conf" <<EOF
user  nginx;
worker_processes  auto;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    keepalive_timeout  65;
    server {
        listen       80;
        server_name  localhost;
        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /usr/share/nginx/html;
        }
    }
}
EOF
      success "已生成 Nginx 默认配置文件：$config_dir/nginx.conf"
      ;;
    caddy)
      cat > "$config_dir/Caddyfile" <<EOF
:80 {
    root * /srv
    file_server
}
EOF
      success "已生成 Caddy 默认配置文件：$config_dir/Caddyfile"
      ;;
    php)
      cat > "$config_dir/php.ini" <<EOF
[PHP]
engine = On
short_open_tag = Off
precision = 14
output_buffering = 4096
zlib.output_compression = Off
implicit_flush = Off
serialize_precision = -1
disable_functions =
disable_classes =
expose_php = On
max_execution_time = 30
max_input_time = 60
memory_limit = 128M
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 1024
ignore_repeated_errors = Off
report_memleaks = On
html_errors = On
default_mimetype = "text/html"
default_charset = "UTF-8"
file_uploads = On
upload_max_filesize = 2M
max_file_uploads = 20
allow_url_fopen = On
allow_url_include = Off
default_socket_timeout = 60
EOF
      success "已生成 PHP 默认配置文件：$config_dir/php.ini"
      ;;
    *)
      warning "暂不支持 $software 的配置文件模板"
      return 1
      ;;
  esac
}

deploy_nginx() {
  clear
  info "部署 Nginx 服务器"
  local config_file=~/.docker_manager.conf
  local versions=("1.26" "1.25" "1.24" "1.23")
  local version=$(select_version "Nginx" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：NGINX_PORT=${NGINX_PORT:-80:80}, NGINX_NAME=${NGINX_NAME:-nginx-server}"
  fi
  read -p "请输入容器名称（默认 ${NGINX_NAME:-nginx-server}）: " name
  read -p "请输入端口映射（默认 ${NGINX_PORT:-80:80}）: " port
  read -p "请输入配置文件目录（默认 /etc/nginx）: " conf_dir
  read -p "请输入网站根目录（默认 /usr/share/nginx/html）: " html_dir
  read -p "是否创建默认 index.html？(y/n): " create_index
  read -p "是否生成默认 Nginx 配置文件？(y/n): " create_config
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${NGINX_NAME:-nginx-server}}
  port=${port:-${NGINX_PORT:-80:80}}
  conf_dir=${conf_dir:-/etc/nginx}
  html_dir=${html_dir:-/usr/share/nginx/html}

  cmd="docker run -d --name $name -p $port -v $(pwd)/nginx-conf:$conf_dir -v $(pwd)/nginx-html:$html_dir nginx:$version"
  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p nginx-conf nginx-html
    if [[ "$create_index" =~ ^[Yy]$ ]]; then
      echo "<h1>Welcome to Nginx!</h1>" > nginx-html/index.html
    fi
    if [[ "$create_config" =~ ^[Yy]$ ]]; then
      generate_config_template "nginx" "$(pwd)/nginx-conf"
      read -p "是否编辑配置文件？(y/n): " edit_config
      [[ "$edit_config" =~ ^[Yy]$ ]] && nano "$(pwd)/nginx-conf/nginx.conf"
    fi
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy Nginx: $name"; return 1; }
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "NGINX_NAME=$name" >> "$config_file"
      echo "NGINX_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "Nginx 服务器部署完成！"
    echo "版本：$version"
    echo "访问地址：http://$(hostname -i):${port%%:*}"
    echo "配置文件目录：$(pwd)/nginx-conf"
    echo "网站根目录：$(pwd)/nginx-html"
    echo "进入容器：docker exec -it $name bash"
    log_operation "Deployed Nginx container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled Nginx deployment"
  fi
}

deploy_caddy() {
  clear
  info "部署 Caddy 服务器"
  local config_file=~/.docker_manager.conf
  local versions=("2.8" "2.7" "2.6")
  local version=$(select_version "Caddy" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：CADDY_PORT=${CADDY_PORT:-80:80}, CADDY_NAME=${CADDY_NAME:-caddy-server}"
  fi
  read -p "请输入容器名称（默认 ${CADDY_NAME:-caddy-server}）: " name
  read -p "请输入端口映射（默认 ${CADDY_PORT:-80:80}）: " port
  read -p "请输入网站根目录（默认 /srv）: " html_dir
  read -p "是否创建默认 index.html？(y/n): " create_index
  read -p "是否生成默认 Caddy 配置文件？(y/n): " create_config
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${CADDY_NAME:-caddy-server}}
  port=${port:-${CADDY_PORT:-80:80}}
  html_dir=${html_dir:-/srv}

  cmd="docker run -d --name $name -p $port -v $(pwd)/caddy-data:/data -v $(pwd)/caddy-config:/config -v $(pwd)/caddy-html:$html_dir caddy:$version"
  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p caddy-data caddy-config caddy-html
    if [[ "$create_index" =~ ^[Yy]$ ]]; then
      echo "<h1>Welcome to Caddy!</h1>" > caddy-html/index.html
    fi
    if [[ "$create_config" =~ ^[Yy]$ ]]; then
      generate_config_template "caddy" "$(pwd)/caddy-config"
      read -p "是否编辑配置文件？(y/n): " edit_config
      [[ "$edit_config" =~ ^[Yy]$ ]] && nano "$(pwd)/caddy-config/Caddyfile"
    fi
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy Caddy: $name"; return 1; }
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "CADDY_NAME=$name" >> "$config_file"
      echo "CADDY_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "Caddy 服务器部署完成！"
    echo "版本：$version"
    echo "访问地址：http://$(hostname -i):${port%%:*}"
    echo "数据目录：$(pwd)/caddy-data"
    echo "配置文件目录：$(pwd)/caddy-config"
    echo "网站根目录：$(pwd)/caddy-html"
    echo "进入容器：docker exec -it $name sh"
    log_operation "Deployed Caddy container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled Caddy deployment"
  fi
}

deploy_apache() {
  clear
  info "部署 Apache 服务器"
  local config_file=~/.docker_manager.conf
  local versions=("2.4" "2.4.57" "2.4.56")
  local version=$(select_version "Apache" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：APACHE_PORT=${APACHE_PORT:-80:80}, APACHE_NAME=${APACHE_NAME:-apache-server}"
  fi
  read -p "请输入容器名称（默认 ${APACHE_NAME:-apache-server}）: " name
  read -p "请输入端口映射（默认 ${APACHE_PORT:-80:80}）: " port
  read -p "请输入网站根目录（默认 /var/www/html）: " html_dir
  read -p "是否创建默认 index.html？(y/n): " create_index
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${APACHE_NAME:-apache-server}}
  port=${port:-${APACHE_PORT:-80:80}}
  html_dir=${html_dir:-/var/www/html}

  cmd="docker run -d --name $name -p $port -v $(pwd)/apache-html:$html_dir httpd:$version"
  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p apache-html
    if [[ "$create_index" =~ ^[Yy]$ ]]; then
      echo "<h1>Welcome to Apache!</h1>" > apache-html/index.html
    fi
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy Apache: $name"; return 1; }
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "APACHE_NAME=$name" >> "$config_file"
      echo "APACHE_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "Apache 服务器部署完成！"
    echo "版本：$version"
    echo "访问地址：http://$(hostname -i):${port%%:*}"
    echo "网站根目录：$(pwd)/apache-html"
    echo "进入容器：docker exec -it $name bash"
    log_operation "Deployed Apache container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled Apache deployment"
  fi
}

deploy_mysql() {
  clear
  info "部署 MySQL 数据库"
  local config_file=~/.docker_manager.conf
  local versions=("8.0" "8.1" "5.7")
  local version=$(select_version "MySQL" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：MYSQL_PORT=${MYSQL_PORT:-3306:3306}, MYSQL_NAME=${MYSQL_NAME:-mysql-db}"
  fi
  read -p "请输入容器名称（默认 ${MYSQL_NAME:-mysql-db}）: " name
  read -p "请输入端口映射（默认 ${MYSQL_PORT:-3306:3306}）: " port
  read -p "请输入根用户密码（默认 mysql）: " password
  read -p "是否创建默认数据库？(y/n): " create_db
  if [[ "$create_db" =~ ^[Yy]$ ]]; then
    read -p "请输入默认数据库名称（默认 myapp）: " db_name
  fi
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${MYSQL_NAME:-mysql-db}}
  port=${port:-${MYSQL_PORT:-3306:3306}}
  password=${password:-mysql}
  db_name=${db_name:-myapp}

  cmd="docker run -d --name $name -p $port -e MYSQL_ROOT_PASSWORD=$password"
  [[ "$create_db" =~ ^[Yy]$ ]] && cmd="$cmd -e MYSQL_DATABASE=$db_name"
  cmd="$cmd -v $(pwd)/mysql-data:/var/lib/mysql mysql:$version"

  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p mysql-data
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy MySQL: $name"; return 1; }
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "MYSQL_NAME=$name" >> "$config_file"
      echo "MYSQL_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "MySQL 数据库部署完成！"
    echo "版本：$version"
    echo "连接信息："
    echo "  主机：$(hostname -i)"
    echo "  端口：${port%%:*}"
    echo "  用户：root"
    echo "  密码：$password"
    [[ "$create_db" =~ ^[Yy]$ ]] && echo "  数据库：$db_name"
    echo "  数据目录：$(pwd)/mysql-data"
    echo "进入容器：docker exec -it $name mysql -uroot -p"
    log_operation "Deployed MySQL container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled MySQL deployment"
  fi
}

deploy_postgres() {
  clear
  info "部署 PostgreSQL 数据库"
  local config_file=~/.docker_manager.conf
  local versions=("16" "15" "14")
  local version=$(select_version "PostgreSQL" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：POSTGRES_PORT=${POSTGRES_PORT:-5432:5432}, POSTGRES_NAME=${POSTGRES_NAME:-postgres-db}"
  fi
  read -p "请输入容器名称（默认 ${POSTGRES_NAME:-postgres-db}）: " name
  read -p "请输入端口映射（默认 ${POSTGRES_PORT:-5432:5432}）: " port
  read -p "请输入数据库密码（默认 postgres）: " password
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${POSTGRES_NAME:-postgres-db}}
  port=${port:-${POSTGRES_PORT:-5432:5432}}
  password=${password:-postgres}

  cmd="docker run -d --name $name -p $port -e POSTGRES_PASSWORD=$password -v $(pwd)/postgres-data:/var/lib/postgresql/data postgres:$version"
  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p postgres-data
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy PostgreSQL: $name"; return 1; }
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "POSTGRES_NAME=$name" >> "$config_file"
      echo "POSTGRES_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "PostgreSQL 数据库部署完成！"
    echo "版本：$version"
    echo "连接信息："
    echo "  主机：$(hostname -i)"
    echo "  端口：${port%%:*}"
    echo "  用户：postgres"
    echo "  密码：$password"
    echo "  数据目录：$(pwd)/postgres-data"
    echo "进入容器：docker exec -it $name psql -U postgres"
    log_operation "Deployed PostgreSQL container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled PostgreSQL deployment"
  fi
}

deploy_mongodb() {
  clear
  info "部署 MongoDB 数据库"
  local config_file=~/.docker_manager.conf
  local versions=("7" "6" "5")
  local version=$(select_version "MongoDB" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：MONGODB_PORT=${MONGODB_PORT:-27017:27017}, MONGODB_NAME=${MONGODB_NAME:-mongodb-db}"
  fi
  read -p "请输入容器名称（默认 ${MONGODB_NAME:-mongodb-db}）: " name
  read -p "请输入端口映射（默认 ${MONGODB_PORT:-27017:27017}）: " port
  read -p "请输入管理员用户名（默认 admin）: " username
  read -p "请输入管理员密码（默认 mongodb）: " password
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${MONGODB_NAME:-mongodb-db}}
  port=${port:-${MONGODB_PORT:-27017:27017}}
  username=${username:-admin}
  password=${password:-mongodb}

  cmd="docker run -d --name $name -p $port -e MONGO_INITDB_ROOT_USERNAME=$username -e MONGO_INITDB_ROOT_PASSWORD=$password -v $(pwd)/mongodb-data:/data/db mongo:$version"
  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p mongodb-data
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy MongoDB: $name"; return 1; }
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "MONGODB_NAME=$name" >> "$config_file"
      echo "MONGODB_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "MongoDB 数据库部署完成！"
    echo "版本：$version"
    echo "连接信息："
    echo "  主机：$(hostname -i)"
    echo "  端口：${port%%:*}"
    echo "  用户：$username"
    echo "  密码：$password"
    echo "  数据目录：$(pwd)/mongodb-data"
    echo "进入容器：docker exec -it $name mongosh -u $username -p $password"
    log_operation "Deployed MongoDB container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled MongoDB deployment"
  fi
}

deploy_redis() {
  clear
  info "部署 Redis 缓存"
  local config_file=~/.docker_manager.conf
  local versions=("7.2" "7.0" "6.2")
  local version=$(select_version "Redis" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：REDIS_PORT=${REDIS_PORT:-6379:6379}, REDIS_NAME=${REDIS_NAME:-redis-cache}"
  fi
  read -p "请输入容器名称（默认 ${REDIS_NAME:-redis-cache}）: " name
  read -p "请输入端口映射（默认 ${REDIS_PORT:-6379:6379}）: " port
  read -p "是否启用持久化？(y/n): " enable_persist
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${REDIS_NAME:-redis-cache}}
  port=${port:-${REDIS_PORT:-6379:6379}}

  cmd="docker run -d --name $name -p $port"
  if [[ "$enable_persist" =~ ^[Yy]$ ]]; then
    cmd="$cmd -v $(pwd)/redis-data:/data"
  fi
  cmd="$cmd redis:$version"

  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    [[ "$enable_persist" =~ ^[Yy]$ ]] && mkdir -p redis-data
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy Redis: $name"; return 1; }
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "REDIS_NAME=$name" >> "$config_file"
      echo "REDIS_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "Redis 缓存部署完成！"
    echo "版本：$version"
    echo "连接信息："
    echo "  主机：$(hostname -i)"
    echo "  端口：${port%%:*}"
    [[ "$enable_persist" =~ ^[Yy]$ ]] && echo "  数据目录：$(pwd)/redis-data"
    echo "进入容器：docker exec -it $name redis-cli"
    log_operation "Deployed Redis container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled Redis deployment"
  fi
}

deploy_python() {
  clear
  info "部署 Python 开发环境"
  local config_file=~/.docker_manager.conf
  local versions=("3.11" "3.10" "3.9")
  local version=$(select_version "Python" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：PYTHON_PORT=${PYTHON_PORT:-8000:8000}, PYTHON_NAME=${PYTHON_NAME:-python-app}"
  fi
  read -p "请输入容器名称（默认 ${PYTHON_NAME:-python-app}）: " name
  read -p "请输入端口映射（默认 ${PYTHON_PORT:-8000:8000}）: " port
  read -p "请输入工作目录（默认 /app）: " workdir
  read -p "是否安装常见库（pip install flask django requests）？(y/n): " install_libs
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${PYTHON_NAME:-python-app}}
  port=${port:-${PYTHON_PORT:-8000:8000}}
  workdir=${workdir:-/app}

  cmd="docker run -d --name $name -p $port -v $(pwd)/python-app:/$workdir -w /$workdir python:$version"
  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p python-app
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy Python: $name"; return 1; }
    if [[ "$install_libs" =~ ^[Yy]$ ]]; then
      docker exec "$name" pip install flask django requests || error "库安装失败！"
    fi
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "PYTHON_NAME=$name" >> "$config_file"
      echo "PYTHON_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "Python 环境部署完成！"
    echo "版本：$version"
    echo "访问地址：http://$(hostname -i):${port%%:*}"
    echo "工作目录：$(pwd)/python-app"
    echo "进入容器：docker exec -it $name bash"
    log_operation "Deployed Python container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled Python deployment"
  fi
}

deploy_nodejs() {
  clear
  info "部署 Node.js 开发环境"
  local config_file=~/.docker_manager.conf
  local versions=("20" "18" "16")
  local version=$(select_version "Node.js" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：NODEJS_PORT=${NODEJS_PORT:-3000:3000}, NODEJS_NAME=${NODEJS_NAME:-nodejs-app}"
  fi
  read -p "请输入容器名称（默认 ${NODEJS_NAME:-nodejs-app}）: " name
  read -p "请输入端口映射（默认 ${NODEJS_PORT:-3000:3000}）: " port
  read -p "请输入工作目录（默认 /app）: " workdir
  read -p "是否初始化 npm 项目（npm init -y）？(y/n): " init_npm
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${NODEJS_NAME:-nodejs-app}}
  port=${port:-${NODEJS_PORT:-3000:3000}}
  workdir=${workdir:-/app}

  cmd="docker run -d --name $name -p $port -v $(pwd)/nodejs-app:/$workdir -w /$workdir node:$version"
  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p nodejs-app
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy Node.js: $name"; return 1; }
    if [[ "$init_npm" =~ ^[Yy]$ ]]; then
      docker exec "$name" npm init -y || error "npm 初始化失败！"
      docker exec "$name" npm install express || error "express 安装失败！"
    fi
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "NODEJS_NAME=$name" >> "$config_file"
      echo "NODEJS_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "Node.js 环境部署完成！"
    echo "版本：$version"
    echo "访问地址：http://$(hostname -i):${port%%:*}"
    echo "工作目录：$(pwd)/nodejs-app"
    echo "进入容器：docker exec -it $name bash"
    log_operation "Deployed Node.js container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled Node.js deployment"
  fi
}

deploy_php() {
  clear
  info "部署 PHP 开发环境（带 Apache）"
  local config_file=~/.docker_manager.conf
  local versions=("8.2" "8.1" "7.4")
  local version=$(select_version "PHP" "${versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：PHP_PORT=${PHP_PORT:-8080:80}, PHP_NAME=${PHP_NAME:-php-app}"
  fi
  read -p "请输入容器名称（默认 ${PHP_NAME:-php-app}）: " name
  read -p "请输入端口映射（默认 ${PHP_PORT:-8080:80}）: " port
  read -p "请输入工作目录（默认 /var/www/html）: " workdir
  read -p "是否创建默认 index.php？(y/n): " create_index
  read -p "是否生成默认 PHP 配置文件？(y/n): " create_config
  read -p "是否保存配置为默认？(y/n): " save_config

  name=${name:-${PHP_NAME:-php-app}}
  port=${port:-${PHP_PORT:-8080:80}}
  workdir=${workdir:-/var/www/html}

  cmd="docker run -d --name $name -p $port -v $(pwd)/php-app:/$workdir"
  [[ "$create_config" =~ ^[Yy]$ ]] && cmd="$cmd -v $(pwd)/php-config:/usr/local/etc/php"
  cmd="$cmd php:$version-apache"

  info "即将执行：$cmd"
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p php-app
    [[ "$create_config" =~ ^[Yy]$ ]] && mkdir -p php-config
    if [[ "$create_index" =~ ^[Yy]$ ]]; then
      echo "<?php phpinfo();" > php-app/index.php
    fi
    if [[ "$create_config" =~ ^[Yy]$ ]]; then
      generate_config_template "php" "$(pwd)/php-config"
      read -p "是否编辑配置文件？(y/n): " edit_config
      [[ "$edit_config" =~ ^[Yy]$ ]] && nano "$(pwd)/php-config/php.ini"
    fi
    eval "$cmd" || { error "容器创建失败！"; log_operation "Failed to deploy PHP: $name"; return 1; }
    docker exec "$name" bash -c "chown -R www-data:www-data /$workdir && chmod -R 755 /$workdir"
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "PHP_NAME=$name" >> "$config_file"
      echo "PHP_PORT=$port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "PHP 环境部署完成！"
    echo "版本：$version"
    echo "访问地址：http://$(hostname -i):${port%%:*}"
    echo "工作目录：$(pwd)/php-app"
    [[ "$create_config" =~ ^[Yy]$ ]] && echo "配置文件目录：$(pwd)/php-config"
    echo "进入容器：docker exec -it $name bash"
    log_operation "Deployed PHP container: $name, version: $version"
  else
    warning "已取消操作"
    log_operation "Cancelled PHP deployment"
  fi
}

deploy_wordpress() {
  clear
  info "部署 WordPress 网站（包含 MySQL）"
  local config_file=~/.docker_manager.conf
  local wp_versions=("latest" "6.6" "6.5")
  local mysql_versions=("8.0" "8.1" "5.7")
  local wp_version=$(select_version "WordPress" "${wp_versions[@]}")
  local mysql_version=$(select_version "MySQL" "${mysql_versions[@]}")
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    info "已加载默认配置：WORDPRESS_PORT=${WORDPRESS_PORT:-8080:80}, WORDPRESS_NAME=${WORDPRESS_NAME:-wordpress-site}"
  fi
  read -p "请输入 WordPress 容器名称（默认 ${WORDPRESS_NAME:-wordpress-site}）: " wp_name
  read -p "请输入 WordPress 端口映射（默认 ${WORDPRESS_PORT:-8080:80}）: " wp_port
  read -p "请输入 MySQL 容器名称（默认 wordpress-mysql）: " mysql_name
  read -p "请输入 MySQL 根用户密码（默认 wordpress）: " mysql_password
  read -p "请输入 WordPress 数据库名称（默认 wordpress）: " db_name
  read -p "是否保存配置为默认？(y/n): " save_config

  wp_name=${wp_name:-${WORDPRESS_NAME:-wordpress-site}}
  wp_port=${wp_port:-${WORDPRESS_PORT:-8080:80}}
  mysql_name=${mysql_name:-wordpress-mysql}
  mysql_password=${mysql_password:-wordpress}
  db_name=${db_name:-wordpress}

  cat > wordpress-docker-compose.yml <<EOF
version: '3.8'
services:
  mysql:
    image: mysql:$mysql_version
    container_name: $mysql_name
    environment:
      MYSQL_ROOT_PASSWORD: $mysql_password
      MYSQL_DATABASE: $db_name
    volumes:
      - $(pwd)/wordpress-mysql-data:/var/lib/mysql
    restart: always
  wordpress:
    image: wordpress:$wp_version
    container_name: $wp_name
    ports:
      - $wp_port
    environment:
      WORDPRESS_DB_HOST: $mysql_name
      WORDPRESS_DB_USER: root
      WORDPRESS_DB_PASSWORD: $mysql_password
      WORDPRESS_DB_NAME: $db_name
    volumes:
      - $(pwd)/wordpress-data:/var/www/html
    depends_on:
      - mysql
    restart: always
EOF

  info "即将部署 WordPress 和 MySQL..."
  read -p "确认执行？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p wordpress-mysql-data wordpress-data
    docker-compose -f wordpress-docker-compose.yml up -d || { error "部署失败！"; rm -f wordpress-docker-compose.yml; return 1; }
    if [[ "$save_config" =~ ^[Yy]$ ]]; then
      echo "WORDPRESS_NAME=$wp_name" >> "$config_file"
      echo "WORDPRESS_PORT=$wp_port" >> "$config_file"
      success "配置已保存到 $config_file"
    fi
    success "WordPress 网站部署完成！"
    echo "WordPress 版本：$wp_version"
    echo "MySQL 版本：$mysql_version"
    echo "访问地址：http://$(hostname -i):${wp_port%%:*}"
    echo "MySQL 数据目录：$(pwd)/wordpress-mysql-data"
    echo "WordPress 文件目录：$(pwd)/wordpress-data"
    echo "进入 WordPress 容器：docker exec -it $wp_name bash"
    echo "进入 MySQL 容器：docker exec -it $mysql_name mysql -uroot -p"
    rm -f wordpress-docker-compose.yml
    log_operation "Deployed WordPress stack: $wp_name, wp_version: $wp_version, mysql_version: $mysql_version"
  else
    warning "已取消操作"
    rm -f wordpress-docker-compose.yml
    log_operation "Cancelled WordPress deployment"
  fi
}

### === 清理 Docker 环境 === ###
clean_docker() {
  clear
  info "清理 Docker 环境"
  echo "1. 删除所有停止的容器"
  echo "2. 删除所有镜像"
  echo "3. 删除所有卷"
  echo "4. 删除所有网络"
  echo "5. 清理所有内容（谨慎操作）"
  echo "0. 返回"
  read -p "请输入你的选择: " choice

  case $choice in
    1)
      read -p "确认删除所有停止的容器？(y/n): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker container prune -f && success "已删除所有停止的容器！" || error "清理失败！"
        log_operation "Cleaned stopped containers"
      else
        warning "已取消操作"
        log_operation "Cancelled container cleanup"
      fi
      ;;
    2)
      read -p "确认删除所有镜像？(y/n): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker image rm -f $(docker images -q | sort -u) && success "已删除所有镜像！" || error "清理失败！"
        log_operation "Cleaned all images"
      else
        warning "已取消操作"
        log_operation "Cancelled image cleanup"
      fi
      ;;
    3)
      read -p "确认删除所有卷？(y/n): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker volume prune -f && success "已删除所有卷！" || error "清理失败！"
        log_operation "Cleaned all volumes"
      else
        warning "已取消操作"
        log_operation "Cancelled volume cleanup"
      fi
      ;;
    4)
      read -p "确认删除所有非默认网络？(y/n): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker network prune -f && success "已删除所有非默认网络！" || error "清理失败！"
        log_operation "Cleaned all networks"
      else
        warning "已取消操作"
        log_operation "Cancelled network cleanup"
      fi
      ;;
    5)
      read -p "确认清理所有 Docker 内容（包括运行中的容器）？(y/n): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker system prune -a -f --volumes
        docker container stop $(docker container ls -q)
        docker container rm -f $(docker container ls -a -q)
        success "已清理所有 Docker 内容！"
        log_operation "Cleaned entire Docker environment"
      else
        warning "已取消操作"
        log_operation "Cancelled full Docker cleanup"
      fi
      ;;
    0)
      return
      ;;
    *)
      warning "无效选择！"
      ;;
  esac
  read -p "按回车键继续..."
}

### === 卸载 Docker === ###
uninstall_docker() {
  clear
  info "卸载 Docker"
  read -p "确认卸载 Docker 及其所有数据？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    info "正在卸载 Docker..."
    systemctl stop docker
    systemctl disable docker
    if [[ -f "/etc/alpine-release" ]]; then
      apk del docker docker-compose
    else
      apt-get remove -y --purge docker docker-engine docker.io containerd runc || yum remove -y docker docker-engine docker.io containerd runc
      rm -rf /var/lib/docker
      rm -rf /var/run/docker
    fi
    rm -f /usr/local/bin/docker-compose
    success "Docker 已卸载！"
    log_operation "Uninstalled Docker"
  else
    warning "已取消操作"
    log_operation "Cancelled Docker uninstallation"
  fi
  read -p "按回车键继续..."
}

### === 主菜单 === ###
main_menu() {
  while true; do
    clear
    info "Docker 管理器 v$SCRIPT_VERSION"
    echo "------------------------"
    echo "1. 安装/更新 Docker"
    echo "2. 查看 Docker 状态"
    echo "3. 容器管理"
    echo "4. 镜像管理"
    echo "5. 网络管理"
    echo "6. 卷管理"
    echo "7. 查看容器监控"
    echo "8. 备份与恢复"
    echo "9. 配置文件管理"
    echo "10. 日志管理"
    echo "11. 批量操作容器"
    echo "12. 部署应用栈"
    echo "13. 一键部署应用"
    echo "14. 清理 Docker 环境"
    echo "15. 卸载 Docker"
    echo "0. 退出"
    echo "------------------------"
    read -p "请输入你的选择: " choice

    case $choice in
      1)
        install_docker
        ;;
      2)
        view_docker_status
        ;;
      3)
        manage_containers
        ;;
      4)
        manage_images
        ;;
      5)
        manage_networks
        ;;
      6)
        manage_volumes
        ;;
      7)
        monitor_containers
        ;;
      8)
        manage_backup
        ;;
      9)
        manage_config
        ;;
      10)
        manage_logs
        ;;
      11)
        manage_batch
        ;;
      12)
        deploy_stack
        ;;
      13)
        deploy_app
        ;;
      14)
        clean_docker
        ;;
      15)
        uninstall_docker
        ;;
      0)
        success "感谢使用，退出脚本！"
        exit 0
        ;;
      *)
        warning "无效选择，请重试！"
        ;;
    esac
    read -p "按回车键继续..."
  done
}

### === 脚本入口 === ###
check_dependencies
main_menu