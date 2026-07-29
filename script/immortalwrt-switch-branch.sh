#!/bin/bash

# https://github.com/QC3284/openwrt-actions
#
# Copyright (c) 2024-2026 QC3284 <https://www.xcqcoo.top>
#
# This is free software, licensed under the GNU GPLv3 License.
# See /LICENSE for more information.

# 用法: bash immortalwrt-switch-branch.sh <设备名> [源码目录] [配置文件]

set -e

DEVICE="${1:-$DEVICE_NAME}"
REPO_DIR="${2:-${OPENWRT_DIR:-.}}"
BRANCH_FILE="${3:-$(dirname "$0")/../config/immortalwrt-device-branch.txt}"
DEFAULT_BRANCH_FILE="${4:-$(dirname "$0")/../config/immortalwrt-default-branch.txt}"
DEFAULT_BRANCH="25.12"
if [ -f "$DEFAULT_BRANCH_FILE" ]; then
  PARSED=$(head -1 "$DEFAULT_BRANCH_FILE" | tr -d '[:space:]')
  [ -n "$PARSED" ] && DEFAULT_BRANCH="$PARSED"
fi
echo "默认分支: $DEFAULT_BRANCH"

if [ -z "$DEVICE" ]; then
  echo "错误: 未指定设备名 (参数1 或环境变量 DEVICE_NAME)"
  exit 1
fi

BRANCH="$DEFAULT_BRANCH"
if [ -f "$BRANCH_FILE" ]; then
  MATCH=$(grep -v '^[[:space:]]*#' "$BRANCH_FILE" | awk -v dev="$DEVICE" '$1 == dev {print $2; exit}')
  if [ -n "$MATCH" ]; then
    BRANCH="$MATCH"
    echo "设备 [$DEVICE] 在配置文件中，使用分支: $BRANCH"
  else
    echo "设备 [$DEVICE] 未在配置文件中，使用默认分支: $BRANCH"
  fi
else
  echo "警告: 配置文件不存在 ($BRANCH_FILE)，使用默认分支: $BRANCH"
fi

cd "$REPO_DIR"

# 从仓库 URL 提取源地址 (如 /workdir/openwrt 中的 origin remote)
SOURCE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -n "$SOURCE_URL" ]; then
  REMOTE_SHA=$(git ls-remote "$SOURCE_URL" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
  if [ -z "$REMOTE_SHA" ]; then
    echo "错误: 远端分支 $BRANCH 不存在于 $SOURCE_URL"
    echo "回退到默认分支: $DEFAULT_BRANCH"
    BRANCH="$DEFAULT_BRANCH"
    REMOTE_SHA=$(git ls-remote "$SOURCE_URL" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
    [ -z "$REMOTE_SHA" ] && { echo "严重错误: 默认分支 $BRANCH 也不存在"; exit 1; }
  fi
fi

git fetch origin "$BRANCH"
git checkout -B "$BRANCH" "origin/$BRANCH"
git reset --hard "origin/$BRANCH"

echo "当前分支: $(git branch --show-current)"

exit 0
