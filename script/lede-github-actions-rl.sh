#!/bin/bash
# https://github.com/QC3284/openwrt-actions
#
# Copyright (c) 2024-2026 QC3284 <https://www.xcqcoo.top>
#
# This is free software, licensed under the GNU GPLv3 License.
# See /LICENSE for more information.
# 用途：生成 lede 编译产物的 Release 说明文件 (release.txt)
echo "自动编译 (Automatic compilation)" >> release.txt
echo "使用源码 (Use source code)：" >> release.txt
echo "[lede](https://github.com/coolsnowwolf/lede)" >> release.txt
echo "$(date)" >> release.txt