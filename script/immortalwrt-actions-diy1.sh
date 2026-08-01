#!/usr/bin/env bash
# File: immortalwrt-actions-diy1.sh — feeds update 前克隆第三方插件 (支持按设备控制)
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/openwrt-actions

set -e

DEVICE="${1:-}"

# 各插件定义为函数，方便按设备开关
plugin_clash()    { git clone -b master --single-branch --filter=blob:none https://github.com/vernesong/OpenClash p-temp/clash || { echo "警告: OpenClash 克隆失败"; }; }
plugin_quickfile(){ git clone --depth 1 https://github.com/sbwml/luci-app-quickfile package/quickfile || { echo "警告: quickfile 克隆失败"; }; }
plugin_proton()   { git clone --depth 1 https://github.com/ChesterGoodiny/luci-theme-proton2025 package/luci-theme-proton2025 || { echo "警告: proton2025 克隆失败"; }; }
plugin_run()      { git clone --depth 1 https://github.com/wukongdaily/luci-app-run package/luci-app-run || { echo "警告: luci-app-run 克隆失败"; }; }

echo "DIY 设备: ${DEVICE:-未指定 (全部启用)}"

# 按设备选择插件组 (default 匹配未知设备，启用全部)
case "$DEVICE" in
  glinet_gl-mt3000)   plugin_clash; plugin_quickfile; plugin_proton; plugin_run ;;
  konka_komi-a31)     plugin_clash; plugin_quickfile; plugin_proton; plugin_run ;;
  glinet_gl-mt3600be) plugin_quickfile; plugin_run ;;  # wifi7 暂不启用 OpenClash
  *)                  plugin_clash; plugin_quickfile; plugin_proton; plugin_run ;;
esac

exit 0
