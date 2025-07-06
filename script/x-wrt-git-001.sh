#!/bin/bash
#本仓库及文件只在Github发布
#作者：QC3284@github.com(https://github.com/QC3284)
#本仓库地址：https://github.com/QC3284/openwrt-actions
#最后更新时间：2025.4.26
git clone https://github.com/kiddin9/kwrt-packages.git opldf
sleep 2
sudo rm -rf package/utils/coremark
cp -r opldf/coremark package/utils/
echo "Done"
sleep 3
sudo rm -rf opldf