#!/usr/bin/env bash
# File: immortalwrt-actions-diy2.sh — feeds update 后替换 OpenClash
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/immortalwrt-actions

set -euo pipefail

# 用途：feeds update 之后、feeds install 之前执行的 DIY 脚本 (在 Build-immortalwrt.yml 中调用)
# 功能：用 diy1.sh 克隆的官方最新版 OpenClash 替换 feeds 中自带的旧版本。
# 强制替换：缺源、目录结构异常或版本与 diy1 探测结果不一致都硬失败，
# 绝不静默回退到 feeds 自带旧版。
OVERLAY="p-temp/clash/luci-app-openclash"
TARGET="feeds/luci/applications/luci-app-openclash"

if [ ! -f "$OVERLAY/Makefile" ]; then
  echo "错误: 未找到 $OVERLAY/Makefile (diy1.sh 未成功克隆 OpenClash)，拒绝静默回退 feeds 旧版"
  exit 1
fi

rm -rf "$TARGET"
mv "$OVERLAY" "$TARGET"

REPLACED_VER=$(sed -n 's/^PKG_VERSION:=//p' "$TARGET/Makefile" 2>/dev/null | head -n 1)
if [ -z "$REPLACED_VER" ]; then
  echo "错误: 替换后的 OpenClash 缺少 PKG_VERSION (目录结构异常)"
  exit 1
fi
if [ -n "${OPENCLASH_VERSION:-}" ] && [ "$REPLACED_VER" != "$OPENCLASH_VERSION" ]; then
  echo "错误: 替换后版本 ($REPLACED_VER) 与 diy1 探测版本 ($OPENCLASH_VERSION) 不一致"
  exit 1
fi
echo "OpenClash 已强制替换为官方版本 $REPLACED_VER"

# 清理临时目录
if [ -d p-temp ]; then rm -rf p-temp; fi

exit 0
