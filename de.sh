#!/bin/bash
set -e

# ==============================
# 基础配置
# ==============================
DOWNLOAD_DIR="$HOME/pp"
BASE_DIR="/opt/ppanel"
VERSION=$(date +%Y%m%d-%H%M%S)

# Supervisor 配置
# 主配置文件由系统管理（1Panel 亦使用它）
SUPERVISOR_CONF="/etc/supervisor/supervisord.conf"
# 1Panel 管理的 program ini 目录
SUPERVISOR_DIR="/opt/1panel/tools/supervisord/supervisor.d"

# GitHub CLI 配置
PPW_REPO="zwenooo/ppw"
PPS_REPO="zwenooo/pps"

# 使用固定标签（latest）
RELEASE_TAG="latest"

# 文件名模式（与 release 资产名称匹配）
ADMIN_FILE="ppanel-admin-web.tar.gz"
USER_FILE="ppanel-user-web.tar.gz"
SERVER_FILE="ppanel-server-linux-amd64.tar.gz"

# 运行中环境中的配置文件路径（统一集中到 shared 目录）
SERVER_CFG_SHARED="$BASE_DIR/shared/config/server/ppanel.yaml"
ADMIN_ENV_SHARED="$BASE_DIR/shared/config/admin/.env"
USER_ENV_SHARED="$BASE_DIR/shared/config/user/.env"

echo "开始部署 PPanel: $VERSION"

# 创建必要目录
mkdir -p "$DOWNLOAD_DIR" "$BASE_DIR/shared/logs" "$BASE_DIR/shared/config/server" "$BASE_DIR/shared/config/admin" "$BASE_DIR/shared/config/user"

usage() {
  cat <<EOF
用法: $0 [server|admin|user|all]
  server  仅下载并更新服务端
  admin   仅下载并更新管理端
  user    仅下载并更新用户端
  all     下载并更新全部组件
EOF
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

ARG="$1"
case "$ARG" in
  server|admin|user|all) ;;
  *)
    echo "未知参数: $ARG"
    usage
    exit 1
    ;;
esac

# ==============================
# 工具函数
# ==============================

# 使用 GitHub CLI 下载 release 文件到版本目录
download_release() {
    local name="$1"
    local repo="$2"
    local tag="$3"
    local filename="$4"
    local deploy_path="$5"

    echo "下载 $name release 文件..."

    local releases_dir="$deploy_path/releases"
    local version_dir="$releases_dir/$VERSION"
    mkdir -p "$releases_dir" "$version_dir"

    # 下载
    (cd "$DOWNLOAD_DIR" && gh release download --repo "$repo" "$tag" -p "$filename")

    # 解压到版本目录
    tar -xzf "$DOWNLOAD_DIR/$filename" -C "$version_dir"
    rm -f "$DOWNLOAD_DIR/$filename"

    echo "$name 下载完成"
}

# 保留最新配置样本，并继续使用运行中配置
preserve_configs() {
    local component="$1"          # server|admin|user
    local version_dir="$2"        # 该组件的版本目录

    case "$component" in
      server)
        # 发行包中的默认位置（相对）
        local rel_cfg_path="etc/ppanel.yaml"
        local new_cfg="$version_dir/$rel_cfg_path"
        # 首次部署：若 shared 中还没有运行配置，则用新包默认配置初始化
        if [ ! -f "$SERVER_CFG_SHARED" ]; then
          echo "首次初始化 server 运行配置到: $SERVER_CFG_SHARED"
          mkdir -p "$(dirname "$SERVER_CFG_SHARED")"
          if [ -f "$new_cfg" ]; then cp -f "$new_cfg" "$SERVER_CFG_SHARED"; fi
        fi
        ;;
      admin)
        local env_path="ppanel-admin-web/apps/admin/.env"
        local env_file="$version_dir/$env_path"
        # 首次部署：若 shared 中还没有运行配置，则用新包中的 .env 初始化
        if [ ! -f "$ADMIN_ENV_SHARED" ]; then
          mkdir -p "$(dirname "$ADMIN_ENV_SHARED")"
          if [ -f "$env_file" ]; then
            cp -f "$env_file" "$ADMIN_ENV_SHARED"
          fi
        fi
        ;;
      user)
        local env_path="ppanel-user-web/apps/user/.env"
        local env_file="$version_dir/$env_path"
        # 首次部署：若 shared 中还没有运行配置，则用新包中的 .env 初始化
        if [ ! -f "$USER_ENV_SHARED" ]; then
          mkdir -p "$(dirname "$USER_ENV_SHARED")"
          if [ -f "$env_file" ]; then
            cp -f "$env_file" "$USER_ENV_SHARED"
          fi
        fi
        ;;
    esac
}

