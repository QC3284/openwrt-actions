#!/usr/bin/env bash
# File: immortalwrt-switch-branch.sh — 按机型切换源码分支
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/openwrt-actions

# 用法: bash immortalwrt-switch-branch.sh <设备名> <源码目录> <设备分支文件> [默认分支文件] [显式分支]
#   显式分支: 可选，指定后跳过配置文件查找直接使用该分支 (但仍做远端存在性校验)

set -euo pipefail

DEVICE="${1:-$DEVICE_NAME}"
REPO_DIR="${2:-${OPENWRT_DIR:-.}}"

# 确定仓库根目录: 优先使用 GITHUB_WORKSPACE，其次基于脚本位置推导
if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d "$GITHUB_WORKSPACE/config" ]; then
  ROOT_DIR="$GITHUB_WORKSPACE"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT_DIR="${SCRIPT_DIR}/.."
fi

BRANCH_FILE="${3:-$ROOT_DIR/config/immortalwrt-device-branch.txt}"
DEFAULT_BRANCH_FILE="${4:-$ROOT_DIR/config/immortalwrt-default-branch.txt}"
EXPLICIT_BRANCH="${5:-}"
if [ ! -f "$DEFAULT_BRANCH_FILE" ]; then
  echo "错误: 默认分支配置文件不存在: $DEFAULT_BRANCH_FILE"
  exit 1
fi
DEFAULT_BRANCH=$(head -1 "$DEFAULT_BRANCH_FILE" | tr -d '[:space:]')
[ -n "$DEFAULT_BRANCH" ] || { echo "错误: 默认分支配置为空"; exit 1; }
echo "默认分支: $DEFAULT_BRANCH"

if [ -z "$DEVICE" ]; then
  echo "错误: 未指定设备名 (参数1 或环境变量 DEVICE_NAME)"
  exit 1
fi

if [ -n "$EXPLICIT_BRANCH" ]; then
  BRANCH="$EXPLICIT_BRANCH"
  echo "使用显式指定的分支: $BRANCH"
elif [ -f "$BRANCH_FILE" ]; then
  BRANCH="$DEFAULT_BRANCH"
  # || true: 分支文件全为注释时 grep 退出码 1，set -euo pipefail 会终止脚本而非回退默认分支
  MATCH=$(grep -v '^[[:space:]]*#' "$BRANCH_FILE" | awk -v dev="$DEVICE" '$1 == dev {print $2; exit}' || true)
  if [ -n "$MATCH" ]; then
    BRANCH="$MATCH"
    echo "设备 [$DEVICE] 在配置文件中，使用分支: $BRANCH"
  else
    echo "设备 [$DEVICE] 未在配置文件中，使用默认分支: $BRANCH"
  fi
else
  BRANCH="$DEFAULT_BRANCH"
  echo "警告: 配置文件不存在 ($BRANCH_FILE)，使用默认分支: $BRANCH"
fi

cd "$REPO_DIR"

# 从仓库 URL 提取源地址 (如 /workdir/openwrt 中的 origin remote)
SOURCE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -n "$SOURCE_URL" ]; then
  # || true: ls-remote 网络失败时进入下方回退逻辑，而非被 set -euo pipefail 直接终止
  REMOTE_SHA=$(git ls-remote "$SOURCE_URL" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}' || true)
  if [ -z "$REMOTE_SHA" ]; then
    echo "错误: 远端分支 $BRANCH 不存在于 $SOURCE_URL"
    echo "回退到默认分支: $DEFAULT_BRANCH"
    BRANCH="$DEFAULT_BRANCH"
    REMOTE_SHA=$(git ls-remote "$SOURCE_URL" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}' || true)
    [ -z "$REMOTE_SHA" ] && { echo "严重错误: 默认分支 $BRANCH 也不存在"; exit 1; }
  fi
fi

git fetch origin "$BRANCH"
git checkout -B "$BRANCH" "origin/$BRANCH"

echo "当前分支: $(git branch --show-current)"

exit 0
