#!/bin/bash
# https://github.com/QC3284/openwrt-actions
#
# Copyright (c) 2024-2026 QC3284 <https://www.xcqcoo.top>
#
# This is free software, licensed under the GNU GPLv3 License.
# See /LICENSE for more information.

set -o pipefail

# 用途：编译前预下载所有依赖源码包 (make download)，并清理下载不完整的文件
THREADS=$(nproc 2>/dev/null || echo 8)
echo "使用 $THREADS 线程下载依赖包..."

make download -j$THREADS 2>&1 | tee make_download.log
DOWNLOAD_EXIT=${PIPESTATUS[0]}
sleep 2

if [ $DOWNLOAD_EXIT -ne 0 ]; then
  echo "警告: make download 退出码 $DOWNLOAD_EXIT，部分包可能下载失败"
  echo "将在编译时自动重试下载"
fi

# 列出并删除小于 1KB 的文件 (通常为下载失败的残缺包)，以便编译时自动重新下载
find dl -size -1024c -exec ls -l {} \; 2>/dev/null || true
find dl -size -1024c -exec rm -f {} \; 2>/dev/null || true
sleep 3