#!/bin/bash
# https://github.com/QC3284/openwrt-actions
#
# Copyright (c) 2024-2026 QC3284 <https://www.xcqcoo.top>
#
# This is free software, licensed under the GNU GPLv3 License.
# See /LICENSE for more information.
# 用途：修改固件默认管理 IP (192.168.1.1 -> 192.168.5.1)，避免与主路由冲突
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate
sleep 3