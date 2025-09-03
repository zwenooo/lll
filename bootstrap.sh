#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
PLAIN='\033[0m'

# Config
: "${XRY_VERSION:=}"   # optional, e.g. v1.2.3
XRY_INSTALL_CMD=(gh api repos/zwenooo/xrayr-release/contents/install.sh?ref=master --jq .content)

# sudo helper
SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo -e "${RED}需要 root 或 sudo 权限来安装依赖${PLAIN}"
    exit 1
  fi
fi

log() { echo -e "${GREEN}==>${PLAIN} $*"; }
warn() { echo -e "${YELLOW}==> WARN:${PLAIN} $*"; }
err() { echo -e "${RED}==> ERROR:${PLAIN} $*" >&2; }

detect_arch() {
  local uarch
  uarch=$(uname -m)
  case "$uarch" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l|armv7) echo armv7 ;;
    s390x) echo s390x ;;
    i386|i686) echo 386 ;;
    *) echo amd64 ; warn "未知架构 ${uarch}，回退为 amd64" ;;
  esac
}

install_gh_pkg() {
  if command -v gh >/dev/null 2>&1; then return 0; fi
  log "安装 GitHub CLI (gh)"

  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -y
    $SUDO apt-get install -y curl ca-certificates gnupg
    if [[ ! -f /usr/share/keyrings/githubcli-archive-keyring.gpg ]]; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
      $SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    fi
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    $SUDO apt-get update -y
    $SUDO apt-get install -y gh && return 0 || warn "apt 安装 gh 失败，尝试二进制安装"
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf -y install dnf-plugins-core || true
    $SUDO dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo || true
    $SUDO dnf -y install gh && return 0 || warn "dnf 安装 gh 失败，尝试二进制安装"
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum -y install yum-utils || true
    $SUDO yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo || true
    $SUDO yum -y install gh && return 0 || warn "yum 安装 gh 失败，尝试二进制安装"
  elif command -v zypper >/dev/null 2>&1; then
    $SUDO zypper --non-interactive addrepo https://cli.github.com/packages/rpm/gh-cli.repo gh-cli || true
    $SUDO zypper --gpg-auto-import-keys --non-interactive refresh || true
    $SUDO zypper --non-interactive install gh && return 0 || warn "zypper 安装 gh 失败，尝试二进制安装"
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache github-cli || $SUDO apk add --no-cache gh || warn "apk 安装 gh 失败，尝试二进制安装"
    command -v gh >/dev/null 2>&1 && return 0
  fi

  install_gh_binary
}

install_gh_binary() {
  log "使用二进制安装 gh"
  $SUDO mkdir -p /usr/local/bin
  $SUDO mkdir -p /tmp/gh-install
  local arch ver tag url tmp
  arch=$(detect_arch)
  # 获取最新版本 tag
  tag=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | sed -n 's/.*"tag_name":\s*"\([^"]\+\)".*/\1/p' | head -n1)
  if [[ -z "$tag" ]]; then err "获取 gh 最新版本失败"; exit 1; fi
  ver=${tag#v}
  url="https://github.com/cli/cli/releases/download/${tag}/gh_${ver}_linux_${arch}.tar.gz"
  tmp="/tmp/gh-install/gh_${ver}_linux_${arch}.tar.gz"
  curl -fsSL "$url" -o "$tmp" || { err "下载 gh 二进制失败: $url"; exit 1; }
  tar -C /tmp/gh-install -xzf "$tmp"
  if [[ -f "/tmp/gh-install/gh_${ver}_linux_${arch}/bin/gh" ]]; then
    $SUDO install -m 0755 "/tmp/gh-install/gh_${ver}_linux_${arch}/bin/gh" /usr/local/bin/gh
  else
    err "解压后未找到 gh 可执行文件"; exit 1
  fi
  command -v gh >/dev/null 2>&1 || { err "gh 安装失败"; exit 1; }
}

login_gh() {
  if gh auth status >/dev/null 2>&1; then
    log "gh 已登录"
    return 0
  fi
  if [[ -n "${GITHUB_TOKEN:-}" || -n "${GH_TOKEN:-}" ]]; then
    local tok=${GITHUB_TOKEN:-${GH_TOKEN}}
    log "使用环境变量 token 登录 gh"
    printf "%s" "$tok" | gh auth login --hostname github.com --with-token
  else
    log "开始交互式登录 gh（回车选择默认，按提示在浏览器授权）"
    gh auth login -h github.com -s 'repo' -p https
  fi
}

run_xrayr_install() {
  log "执行 XrayR 安装脚本"
  if [[ -n "${XRY_VERSION}" ]]; then
    bash <(gh api repos/zwenooo/xrayr-release/contents/install.sh?ref=master --jq .content | base64 -d) "${XRY_VERSION}"
  else
    bash <(gh api repos/zwenooo/xrayr-release/contents/install.sh?ref=master --jq .content | base64 -d)
  fi
}

main() {
  install_gh_pkg
  gh --version | head -n1
  login_gh
  run_xrayr_install
}

main "$@"