# 部署某个组件
deploy_component() {
    local name="$1"      # admin|user|server
    local repo="$2"
    local tag="$3"
    local filename="$4"
    local deploy_path="$5"

    echo "部署 $name..."

    download_release "$name" "$repo" "$tag" "$filename" "$deploy_path"

    local version_dir="$deploy_path/releases/$VERSION"

    # 处理配置：保留新样本，继续使用运行中配置
    preserve_configs "$name" "$version_dir"

    # 部署到运行目录
    case "$name" in
      server)
        # 切换运行目录到新版本（通过符号链接），并将版本内 etc/ppanel.yaml 链接到 shared 配置
        local new_srv_dir="$version_dir"
        mkdir -p "$BASE_DIR/server"
        # 确保二进制可执行（位于版本目录中）
        [ -f "$new_srv_dir/ppanel-server" ] && chmod +x "$new_srv_dir/ppanel-server" || true
        # 备份版本目录中原始配置（每次更新都备份为 .backup，使用 cp 保留原文件）
        if [ -f "$new_srv_dir/etc/ppanel.yaml" ] && [ ! -L "$new_srv_dir/etc/ppanel.yaml" ]; then
          cp -f "$new_srv_dir/etc/ppanel.yaml" "$new_srv_dir/etc/ppanel.yaml.backup"
          if [ ! -s "$new_srv_dir/etc/ppanel.yaml.backup" ]; then
            echo "警告: 服务器默认配置备份为空: $new_srv_dir/etc/ppanel.yaml.backup"
          fi
        else
          echo "提示: 未找到服务器默认配置用于备份: $new_srv_dir/etc/ppanel.yaml"
        fi
        # 若目标路径已是目录而非符号链接，需先移除
        if [ -d "$BASE_DIR/server/ppanel-server" ] && [ ! -L "$BASE_DIR/server/ppanel-server" ]; then
          rm -rf "$BASE_DIR/server/ppanel-server"
        fi
        ln -sfn "$new_srv_dir" "$BASE_DIR/server/ppanel-server"
        # 将运行所需配置链接到 shared 配置
        local target_cfg="$BASE_DIR/server/ppanel-server/etc/ppanel.yaml"
        mkdir -p "$(dirname "$target_cfg")"
        rm -f "$target_cfg"
        ln -sfn "$SERVER_CFG_SHARED" "$target_cfg"
        ;;
      admin)
        # 切换运行目录到新版本的 ppanel-admin-web
        local new_web_dir="$version_dir/ppanel-admin-web"
        mkdir -p "$BASE_DIR/admin"
        # 备份新版本目录中原始 .env（每次更新都备份为 .env.backup），随后将 .env 链接到 shared 配置
        mkdir -p "$new_web_dir/apps/admin"
        if [ -f "$new_web_dir/apps/admin/.env" ] && [ ! -L "$new_web_dir/apps/admin/.env" ]; then
          cp -f "$new_web_dir/apps/admin/.env" "$new_web_dir/apps/admin/.env.backup"
          if [ ! -s "$new_web_dir/apps/admin/.env.backup" ]; then
            echo "警告: admin 默认配置(.env)备份为空: $new_web_dir/apps/admin/.env.backup"
          fi
        fi
        rm -f "$new_web_dir/apps/admin/.env"
        if [ -f "$ADMIN_ENV_SHARED" ]; then
          ln -sfn "$ADMIN_ENV_SHARED" "$new_web_dir/apps/admin/.env"
        elif [ -f "$new_web_dir/apps/admin/.env" ]; then
          cp -f "$new_web_dir/apps/admin/.env" "$ADMIN_ENV_SHARED"
          ln -sfn "$ADMIN_ENV_SHARED" "$new_web_dir/apps/admin/.env"
        fi
        # 若目标路径已是目录而非符号链接，需先移除，否则 ln 会在该目录内再创建同名链接
        if [ -d "$BASE_DIR/admin/ppanel-admin-web" ] && [ ! -L "$BASE_DIR/admin/ppanel-admin-web" ]; then
          rm -rf "$BASE_DIR/admin/ppanel-admin-web"
        fi
        ln -sfn "$new_web_dir" "$BASE_DIR/admin/ppanel-admin-web"
        ;;
      user)
        # 切换运行目录到新版本的 ppanel-user-web
        local new_web_dir="$version_dir/ppanel-user-web"
        mkdir -p "$BASE_DIR/user"
        # 备份新版本目录中原始 .env（每次更新都备份为 .env.backup），随后将 .env 链接到 shared 配置
        mkdir -p "$new_web_dir/apps/user"
        if [ -f "$new_web_dir/apps/user/.env" ] && [ ! -L "$new_web_dir/apps/user/.env" ]; then
          cp -f "$new_web_dir/apps/user/.env" "$new_web_dir/apps/user/.env.backup"
          if [ ! -s "$new_web_dir/apps/user/.env.backup" ]; then
            echo "警告: user 默认配置(.env)备份为空: $new_web_dir/apps/user/.env.backup"
          fi
        fi
        rm -f "$new_web_dir/apps/user/.env"
        if [ -f "$USER_ENV_SHARED" ]; then
          ln -sfn "$USER_ENV_SHARED" "$new_web_dir/apps/user/.env"
        elif [ -f "$new_web_dir/apps/user/.env" ]; then
          cp -f "$new_web_dir/apps/user/.env" "$USER_ENV_SHARED"
          ln -sfn "$USER_ENV_SHARED" "$new_web_dir/apps/user/.env"
        fi
        # 若目标路径已是目录而非符号链接，需先移除，否则 ln 会在该目录内再创建同名链接
        if [ -d "$BASE_DIR/user/ppanel-user-web" ] && [ ! -L "$BASE_DIR/user/ppanel-user-web" ]; then
          rm -rf "$BASE_DIR/user/ppanel-user-web"
        fi
        ln -sfn "$new_web_dir" "$BASE_DIR/user/ppanel-user-web"
        ;;
    esac

    echo "$name 部署完成"
}

