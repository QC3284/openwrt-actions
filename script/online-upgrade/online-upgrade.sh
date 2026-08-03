#!/bin/sh
# =====================================================
# Online Upgrade Script — 适配 QC3284/openwrt-actions
# 从 GitHub Releases 列表自动查找设备对应固件
# =====================================================

CONFIG_FILE="/etc/config/online-upgrade"
get_uci() { uci -q get "online-upgrade.settings.$1" 2>/dev/null; }

REPO="$(get_uci repo)"
PROXY="$(get_uci proxy)"

[ -z "$REPO" ] && REPO="QC3284/openwrt-actions"
[ -z "$PROXY" ] && PROXY="https://ghfast.top/"

TMP_JSON="/tmp/release_list.json"
TMP_FW="/tmp/firmware.bin"
MODE="${1:-check}"

# ===== 设备识别 =====
get_device() {
  # 优先从 UCI 读取，否则自动检测
  local dev=$(get_uci device)
  [ -n "$dev" ] && { echo "$dev"; return; }
  # 从 /etc/board.json 读取
  dev=$(jsonfilter -e '@.model.id' < /etc/board.json 2>/dev/null | tr ',' '_' | tr '[:upper:]' '[:lower:]')
  [ -n "$dev" ] && { echo "$dev"; return; }
  # 回退：从 /proc/device-tree/compatible 读取第一个
  dev=$(cat /proc/device-tree/compatible 2>/dev/null | tr '\0' '\n' | tail -1 | tr ',' '_' | tr '[:upper:]' '[:lower:]')
  [ -n "$dev" ] && { echo "$dev"; return; }
  echo "unknown"
}

DEVICE="$(get_device)"
echo "========================================"
echo "  固件在线升级 (适配 openwrt-actions)"
echo "  仓库: ${REPO}"
echo "  设备: ${DEVICE}"
echo "========================================"

# ===== 获取最新 Release 列表 =====
fetch_releases() {
  local url="https://api.github.com/repos/${REPO}/releases?per_page=20"
  local http_code

  curl -sL -H "User-Agent: online-upgrade" -o "$TMP_JSON" -w "%{http_code}" "$url" 2>/dev/null
}

# ===== 查找设备对应的最新 Release =====
find_firmware() {
  local http_code=$(fetch_releases)
  local tag fw_url fw_name fw_date

  if [ "$http_code" != "200" ]; then
    # 直连失败，尝试代理
    local proxy_url="${PROXY}https://api.github.com/repos/${REPO}/releases?per_page=20"
    http_code=$(curl -sL -H "User-Agent: online-upgrade" -o "$TMP_JSON" -w "%{http_code}" "$proxy_url" 2>/dev/null)
  fi

  [ "$http_code" != "200" ] && { echo "错误: API 返回 HTTP $http_code"; return 1; }

  # 找到该设备最新的 release tag
  tag=$(jsonfilter -i "$TMP_JSON" -e '@[*].tag_name' 2>/dev/null | grep "^${DEVICE}-" | head -1)
  [ -z "$tag" ] && { echo "错误: 未找到设备 ${DEVICE} 的 Release"; return 1; }
  echo "  最新 Tag: ${tag}"

  # 找到 sysupgrade 固件
  fw_name=$(jsonfilter -i "$TMP_JSON" -e "@[@.tag_name=\"${tag}\"].assets[*].name" 2>/dev/null | grep "squashfs-sysupgrade" | grep -v "manifest" | head -1)
  [ -z "$fw_name" ] && { echo "错误: 未找到 sysupgrade 固件"; return 1; }
  echo "  固件: ${fw_name}"

  fw_url=$(jsonfilter -i "$TMP_JSON" -e "@[@.tag_name=\"${tag}\"].assets[@.name=\"${fw_name}\"].browser_download_url" 2>/dev/null)
  fw_date=$(jsonfilter -i "$TMP_JSON" -e "@[@.tag_name=\"${tag}\"].published_at" 2>/dev/null)

  echo "TAG=${tag}" > /tmp/.online-upgrade.env
  echo "FW_URL=${fw_url}" >> /tmp/.online-upgrade.env
  echo "FW_NAME=${fw_name}" >> /tmp/.online-upgrade.env
  echo "FW_DATE=${fw_date}" >> /tmp/.online-upgrade.env
  return 0
}

