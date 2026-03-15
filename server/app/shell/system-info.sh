#!/usr/bin/env bash

set -u

get_public_json() {
  curl -fsSL --max-time 5 https://ipinfo.io/json 2>/dev/null || true
}

get_public_ipv4() {
  local ip
  ip=$(curl -fsSL --max-time 5 https://ipinfo.io/ip 2>/dev/null | tr -d '\r') || true
  printf '%s' "$ip"
}

get_public_ipv6() {
  local ip
  ip=$(curl -fsSL --max-time 5 https://v6.ipinfo.io/ip 2>/dev/null | tr -d '\r') || true
  printf '%s' "$ip"
}

json_get() {
  local key="$1"
  awk -F': ' -v k="\"$key\"" '$1 ~ k {gsub(/^[[:space:]]+|,$/, "", $2); gsub(/^"|"$/, "", $2); print $2; exit}'
}

format_bytes_human() {
  awk -v bytes="${1:-0}" 'BEGIN {
    split("B K M G T P", u, " ");
    v = bytes + 0;
    i = 1;
    while (v >= 1024 && i < 6) {
      v /= 1024;
      i++;
    }
    if (i == 1) {
      printf "%d%s", v, u[i];
    } else {
      printf "%.2f%s", v, u[i];
    }
  }'
}

format_bytes_compact() {
  awk -v bytes="${1:-0}" 'BEGIN {
    split("B K M G T P", u, " ");
    v = bytes + 0;
    i = 1;
    while (v >= 1024 && i < 6) {
      v /= 1024;
      i++;
    }
    if (i == 1) {
      printf "%d%s", v, u[i];
    } else if (v >= 100) {
      printf "%.0f%s", v, u[i];
    } else if (v >= 10) {
      printf "%.1f%s", v, u[i];
    } else {
      printf "%.2f%s", v, u[i];
    }
  }'
}

format_mem_usage() {
  awk -v used_b="$1" -v total_b="$2" 'BEGIN {
    used = used_b / 1024 / 1024;
    total = total_b / 1024 / 1024;
    pct = (total_b > 0 ? used_b * 100 / total_b : 0);
    printf "%.2f/%.2fM (%.2f%%)", used, total, pct;
  }'
}

format_swap_usage() {
  awk -v used_m="$1" -v total_m="$2" 'BEGIN {
    pct = (total_m > 0 ? used_m * 100 / total_m : 0);
    if (used_m == int(used_m) && total_m == int(total_m)) {
      printf "%dM/%dM (%.0f%%)", used_m, total_m, pct;
    } else {
      printf "%.2fM/%.2fM (%.2f%%)", used_m, total_m, pct;
    }
  }'
}

format_uptime_cn() {
  local total seconds days hours minutes
  total=$(cut -d. -f1 /proc/uptime 2>/dev/null)
  total=${total:-0}
  days=$((total / 86400))
  hours=$(((total % 86400) / 3600))
  minutes=$(((total % 3600) / 60))

  if [ "$days" -gt 0 ]; then
    printf '%d天%d时%d分' "$days" "$hours" "$minutes"
  elif [ "$hours" -gt 0 ]; then
    printf '%d时%d分' "$hours" "$minutes"
  else
    printf '%d分' "$minutes"
  fi
}

get_cpu_usage_percent() {
  local a b
  a=$(grep '^cpu ' /proc/stat)
  sleep 1
  b=$(grep '^cpu ' /proc/stat)
  awk -v A="$a" -v B="$b" 'BEGIN {
    split(A, x, " ");
    split(B, y, " ");
    idle1 = x[5] + x[6];
    idle2 = y[5] + y[6];
    total1 = 0;
    total2 = 0;
    for (i = 2; i <= 11; i++) {
      total1 += x[i];
      total2 += y[i];
    }
    diff_total = total2 - total1;
    diff_idle = idle2 - idle1;
    usage = (diff_total > 0 ? (diff_total - diff_idle) * 100 / diff_total : 0);
    printf "%.0f", usage;
  }'
}

get_total_traffic() {
  awk 'BEGIN {rx=0; tx=0}
    NR > 2 {
      gsub(":", "", $1);
      if ($1 != "lo") {
        rx += $2;
        tx += $10;
      }
    }
    END {printf "%s %s", rx, tx}' /proc/net/dev
}

get_dns_servers() {
  awk '/^nameserver[[:space:]]+/ {printf "%s ", $2} END {print ""}' /etc/resolv.conf 2>/dev/null
}

get_disk_usage() {
  df -B1 / 2>/dev/null | awk 'NR==2 {
    used=$3; total=$2; pct=(total>0?used*100/total:0);
    split("B K M G T P", u, " ");
    uv=used; tv=total; ui=1; ti=1;
    while (uv>=1024 && ui<6) {uv/=1024; ui++}
    while (tv>=1024 && ti<6) {tv/=1024; ti++}
    uf=(ui==1?sprintf("%d%s", uv, u[ui]):(uv>=100?sprintf("%.0f%s", uv, u[ui]):(uv>=10?sprintf("%.1f%s", uv, u[ui]):sprintf("%.2f%s", uv, u[ui]))));
    tf=(ti==1?sprintf("%d%s", tv, u[ti]):(tv>=100?sprintf("%.0f%s", tv, u[ti]):(tv>=10?sprintf("%.1f%s", tv, u[ti]):sprintf("%.2f%s", tv, u[ti]))));
    printf "%s/%s (%.0f%%)", uf, tf, pct;
  }'
}

