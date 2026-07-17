#!/bin/bash
#本仓库及文件只在Github发布
#作者：QC3284@github.com(https://github.com/QC3284)
#本仓库地址：https://github.com/QC3284/openwrt-actions
#最后更新时间：2025.4.26
# 用途：用 kwrt-packages 仓库中的 coremark 替换源码自带版本 (修复编译问题)
git clone https://github.com/kiddin9/kwrt-packages.git opldf
sleep 2
# 删除源码自带的 coremark，替换为 kwrt 版本
sudo rm -rf package/utils/coremark
cp -r opldf/coremark package/utils/
echo "Done"
sleep 3
# 清理临时克隆目录
sudo rm -rf opldf