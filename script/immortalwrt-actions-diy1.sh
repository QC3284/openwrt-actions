#!/bin/bash
# 用途：feeds update 之前执行的 DIY 脚本 (在 Build-immortalwrt.yml 中调用)
# 功能：克隆第三方软件包到源码树，供后续编译使用
# 本仓库地址：https://github.com/QC3284/openwrt-actions

# 克隆 OpenClash (仅取 master 分支，blob:none 减少下载量)，暂存到 p-temp，由 diy2.sh 移入 feeds
git clone -b master --single-branch --filter=blob:none https://github.com/vernesong/OpenClash p-temp/clash
# 文件管理插件 quickfile
git clone https://github.com/sbwml/luci-app-quickfile package/quickfile
# proton2025 主题
git clone https://github.com/ChesterGoodiny/luci-theme-proton2025 package/luci-theme-proton2025
# RUN 安装工具
git clone https://github.com/wukongdaily/luci-app-run package/luci-app-run

exit 0