# ===== 版本对比 =====
is_newer() {
  local last_ts=$(get_uci last_upgrade_ts)
  . /tmp/.online-upgrade.env 2>/dev/null
  [ -z "$last_ts" ] && return 0  # 首次检测，认为有新固件
  [ "$FW_DATE" != "$last_ts" ] && return 0
  return 1
}

# ===== 检查模式 =====
if [ "$MODE" = "check" ] || [ "$MODE" = "status" ]; then
  find_firmware || exit 1
  if is_newer; then
    echo ""
    echo "  >>> 发现新固件！"
    echo "  升级: online-upgrade.sh upgrade"
  else
    echo ""
    echo "  已是最新。"
  fi
  rm -f "$TMP_JSON"
  exit 0
fi

# ===== 升级模式 =====
if [ "$MODE" = "upgrade" ]; then
  find_firmware || exit 1
  . /tmp/.online-upgrade.env

  if ! is_newer; then
    echo "已是最新，无需升级。"
    exit 0
  fi

  echo ""
  echo "========================================"
  echo "  [执行升级]"
  echo "========================================"

  # 下载
  echo "Step 1: 下载固件..."
  DOWNLOAD_URL="${PROXY}${FW_URL}"
  curl -sL -o "$TMP_FW" "$DOWNLOAD_URL" 2>&1
  if [ $? -ne 0 ] || [ ! -s "$TMP_FW" ]; then
    echo "错误: 下载失败"
    exit 1
  fi
  echo "  下载成功 ($(du -h "$TMP_FW" | cut -f1))"

  # 备份
  echo "Step 2: 创建配置备份..."
  TS=$(date +%Y%m%d-%H%M%S)
  BACKUP="/tmp/pre-upgrade-backup-${TS}.tar.gz"
  sysupgrade -b "$BACKUP"
  if [ $? -ne 0 ] || [ ! -s "$BACKUP" ]; then
    echo "错误: 备份失败"
    exit 1
  fi
  cp "$BACKUP" "/root/pre-upgrade-backup-${TS}.tar.gz"
  echo "  备份: /root/pre-upgrade-backup-${TS}.tar.gz"

  # 记录版本
  echo "Step 3: 记录版本..."
  uci set online-upgrade.settings.last_upgrade_ts="$FW_DATE"
  uci set online-upgrade.settings.last_upgrade_tag="$TAG"
  uci commit online-upgrade

  # 升级
  echo "Step 4: 执行 sysupgrade..."
  sync
  sleep 1
  /sbin/sysupgrade -f "$BACKUP" "$TMP_FW"

  # sysupgrade 失败
  uci -q delete online-upgrade.settings.last_upgrade_ts
  uci -q delete online-upgrade.settings.last_upgrade_tag
  uci commit online-upgrade
  exit 1
fi

# ===== 后台模式 =====
if [ "$MODE" = "background" ] || [ "$MODE" = "--bg" ]; then
  setsid /bin/sh "$0" "upgrade" </dev/null >/tmp/online-upgrade.log 2>&1 &
  echo "升级已在后台启动 (PID: $!)"
  exit 0
fi

echo "用法: online-upgrade.sh [check|upgrade|background]"
exit 1

# ===== IP 检测 =====
detect_region() {
  local cc
  cc=$(curl -s --connect-timeout 3 "http://ip-api.com/json/?fields=countryCode" 2>/dev/null | jsonfilter -e '@.countryCode' 2>/dev/null)
  [ "$cc" = "CN" ] && return 0 || return 1
}

# 国内强制启用代理
if detect_region; then
  echo "  检测到国内网络，强制启用代理"
  [ -z "$PROXY" ] && PROXY="https://ghfast.top/"
fi
