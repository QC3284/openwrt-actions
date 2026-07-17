#!/bin/bash
# 用途：feeds update 之后、feeds install 之前执行的 DIY 脚本 (在 Build-immortalwrt.yml 中调用)
# 功能：用 diy1.sh 克隆的 OpenClash 替换 feeds 中自带的旧版本
# 本仓库地址：https://github.com/QC3284/openwrt-actions

# 删除 feeds 自带的 luci-app-openclash，替换为最新版
rm -rf feeds/luci/applications/luci-app-openclash
mv p-temp/clash/luci-app-openclash feeds/luci/applications/luci-app-openclash
# 清理临时目录
rm -rf p-temp

exit 0