# ==============================
# 选择性部署
# ==============================
DO_SERVER=false
DO_ADMIN=false
DO_USER=false
case "$ARG" in
  all)
    DO_SERVER=true; DO_ADMIN=true; DO_USER=true ;;
  server)
    DO_SERVER=true ;;
  admin)
    DO_ADMIN=true ;;
  user)
    DO_USER=true ;;
esac

if $DO_ADMIN; then
  deploy_component "admin" "$PPW_REPO" "$RELEASE_TAG" "$ADMIN_FILE" "$BASE_DIR/admin"
fi
if $DO_USER; then
  deploy_component "user" "$PPW_REPO" "$RELEASE_TAG" "$USER_FILE" "$BASE_DIR/user"
fi
if $DO_SERVER; then
  deploy_component "server" "$PPS_REPO" "$RELEASE_TAG" "$SERVER_FILE" "$BASE_DIR/server"
fi

# ==============================
# 重启服务
# ==============================
echo "重启相关服务..."

# supervisorctl 封装：使用系统 supervisorctl，并显式指定 -c 配置
_supervisorctl_bin() { echo "supervisorctl"; }
run_supervisorctl() {
  local bin
  bin=$(_supervisorctl_bin)
  if [ -f "$SUPERVISOR_CONF" ]; then
    "$bin" -c "$SUPERVISOR_CONF" "$@"
  else
    "$bin" "$@"
  fi
}

