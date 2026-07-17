#!/bin/bash
#本仓库及文件只在Github发布
#作者：QC3284@github.com(https://github.com/QC3284)
#本仓库地址：https://github.com/QC3284/openwrt-actions
#最后更新时间：2024.12.08
# 用途：修改固件默认管理 IP (192.168.1.1 -> 192.168.5.1)，避免与主路由冲突
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate
sleep 3