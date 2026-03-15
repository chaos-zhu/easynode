#!/usr/bin/env bash

set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "请使用 root 身份运行此脚本"
  exit 1
fi

SCRIPT_URL_CN="https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh"
WORK_DIR="/tmp/reinstall-bin456789"
SCRIPT_PATH="$WORK_DIR/reinstall.sh"

mkdir -p "$WORK_DIR"

log() {
  printf '[INFO] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_basic_tools() {
  if need_cmd apt-get; then
    apt-get update -y
    apt-get install -y curl wget
  elif need_cmd dnf; then
    dnf install -y curl wget
  elif need_cmd yum; then
    yum install -y curl wget
  elif need_cmd apk; then
    apk add --no-cache curl wget
  else
    warn "未识别包管理器，请确保系统已安装 curl 或 wget"
  fi
}

download_reinstall_script() {
  log "下载 bin456789/reinstall 脚本"
  if need_cmd curl; then
    curl -fsSL -o "$SCRIPT_PATH" "$SCRIPT_URL_CN"
  else
    wget -O "$SCRIPT_PATH" "$SCRIPT_URL_CN"
  fi
  chmod +x "$SCRIPT_PATH"
}

confirm_reinstall() {
  echo "--------------------------------"
  echo "该脚本仅封装 bin456789/reinstall 项目。"
  echo "重装会清空目标硬盘数据，存在失联风险。"
  echo "请提前备份重要数据，并确认可以接受自动重启。"
  echo "如果误操作，可在重启前执行: bash reinstall.sh reset"
  echo "--------------------------------"
  read -r -p "确认继续吗？(Y/N): " answer
  case "$answer" in
    [Yy]) ;;
    *)
      echo "已取消"
      exit 0
      ;;
  esac
}

read_password_args() {
  local prompt="$1"
  local user_label="$2"
  local pass
  echo "默认用户名: $user_label"
  read -r -s -p "$prompt" pass
  echo
  if [ -n "$pass" ]; then
    PASSWORD_ARGS=(--password "$pass")
  else
    PASSWORD_ARGS=()
    echo "未输入密码，将由上游脚本自动生成随机密码"
  fi
}

run_reinstall() {
  install_basic_tools
  download_reinstall_script
  cd "$WORK_DIR"
  bash "$SCRIPT_PATH" "$@"
}

show_menu() {
  cat <<'EOF'
--------------------------------
bin456789/reinstall 独立封装脚本
--------------------------------
Linux 重装
 1. Debian 13
 2. Debian 12
 3. Debian 11
 4. Debian 10
11. Ubuntu 24.04
12. Ubuntu 22.04
13. Ubuntu 20.04
14. Ubuntu 18.04
21. Alpine 3.23
22. Rocky 10
23. AlmaLinux 10
24. Oracle 10
25. Fedora 43
26. openEuler 24.03
27. openSUSE tumbleweed
28. Kali
29. Arch
30. Gentoo
31. fnOS 1
--------------------------------
Windows 安装
41. Windows 11 Pro
42. Windows 11 Enterprise LTSC 2024
43. Windows Server 2025 Datacenter
44. Windows Server 2022 Datacenter
--------------------------------
其它功能
51. DD 指定 Raw 镜像
52. 启动到 Alpine Live OS (--hold 1)
53. 启动到 netboot.xyz
54. 取消重装 (reset)
--------------------------------
 0. 退出
--------------------------------
EOF
}