# supervisorctl 辅助函数：restart 或首次启动
supervisor_reload() {
  run_supervisorctl reread >/dev/null 2>&1 || true
  run_supervisorctl update >/dev/null 2>&1 || true
}
supervisor_restart_or_start() {
  local name="$1"
  run_supervisorctl restart "$name" >/dev/null 2>&1 && { echo "supervisor: $name restarted"; return 0; }
  run_supervisorctl start   "$name" >/dev/null 2>&1 && { echo "supervisor: $name started";  return 0; }
  supervisor_reload
  run_supervisorctl start   "$name" >/dev/null 2>&1 && { echo "supervisor: $name started (after reload)"; return 0; }
  return 1
}

if $DO_SERVER; then
  supervisor_restart_or_start ppserver: || echo "server 进程未在 supervisor 中注册: 请检查 $SUPERVISOR_DIR/ppserver.ini"
fi
if $DO_ADMIN; then
  supervisor_restart_or_start ppadmin:  || echo "admin 进程未在 supervisor 中注册: 请检查 $SUPERVISOR_DIR/ppadmin.ini"
fi
if $DO_USER; then
  supervisor_restart_or_start ppuser:   || echo "user 进程未在 supervisor 中注册: 请检查 $SUPERVISOR_DIR/ppuser.ini"
fi
# 不处理 Nginx，由 1Panel 管理

# ==============================
# 清理旧版本（各自保留最近3个）
# ==============================
for component in admin user server; do
    case "$component" in
      admin) $DO_ADMIN || continue ;;
      user)  $DO_USER  || continue ;;
      server)$DO_SERVER|| continue ;;
    esac
    cd "$BASE_DIR/$component/releases" 2>/dev/null || continue
    ls -t | tail -n +4 | xargs rm -rf 2>/dev/null || true
done

echo "PPanel 部署完成: $VERSION"

# ==============================
# 健康检查与回滚（仅在更新 server 时执行）
# ==============================
health_check() {
    local retries=5
    local delay=5
    local url="${HEALTH_URL:-}"
    local port=""

    echo "开始健康检查..."

    # 若未指定 HEALTH_URL，则从 shared 配置中读取端口，默认 8080
    if [ -z "$url" ]; then
        port=8080
        if [ -f "$SERVER_CFG_SHARED" ]; then
          # 读取 YAML 顶层 Port: 值（忽略注释与前置空白）
          local p
          p=$(awk '/^[[:space:]]*Port:[[:space:]]*/{ gsub(/^[^:]*:[[:space:]]*/, "", $0); print $0; exit }' "$SERVER_CFG_SHARED" 2>/dev/null | tr -d '\r')
          if echo "$p" | grep -Eoq '^[0-9]+'; then
            port=$(echo "$p" | grep -Eo '^[0-9]+')
          fi
        fi
    fi

    for i in $(seq 1 $retries); do
        if [ -n "$url" ]; then
            # 明确指定了健康检查 URL，直接探测（不以 HTTP 状态码作为失败标准）
            if curl -sS --connect-timeout 3 --max-time 5 -o /dev/null "$url"; then
                echo "服务健康检查通过"
                return 0
            fi
        else
            # 未指定 URL：优先尝试 HTTP 根路径，再尝试 HTTPS 根路径（忽略证书验证）
            if curl -sS --connect-timeout 3 --max-time 5 -o /dev/null "http://127.0.0.1:$port/"; then
                echo "服务健康检查通过"
                return 0
            fi
            if curl -ksS --connect-timeout 3 --max-time 5 -o /dev/null "https://127.0.0.1:$port/"; then
                echo "服务健康检查通过"
                return 0
            fi
        fi
        echo "健康检查失败，等待${delay}秒后重试... ($i/$retries)"
        sleep "$delay"
    done

    echo "健康检查失败，可能需要手动检查服务状态"
    return 1
}

