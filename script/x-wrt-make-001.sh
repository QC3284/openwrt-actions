#!/bin/bash
#本仓库及文件只在Github发布
#作者：QC3284@github.com(https://github.com/QC3284)
#本仓库地址：https://github.com/QC3284/openwrt-actions
#最后更新时间：2024.11.30
make download -j8 2>&1 | tee make_download.log
sleep 2
find dl -size -1024c -exec ls -l {} \;
find dl -size -1024c -exec rm -f {} \;
sleep 3