main() {
  local choice
  local img_url
  local image_name

  confirm_reinstall
  show_menu
  read -r -p "请选择功能: " choice

  case "$choice" in
    1)
      read_password_args "请输入 Debian 13 的 root 密码(留空则随机): " "root"
      run_reinstall debian 13 "${PASSWORD_ARGS[@]}"
      ;;
    2)
      read_password_args "请输入 Debian 12 的 root 密码(留空则随机): " "root"
      run_reinstall debian 12 "${PASSWORD_ARGS[@]}"
      ;;
    3)
      read_password_args "请输入 Debian 11 的 root 密码(留空则随机): " "root"
      run_reinstall debian 11 "${PASSWORD_ARGS[@]}"
      ;;
    4)
      read_password_args "请输入 Debian 10 的 root 密码(留空则随机): " "root"
      run_reinstall debian 10 "${PASSWORD_ARGS[@]}"
      ;;
    11)
      read_password_args "请输入 Ubuntu 24.04 的 root 密码(留空则随机): " "root"
      run_reinstall ubuntu 24.04 "${PASSWORD_ARGS[@]}"
      ;;
    12)
      read_password_args "请输入 Ubuntu 22.04 的 root 密码(留空则随机): " "root"
      run_reinstall ubuntu 22.04 "${PASSWORD_ARGS[@]}"
      ;;
    13)
      read_password_args "请输入 Ubuntu 20.04 的 root 密码(留空则随机): " "root"
      run_reinstall ubuntu 20.04 "${PASSWORD_ARGS[@]}"
      ;;
    14)
      read_password_args "请输入 Ubuntu 18.04 的 root 密码(留空则随机): " "root"
      run_reinstall ubuntu 18.04 "${PASSWORD_ARGS[@]}"
      ;;
    21)
      read_password_args "请输入 Alpine 3.23 的 root 密码(留空则随机): " "root"
      run_reinstall alpine 3.23 "${PASSWORD_ARGS[@]}"
      ;;
    22)
      read_password_args "请输入 Rocky 10 的 root 密码(留空则随机): " "root"
      run_reinstall rocky 10 "${PASSWORD_ARGS[@]}"
      ;;
    23)
      read_password_args "请输入 AlmaLinux 10 的 root 密码(留空则随机): " "root"
      run_reinstall almalinux 10 "${PASSWORD_ARGS[@]}"
      ;;
    24)
      read_password_args "请输入 Oracle 10 的 root 密码(留空则随机): " "root"
      run_reinstall oracle 10 "${PASSWORD_ARGS[@]}"
      ;;
    25)
      read_password_args "请输入 Fedora 43 的 root 密码(留空则随机): " "root"
      run_reinstall fedora 43 "${PASSWORD_ARGS[@]}"
      ;;
    26)
      read_password_args "请输入 openEuler 24.03 的 root 密码(留空则随机): " "root"
      run_reinstall openeuler 24.03 "${PASSWORD_ARGS[@]}"
      ;;
    27)
      read_password_args "请输入 openSUSE tumbleweed 的 root 密码(留空则随机): " "root"
      run_reinstall opensuse tumbleweed "${PASSWORD_ARGS[@]}"
      ;;
    28)
      read_password_args "请输入 Kali 的 root 密码(留空则随机): " "root"
      run_reinstall kali "${PASSWORD_ARGS[@]}"
      ;;
    29)
      read_password_args "请输入 Arch 的 root 密码(留空则随机): " "root"
      run_reinstall arch "${PASSWORD_ARGS[@]}"
      ;;
    30)
      read_password_args "请输入 Gentoo 的 root 密码(留空则随机): " "root"
      run_reinstall gentoo "${PASSWORD_ARGS[@]}"
      ;;
    31)
      read_password_args "请输入 fnOS 1 的 root 密码(留空则随机): " "root"
      run_reinstall fnos 1 "${PASSWORD_ARGS[@]}"
      ;;

    41)
      read_password_args "请输入 Windows 11 Pro 的 administrator 密码(留空则随机): " "administrator"
      run_reinstall windows --image-name "Windows 11 Pro" --lang zh-cn "${PASSWORD_ARGS[@]}"
      ;;
    42)
      read_password_args "请输入 Windows 11 Enterprise LTSC 2024 的 administrator 密码(留空则随机): " "administrator"
      run_reinstall windows --image-name "Windows 11 Enterprise LTSC 2024" --lang zh-cn "${PASSWORD_ARGS[@]}"
      ;;
    43)
      read_password_args "请输入 Windows Server 2025 Datacenter 的 administrator 密码(留空则随机): " "administrator"
      run_reinstall windows --image-name "Windows Server 2025 SERVERDATACENTER" --lang zh-cn "${PASSWORD_ARGS[@]}"
      ;;
    44)
      read_password_args "请输入 Windows Server 2022 Datacenter 的 administrator 密码(留空则随机): " "administrator"
      run_reinstall windows --image-name "Windows Server 2022 SERVERDATACENTER" --lang zh-cn "${PASSWORD_ARGS[@]}"
      ;;

    51)
      read -r -p "请输入 Raw/VHD 镜像链接: " img_url
      if [ -z "$img_url" ]; then
        echo "镜像链接不能为空"
        exit 1
      fi
      run_reinstall dd --img "$img_url"
      ;;
    52)
      read_password_args "请输入 Alpine Live OS 的 root 密码(留空则随机): " "root"
      run_reinstall alpine --hold 1 "${PASSWORD_ARGS[@]}"
      ;;
    53)
      run_reinstall netboot.xyz
      ;;
    54)
      install_basic_tools
      download_reinstall_script
      cd "$WORK_DIR"
      bash "$SCRIPT_PATH" reset
      ;;
    0)
      echo "已退出"
      exit 0
      ;;
    *)
      echo "无效选择"
      exit 1
      ;;
  esac
}

main "$@"
