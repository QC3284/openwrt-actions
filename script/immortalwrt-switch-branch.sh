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
DEFAULT_BRANCH="25.12"

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
git fetch origin "$BRANCH"
git checkout -B "$BRANCH" "origin/$BRANCH"
git reset --hard "origin/$BRANCH"

echo "当前分支: $(git branch --show-current)"

exit 0