main() {
  local hostname os_info kernel_version cpu_arch cpu_model cpu_cores cpu_freq
  local cpu_usage load_avg tcp_count udp_count mem_total mem_available mem_used
  local swap_total swap_used disk_info rx tx congestion_algorithm queue_algorithm
  local ipinfo isp_info ipv4_address ipv6_address dns_addresses country city timezone current_time runtime

  hostname=$(hostname 2>/dev/null || uname -n)
  os_info=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')
  kernel_version=$(uname -r 2>/dev/null)
  cpu_arch=$(uname -m 2>/dev/null)
  cpu_model=$(awk -F': *' '/^Model name:/{print $2; exit}' < <(lscpu 2>/dev/null))
  [ -n "$cpu_model" ] || cpu_model=$(awk -F': *' '/^model name[[:space:]]*:/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
  cpu_cores=$(nproc 2>/dev/null)
  cpu_freq=$(awk -F': *' '/^CPU max MHz:/{printf "%.1f GHz", $2/1000; found=1; exit}
                   /^CPU MHz:/{printf "%.1f GHz", $2/1000; found=1; exit}
                   END{if (!found) exit 1}' < <(lscpu 2>/dev/null) 2>/dev/null)
  [ -n "$cpu_freq" ] || cpu_freq=$(awk -F': *' '/^cpu MHz[[:space:]]*:/{printf "%.1f GHz", $2/1000; exit}' /proc/cpuinfo 2>/dev/null)
  [ -n "$cpu_freq" ] || cpu_freq="N/A"

  cpu_usage=$(get_cpu_usage_percent)
  load_avg=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null)
  tcp_count=$(ss -tanH 2>/dev/null | wc -l | awk '{print $1}')
  udp_count=$(ss -uanH 2>/dev/null | wc -l | awk '{print $1}')

  mem_total=$(awk '/MemTotal:/ {print $2*1024; exit}' /proc/meminfo 2>/dev/null)
  mem_available=$(awk '/MemAvailable:/ {print $2*1024; exit}' /proc/meminfo 2>/dev/null)
  mem_total=${mem_total:-0}
  mem_available=${mem_available:-0}
  mem_used=$((mem_total - mem_available))

  swap_total=$(free -m 2>/dev/null | awk 'NR==3{print $2}')
  swap_used=$(free -m 2>/dev/null | awk 'NR==3{print $3}')
  swap_total=${swap_total:-0}
  swap_used=${swap_used:-0}

  disk_info=$(get_disk_usage)

  read -r rx tx <<< "$(get_total_traffic)"
  rx=$(format_bytes_compact "${rx:-0}")
  tx=$(format_bytes_compact "${tx:-0}")

  congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")
  queue_algorithm=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "N/A")

  ipinfo=$(get_public_json)
  isp_info=$(printf '%s
' "$ipinfo" | json_get org)
  ipv4_address=$(get_public_ipv4)
  ipv6_address=$(get_public_ipv6)
  dns_addresses=$(get_dns_servers)
  country=$(printf '%s
' "$ipinfo" | json_get country)
  city=$(printf '%s
' "$ipinfo" | json_get city)

  timezone=$(timedatectl show --property=Timezone --value 2>/dev/null)
  [ -n "$timezone" ] || timezone=$(readlink /etc/localtime 2>/dev/null | sed 's#^.*/zoneinfo/##')
  [ -n "$timezone" ] || timezone=$(date +%Z)
  current_time=$(date '+%Y-%m-%d %I:%M %p')
  runtime=$(format_uptime_cn)

  echo "-------------"
  printf "%-16s %s\n" "主机名:" "$hostname"
  printf "%-16s %s\n" "系统版本:" "$os_info"
  printf "%-16s %s\n" "Linux版本:" "$kernel_version"
  echo "-------------"
  printf "%-16s %s\n" "CPU架构:" "$cpu_arch"
  printf "%-16s %s\n" "CPU型号:" "$cpu_model"
  printf "%-16s %s\n" "CPU核心数:" "$cpu_cores"
  printf "%-16s %s\n" "CPU频率:" "$cpu_freq"
  echo "-------------"
  printf "%-16s %s%%\n" "CPU占用:" "$cpu_usage"
  printf "%-16s %s\n" "系统负载:" "$load_avg"
  printf "%-16s %s|%s\n" "TCP|UDP连接数:" "$tcp_count" "$udp_count"
  printf "%-16s %s\n" "物理内存:" "$(format_mem_usage "$mem_used" "$mem_total")"
  printf "%-16s %s\n" "虚拟内存:" "$(format_swap_usage "$swap_used" "$swap_total")"
  printf "%-16s %s\n" "硬盘占用:" "$disk_info"
  echo "-------------"
  printf "%-16s %s\n" "总接收:" "$rx"
  printf "%-16s %s\n" "总发送:" "$tx"
  echo "-------------"
  printf "%-16s %s %s\n" "网络算法:" "$congestion_algorithm" "$queue_algorithm"
  echo "-------------"
  printf "%-16s %s\n" "运营商:" "$isp_info"
  printf "%-16s %s\n" "IPv4地址:" "$ipv4_address"
  printf "%-16s %s\n" "IPv6地址:" "$ipv6_address"
  printf "%-16s %s\n" "DNS地址:" "$dns_addresses"
  printf "%-16s %s %s\n" "地理位置:" "$country" "$city"
  printf "%-16s %s %s\n" "系统时间:" "$timezone" "$current_time"
  echo "-------------"
  printf "%-16s %s\n" "运行时长:" "$runtime"
}

main "$@"
