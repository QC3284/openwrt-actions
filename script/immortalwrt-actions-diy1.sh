#!/bin/bash

# https://github.com/QC3284/openwrt-actions
#
# Copyright (c) 2024-2026 QC3284 <https://www.xcqcoo.top>
#
# This is free software, licensed under the GNU GPLv3 License.
# See /LICENSE for more information.

# 用途：feeds update 之前执行的 DIY 脚本 (在 Build-immortalwrt.yml 中调用)
# 功能：克隆第三方软件包到源码树，供后续编译使用
git clone -b master --single-branch --filter=blob:none https://github.com/vernesong/OpenClash p-temp/clash
# 文件管理插件 quickfile
git clone https://github.com/sbwml/luci-app-quickfile package/quickfile
# proton2025 主题
git clone https://github.com/ChesterGoodiny/luci-theme-proton2025 package/luci-theme-proton2025
# RUN 安装工具
git clone https://github.com/wukongdaily/luci-app-run package/luci-app-run

exit 0
