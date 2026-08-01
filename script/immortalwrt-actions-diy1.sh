#!/usr/bin/env bash

# https://github.com/QC3284/openwrt-actions
#
# Copyright (c) 2024-2026 QC3284 <https://www.xcqcoo.top>
#
# This is free software, licensed under the GNU GPLv3 License.
# See /LICENSE for more information.

set -e

# 用途：feeds update 之前执行的 DIY 脚本 (在 Build-immortalwrt.yml 中调用)
# 功能：克隆第三方软件包到源码树，供后续编译使用
git clone -b master --single-branch --filter=blob:none https://github.com/vernesong/OpenClash p-temp/clash || { echo "警告: OpenClash 克隆失败"; }
# 文件管理插件 quickfile
git clone --depth 1 https://github.com/sbwml/luci-app-quickfile package/quickfile || { echo "警告: quickfile 克隆失败"; }
# proton2025 主题
git clone --depth 1 https://github.com/ChesterGoodiny/luci-theme-proton2025 package/luci-theme-proton2025 || { echo "警告: proton2025 克隆失败"; }
# RUN 安装工具
git clone --depth 1 https://github.com/wukongdaily/luci-app-run package/luci-app-run || { echo "警告: luci-app-run 克隆失败"; }

exit 0
