#!/usr/bin/env bash

set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "请使用 root 身份运行此脚本"
  exit 1
fi

log() {
  printf '[INFO] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_os() {
  if [ ! -f /etc/os-release ]; then
    echo "无法识别系统：缺少 /etc/os-release"
    exit 1
  fi

  . /etc/os-release
  OS_ID="${ID:-}"
  OS_VERSION_ID="${VERSION_ID:-}"
  OS_CODENAME="${VERSION_CODENAME:-}"

  case "$OS_ID" in
    debian|ubuntu|raspbian)
      PKG_TYPE="apt"
      ;;
    centos|rhel|rocky|almalinux|ol|fedora)
      PKG_TYPE="dnf"
      ;;
    *)
      echo "当前脚本暂不支持该系统：$OS_ID"
      exit 1
      ;;
  esac
}

install_prereqs_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
}

install_docker_apt() {
  local repo_url="https://mirrors.aliyun.com/docker-ce/linux/${OS_ID}"
  local gpg_url="${repo_url}/gpg"

  install_prereqs_apt

  if [ -z "$OS_CODENAME" ]; then
    OS_CODENAME=$(awk -F'[=(]' '/VERSION_CODENAME|DISTRIB_CODENAME/{print $2; exit}' /etc/os-release 2>/dev/null || true)
  fi

  if [ -z "$OS_CODENAME" ] && [ "$OS_ID" = "debian" ]; then
    case "$OS_VERSION_ID" in
      12) OS_CODENAME="bookworm" ;;
      11) OS_CODENAME="bullseye" ;;
      10) OS_CODENAME="buster" ;;
    esac
  fi

  if [ -z "$OS_CODENAME" ] && [ "$OS_ID" = "ubuntu" ]; then
    case "$OS_VERSION_ID" in
      24.04) OS_CODENAME="noble" ;;
      22.04) OS_CODENAME="jammy" ;;
      20.04) OS_CODENAME="focal" ;;
      18.04) OS_CODENAME="bionic" ;;
    esac
  fi

  if [ -z "$OS_CODENAME" ]; then
    echo "无法识别系统代号，请手动检查 /etc/os-release"
    exit 1
  fi

  log "配置 Docker APT 国内源: $repo_url"
  curl -fsSL "$gpg_url" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  cat > /etc/apt/sources.list.d/docker.list <<EOF
 deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $repo_url $OS_CODENAME stable
EOF

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_prereqs_dnf() {
  if command_exists dnf; then
    dnf install -y dnf-plugins-core ca-certificates curl
  else
    yum install -y yum-utils ca-certificates curl
  fi
}

install_docker_dnf() {
  local repo_file="/etc/yum.repos.d/docker-ce.repo"
  local base_url

  install_prereqs_dnf

  case "$OS_ID" in
    fedora)
      base_url="https://mirrors.aliyun.com/docker-ce/linux/fedora/docker-ce.repo"
      ;;
    *)
      base_url="https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
      ;;
  esac

  log "配置 Docker YUM/DNF 国内源: $base_url"
  curl -fsSL "$base_url" -o "$repo_file"

  if command_exists dnf; then
    dnf makecache
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    yum makecache fast
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
}

configure_daemon_mirror() {
  install -d /etc/docker

  cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io",
    "https://docker.hlmirror.com",
    "https://docker.amingg.com",
    "https://dockerproxy.net",
    "https://docker.1panel.live",
    "https://docker.kejilion.pro"
  ]
}
EOF
}

enable_docker_service() {
  systemctl daemon-reload
  systemctl enable docker
  systemctl restart docker
}

verify_installation() {
  log "Docker 版本信息"
  docker --version
  docker compose version
  echo
  log "当前镜像加速配置"
  cat /etc/docker/daemon.json
}

main() {
  detect_os
  log "检测到系统: ${OS_ID} ${OS_VERSION_ID:-unknown}"

  case "$PKG_TYPE" in
    apt)
      install_docker_apt
      ;;
    dnf)
      install_docker_dnf
      ;;
  esac

  configure_daemon_mirror
  enable_docker_service
  verify_installation

  log "Docker 安装完成，已启用大陆镜像加速环境"
}

main "$@"
