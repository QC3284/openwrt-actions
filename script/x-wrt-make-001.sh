#!/bin/bash
#本仓库及文件只在Github发布
#作者：QC3284@github.com(https://github.com/QC3284)
#本仓库地址：https://github.com/QC3284/openwrt-actions
#最后更新时间：2024.11.30
# 用途：编译前预下载所有依赖源码包 (make download)，并清理下载不完整的文件
make download -j8 2>&1 | tee make_download.log
sleep 2
# 列出并删除小于 1KB 的文件 (通常为下载失败的残缺包)，以便编译时自动重新下载
find dl -size -1024c -exec ls -l {} \;
find dl -size -1024c -exec rm -f {} \;
sleep 3