#!/bin/sh
# File: immortalwrt-uci-defaults.sh — 首次启动自动配置 (LAN IP / SSH / 换源)
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/openwrt-actions

# ImmortalWrt uci-defaults 自定义脚本 (首次启动时自动执行)
#   - sed, grep, mv, cp, mkdir, chmod, rm, cat (busybox)
#   - [ -x / -f / -d ] (busybox test)
#   - 不依赖 bash 扩展，不依赖 GNU sed，不依赖 awk

# ===== 可自定义配置 =====
LAN_IP="192.168.5.1/24"

# 1. 修改默认 LAN IP，避免与主路由冲突 (CIDR 格式适配 OpenWrt 21.02+)
uci set network.lan.ipaddr="${LAN_IP}"
uci commit network

# 2. SSH: 将 dropbear 替换为 openssh-server (确认 sshd 已安装后才禁用 dropbear)
if [ -x /etc/init.d/sshd ]; then
  if [ -x /etc/init.d/dropbear ]; then
    /etc/init.d/dropbear disable 2>/dev/null
    /etc/init.d/dropbear stop 2>/dev/null
    # 通过 uci 标记禁用 (确保 LuCI 同步状态)
    uci -q set dropbear.@dropbear[0].enabled='0' 2>/dev/null
    uci -q commit dropbear 2>/dev/null
  fi
  /etc/init.d/sshd enable 2>/dev/null

  # 允许 root 用户密码登录 (直接修改 sshd_config)
  sed -i -e 's/^[[:space:]]*#[[:space:]]*\(PermitRootLogin\)/\1/' -e 's/^[[:space:]]*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null
  grep -q '^PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
  # 使配置生效
  /etc/init.d/sshd restart 2>/dev/null

  # 迁移 dropbear 密钥与 authorized_keys 至 OpenSSH 目录
  mkdir -p /root/.ssh
  if [ -d /etc/dropbear ]; then
    for item in /etc/dropbear/*; do
      [ -f "$item" ] && cp "$item" /root/.ssh/ 2>/dev/null
    done
  fi
fi

# 3. 生成 mirrors.sh: 用户手动选择镜像源后替换
#    使用占位符技巧避免 sed 重复替换，同时兼容 busybox sed (含/不含 -r)
cat << 'SCRIPT_EOF' > /root/mirrors.sh
#!/bin/sh
# 交互式软件源镜像切换工具
# 兼容 opkg (24.10 及更早) 和 apk (25.12 及更新)

show_menu() {
  echo ""
  echo "========== 选择软件源镜像 =========="
  echo "1) 官方 ImmortalWrt (downloads.immortalwrt.org)"
  echo "2) 自定义镜像  (dl-esa-cn-1-immortalwrt.3284123.xyz)"
  echo "3) 中科大 USTC   (mirrors.ustc.edu.cn)"
  echo "4) 清华 TUNA    (mirrors.tuna.tsinghua.edu.cn)"
  echo "5) 阿里云        (mirrors.aliyun.com)"
  echo "6) 腾讯云        (mirrors.cloud.tencent.com)"
  echo "7) vsean         (mirrors.vsean.net)"
  echo "===================================="
}

select_mirror() {
  case "$1" in
    1) MIRROR="https://downloads.immortalwrt.org"; PREFIX="" ;;
    2|"") MIRROR="https://dl-esa-cn-1-immortalwrt.3284123.xyz"; PREFIX="" ;;
    3) MIRROR="https://mirrors.ustc.edu.cn"; PREFIX="/immortalwrt" ;;
    4) MIRROR="https://mirrors.tuna.tsinghua.edu.cn"; PREFIX="/immortalwrt" ;;
    5) MIRROR="https://mirrors.aliyun.com"; PREFIX="/openwrt" ;;
    6) MIRROR="https://mirrors.cloud.tencent.com"; PREFIX="/immortalwrt" ;;
    7) MIRROR="https://mirrors.vsean.net"; PREFIX="/openwrt" ;;
    *) echo "无效选择，使用自定义镜像 (2)" ; MIRROR="https://dl-esa-cn-1-immortalwrt.3284123.xyz"; PREFIX="" ;;
  esac
}

replace_mirror() {
  f="$1"
  t="$1.tmp"
  # 替换前备份 (仅首次)
  bak="${f}.bak"
  [ -f "$f" ] && [ ! -f "$bak" ] && cp "$f" "$bak"
  # 先用占位符 __M__ 替换所有远端 URL (避免结果被后续匹配再次替换)
  # 已知镜像路径前缀 /openwrt, /immortalwrt, /lede 会被去除
  if sed -r \
       -e "s@https?://[^/]+(/openwrt|/immortalwrt|/lede)?/@__M__@g" \
       -e "s@__M__@${MIRROR}${PREFIX}/@g" \
       "$f" > "$t" 2>/dev/null; then
    :
  else
    # busybox 不支持 -r 时回退：多次匹配但不重复处理
    sed \
      -e "s@https\?://[^/]*/openwrt/@__M__@g" \
      -e "s@https\?://[^/]*/immortalwrt/@__M__@g" \
      -e "s@https\?://[^/]*/lede/@__M__@g" \
      -e "s@https\?://[^/]*/@__M__@g" \
      -e "s@__M__@${MIRROR}${PREFIX}/@g" \
      "$f" > "$t"
  fi
  mv "$t" "$f" && echo "已更新: $f"
  rm -f "$t"
}

do_replace() {
  # opkg (24.10 及更早版本)
  for f in /etc/opkg/distfeeds.conf /etc/opkg/customfeeds.conf; do
    [ -f "$f" ] && replace_mirror "$f"
  done

  # apk (25.12 及更新版本) — 优先处理 repositories.d/ 目录，兼容单文件 repositories
  if [ -d /etc/apk/repositories.d ]; then
    for f in /etc/apk/repositories.d/*.list; do
      [ -f "$f" ] && replace_mirror "$f"
    done
  elif [ -f /etc/apk/repositories ]; then
    replace_mirror /etc/apk/repositories
  fi

  echo ""
  echo "所有软件源已切换至: ${MIRROR}${PREFIX}"
}

# 支持命令行参数直接指定 (如: mirrors.sh 2)
if [ -n "$1" ]; then
  select_mirror "$1"
  do_replace
  exit 0
fi

# 交互模式
show_menu
printf "请输入序号 [2]: "
read choice
select_mirror "$choice"
do_replace
SCRIPT_EOF

chmod +x /root/mirrors.sh

# 4. luci-app-quickfile 检测：如已安装，配置 nginx 以启用文件管理功能
if [ -f /usr/lib/lua/luci/controller/quickfile.lua ]; then
  if uci -q get nginx.global >/dev/null 2>&1; then
    uci set nginx.global.uci_enable='true'
    uci del nginx._lan 2>/dev/null
    uci del nginx._redirect2ssl 2>/dev/null
    uci add nginx server 2>/dev/null
    uci rename nginx.@server[0]='_lan' 2>/dev/null
    uci set nginx._lan.server_name='_lan'
    uci add_list nginx._lan.listen='80 default_server'
    uci add_list nginx._lan.listen='[::]:80 default_server'
    uci add_list nginx._lan.include='conf.d/*.locations'
    uci set nginx._lan.access_log='off; # logd openwrt'
    uci commit nginx
    service nginx restart
  fi
fi

# 5. 初始化 wget HSTS 文件 (部分固件 wget 不会自动创建，导致 https 下载异常)
[ ! -f /root/.wget-hsts ] && touch /root/.wget-hsts

exit 0
