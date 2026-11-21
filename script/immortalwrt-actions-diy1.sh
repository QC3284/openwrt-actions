#!/usr/bin/env bash
# File: immortalwrt-actions-diy1.sh — feeds update 前克隆第三方插件
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/immortalwrt-actions

set -euo pipefail

# 用途：feeds update 之前执行的 DIY 脚本 (在 Build-immortalwrt.yml 中调用)
# 功能：克隆第三方软件包到源码树，供后续编译使用
# 注意: p-temp 临时目录由 diy2.sh 负责清理，此处不可清理

# ---------------- OpenClash：强制使用官方最新版（含测试版） ----------------
# 上游 vernesong/OpenClash 同时维护 master(稳定) 与 dev(测试) 两条线，版本号各自推进。
# 这里不写死分支：分别探测两条线 Makefile 的 PKG_VERSION，取更高者 —— 测试版更新时
# 自动跟测试版，稳定版反超时自动回到稳定版。两条线都拿不到就硬失败，
# 绝不静默退回 feeds 自带的旧版本。
OPENCLASH_REPO="https://github.com/vernesong/OpenClash"

probe_openclash_version() {
  local branch="$1" dir="$2" ver
  rm -rf "$dir"
  git clone --depth 1 --single-branch --branch "$branch" --filter=blob:none \
    "$OPENCLASH_REPO" "$dir" >/dev/null 2>&1 || return 1
  ver=$(sed -n 's/^PKG_VERSION:=//p' "$dir/luci-app-openclash/Makefile" 2>/dev/null | head -n 1)
  [ -n "$ver" ] || return 1
  printf '%s' "$ver"
}

STABLE_VER=$(probe_openclash_version master p-temp/clash-stable || true)
BETA_VER=$(probe_openclash_version dev p-temp/clash-dev || true)
[ -n "$STABLE_VER" ] || echo "警告: 未能探测 OpenClash master 分支版本"
[ -n "$BETA_VER" ] || echo "警告: 未能探测 OpenClash dev 分支版本"

LATEST_VER=""
if [ -n "$STABLE_VER" ] && [ -n "$BETA_VER" ]; then
  LATEST_VER=$(printf '%s\n%s\n' "$STABLE_VER" "$BETA_VER" | sort -V | tail -n 1)
elif [ -n "$BETA_VER" ]; then
  LATEST_VER="$BETA_VER"
elif [ -n "$STABLE_VER" ]; then
  LATEST_VER="$STABLE_VER"
fi

if [ -z "$LATEST_VER" ]; then
  echo "错误: OpenClash 官方仓库 master/dev 均无法获取，拒绝回退到 feeds 旧版本"
  exit 1
fi

if [ "$LATEST_VER" = "$BETA_VER" ]; then
  CHOSEN_BRANCH="dev"
  CHOSEN_DIR="p-temp/clash-dev"
else
  CHOSEN_BRANCH="master"
  CHOSEN_DIR="p-temp/clash-stable"
fi
rm -rf p-temp/clash
mv "$CHOSEN_DIR" p-temp/clash
rm -rf p-temp/clash-stable p-temp/clash-dev

echo "OpenClash: 选用 $CHOSEN_BRANCH 分支，PKG_VERSION=$LATEST_VER (master=$STABLE_VER, dev=$BETA_VER)"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### OpenClash 依赖版本"
    echo "- 分支: $CHOSEN_BRANCH"
    echo "- PKG_VERSION: $LATEST_VER"
    echo "- 上游: $OPENCLASH_REPO"
  } >> "$GITHUB_STEP_SUMMARY"
fi
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "OPENCLASH_VERSION=$LATEST_VER" >> "$GITHUB_ENV"
fi

# 文件管理插件 quickfile
git clone --depth 1 https://github.com/sbwml/luci-app-quickfile package/quickfile || { echo "警告: quickfile 克隆失败"; }
# harbor 文件管理
git clone --depth 1 https://github.com/destan19/luci-app-harbor-file package/harbor-file || { echo "警告: harbor-file 克隆失败"; }
# proton2025 主题
git clone --depth 1 https://github.com/ChesterGoodiny/luci-theme-proton2025 package/luci-theme-proton2025 || { echo "警告: proton2025 克隆失败"; }
# RUN 安装工具
git clone --depth 1 https://github.com/wukongdaily/luci-app-run package/luci-app-run || { echo "警告: luci-app-run 克隆失败"; }
# 在线升级 (v2.0.0 已适配本项目 multi-device releases)
git clone --depth 1 https://github.com/QC3284/luci-app-online-upgrade package/luci-app-online-upgrade || { echo "警告: online-upgrade 克隆失败"; }

exit 0
