#!/bin/bash
#本仓库及文件只在Github发布
#作者：QC3284@github.com(https://github.com/QC3284)
#本仓库地址：https://github.com/QC3284/openwrt-actions
#最后更新时间：2025.5.24
echo "自动编译 (Automatic compilation)" >> release.txt
echo "使用源码 (Use source code)：" >> release.txt
echo "[x-wrt](https://github.com/x-wrt/x-wrt)" >> release.txt
echo "使用标签 (Use tags)" >> release.txt
echo "[$(cat  $GITHUB_WORKSPACE/config/x-wrt-config-tag.txt)](https://github.com/x-wrt/x-wrt/releases/tag/$(cat  $GITHUB_WORKSPACE/config/x-wrt-config-tag.txt))" >> release.txt
echo "默认账号/密码 (Default account/password)：" >> release.txt
echo "admin/admin" >> release.txt
echo "SSH默认账号/密码 (Default SSH account/password)：" >> release.txt
echo "root/admin" >> release.txt
echo "注：" >> release.txt
echo "- PB-Boot(pb-boot.7z)适用于Xiaomi CR6608/CR6609/CR6606/CR660x" >> release.txt
echo "- 如果发现本次编译没有文件，说明正在调整插件和更新（也有可能是源码炸了）" >> release.txt
echo "- 如果发现更新频繁，尽量不要下载（可能正在调整插件）" >> release.txt
echo "- 此固件基于[X-WRT](https://github.com/x-wrt/x-wrt)源码编译，加入了一些插件，如需下载官方原版，请到：" >> release.txt
echo "- [X-WRT/OpenWrt/LEDE 固件下载](https://downloads.x-wrt.com/rom)" >> release.txt
echo "- 本仓库没有在[GitCode](https://gitcode.com)上发布" >> release.txt
