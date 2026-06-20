#!/bin/bash
git clone -b master --single-branch --filter=blob:none https://github.com/vernesong/OpenClash p-temp/clash
git clone https://github.com/sbwml/luci-app-quickfile package/quickfile
mv p-temp/clash/luci-app-openclash package/luci-app-openclash
rm -rf p-temp

exit 0
