#!/usr/bin/env bash
# File: immortalwrt-actions-diy2.sh — feeds update 后替换 OpenClash
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/openwrt-actions

set -e

# 用途：feeds update 之后、feeds install 之前执行的 DIY 脚本 (在 Build-immortalwrt.yml 中调用)
# 功能：用 diy1.sh 克隆的 OpenClash 替换 feeds 中自带的旧版本
if [ -d p-temp/clash/luci-app-openclash ]; then
  rm -rf feeds/luci/applications/luci-app-openclash
  mv p-temp/clash/luci-app-openclash feeds/luci/applications/luci-app-openclash
fi
# 清理临时目录
rm -rf p-temp

exit 0