rollback() {
    echo "检测到服务异常，开始回滚..."

    # 管理端回滚：切回上一个版本并将 .env 链接至 shared（同时备份 .env）
    if $DO_ADMIN; then
      local releases_dir="$BASE_DIR/admin/releases"
      if [ -d "$releases_dir" ]; then
        local prev_version=$(ls -t "$releases_dir" 2>/dev/null | sed -n '2p')
        if [ -n "$prev_version" ]; then
          local prev_dir="$releases_dir/$prev_version/ppanel-admin-web"
          mkdir -p "$prev_dir/apps/admin"
          if [ -f "$prev_dir/apps/admin/.env" ] && [ ! -L "$prev_dir/apps/admin/.env" ]; then
            cp -f "$prev_dir/apps/admin/.env" "$prev_dir/apps/admin/.env.backup"
          fi
          rm -f "$prev_dir/apps/admin/.env"
          if [ -f "$ADMIN_ENV_SHARED" ]; then
            ln -sfn "$ADMIN_ENV_SHARED" "$prev_dir/apps/admin/.env"
          fi
          ln -sfn "$prev_dir" "$BASE_DIR/admin/ppanel-admin-web"
        fi
      fi
    fi

    # 用户端回滚：切回上一个版本并将 .env 链接至 shared（同时备份 .env）
    if $DO_USER; then
      local releases_dir="$BASE_DIR/user/releases"
      if [ -d "$releases_dir" ]; then
        local prev_version=$(ls -t "$releases_dir" 2>/dev/null | sed -n '2p')
        if [ -n "$prev_version" ]; then
          local prev_dir="$releases_dir/$prev_version/ppanel-user-web"
          mkdir -p "$prev_dir/apps/user"
          if [ -f "$prev_dir/apps/user/.env" ] && [ ! -L "$prev_dir/apps/user/.env" ]; then
            cp -f "$prev_dir/apps/user/.env" "$prev_dir/apps/user/.env.backup"
          fi
          rm -f "$prev_dir/apps/user/.env"
          if [ -f "$USER_ENV_SHARED" ]; then
            ln -sfn "$USER_ENV_SHARED" "$prev_dir/apps/user/.env"
          fi
          ln -sfn "$prev_dir" "$BASE_DIR/user/ppanel-user-web"
        fi
      fi
    fi

    # 服务端回滚：指向上一个 releases 目录，并链接 etc/ppanel.yaml 到 shared 配置（同时备份原始 ppanel.yaml）
    if $DO_SERVER; then
      local releases_dir="$BASE_DIR/server/releases"
      if [ -d "$releases_dir" ]; then
        local prev_version=$(ls -t "$releases_dir" 2>/dev/null | sed -n '2p')
        if [ -n "$prev_version" ]; then
          local prev_dir="$releases_dir/$prev_version"
          mkdir -p "$BASE_DIR/server"
          [ -f "$prev_dir/ppanel-server" ] && chmod +x "$prev_dir/ppanel-server" || true
          ln -sfn "$prev_dir" "$BASE_DIR/server/ppanel-server"
          # 备份回滚版本目录中的原始配置（每次回滚也备份为 .backup，使用 cp 保留原文件），并衔接回滚后的配置链接
          if [ -f "$prev_dir/etc/ppanel.yaml" ] && [ ! -L "$prev_dir/etc/ppanel.yaml" ]; then
            cp -f "$prev_dir/etc/ppanel.yaml" "$prev_dir/etc/ppanel.yaml.backup"
          fi
          local target_cfg="$BASE_DIR/server/ppanel-server/etc/ppanel.yaml"
          mkdir -p "$(dirname "$target_cfg")"
          rm -f "$target_cfg"
          ln -sfn "$SERVER_CFG_SHARED" "$target_cfg"
        fi
      fi
    fi

    # 重启相关服务（或首次启动）
    if $DO_SERVER; then
      supervisor_restart_or_start ppserver: || echo "server 进程未在 supervisor 中注册"
    fi
    if $DO_ADMIN; then
      supervisor_restart_or_start ppadmin:  || echo "admin 进程未在 supervisor 中注册"
    fi
    if $DO_USER; then
      supervisor_restart_or_start ppuser:   || echo "user 进程未在 supervisor 中注册"
    fi
    # 不处理 Nginx，由 1Panel 管理

    echo "回滚完成"
}

if $DO_SERVER; then
  if ! health_check; then
      read -p "健康检查失败，是否回滚到上一版本? (y/N): " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
          rollback
      fi
  fi
fi

echo "部署脚本执行完成"
