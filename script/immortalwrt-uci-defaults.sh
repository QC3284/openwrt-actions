#!/bin/sh

# https://github.com/QC3284/openwrt-actions
#
# Copyright (c) 2024-2026 QC3284 <https://www.xcqcoo.top>
#
# This is free software, licensed under the GNU GPLv3 License.
# See /LICENSE for more information.

# ImmortalWrt uci-defaults 自定义脚本 (首次启动时自动执行)
#   - sed, grep, mv, cp, mkdir, chmod, rm, cat (busybox)
#   - [ -x / -f / -d ] (busybox test)
#   - 不依赖 bash 扩展，不依赖 GNU sed，不依赖 awk

# 1. 修改默认 LAN IP，避免与主路由冲突 (CIDR 格式适配 OpenWrt 21.02+)
uci set network.lan.ipaddr='192.168.5.2/24'
uci commit network

# 2. SSH: 将 dropbear 替换为 openssh-server (确认 sshd 已安装后才禁用 dropbear)
if [ -x /etc/init.d/sshd ]; then
  if [ -x /etc/init.d/dropbear ]; then
    /etc/init.d/dropbear disable 2>/dev/null
    /etc/init.d/dropbear stop 2>/dev/null
  fi
  /etc/init.d/sshd enable 2>/dev/null

  # 迁移 dropbear 密钥与 authorized_keys 至 OpenSSH 目录
  mkdir -p /root/.ssh
  if [ -d /etc/dropbear ]; then
    for item in /etc/dropbear/*; do
      [ -f "$item" ] && cp "$item" /root/.ssh/ 2>/dev/null
    done
  fi
fi

# 3. 生成 mirrors.sh: 将所有软件源替换为自定义镜像
#    使用占位符技巧避免 sed 重复替换，同时兼容 busybox sed (含/不含 -r)
cat << 'SCRIPT_EOF' > /root/mirrors.sh
#!/bin/sh
# 替换所有软件源为自定义镜像 (与官方源路径一致)
# 兼容 opkg (24.10 及更早) 和 apk (25.12 及更新)
MIRROR="https://dl-esa-cn-1-immortalwrt.3284123.xyz"

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
       -e "s@__M__@${MIRROR}/@g" \
       "$f" > "$t" 2>/dev/null; then
    :
  else
    # busybox 不支持 -r 时回退：多次匹配但不重复处理
    sed \
      -e "s@https\?://[^/]*/openwrt/@__M__@g" \
      -e "s@https\?://[^/]*/immortalwrt/@__M__@g" \
      -e "s@https\?://[^/]*/lede/@__M__@g" \
      -e "s@https\?://[^/]*/@__M__@g" \
      -e "s@__M__@${MIRROR}/@g" \
      "$f" > "$t"
  fi
  mv "$t" "$f" && echo "已更新: $f"
  rm -f "$t"
}

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

echo "所有软件源已切换至 ${MIRROR}"
SCRIPT_EOF

chmod +x /root/mirrors.sh

exit 0
