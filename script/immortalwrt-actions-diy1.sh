#!/bin/bash
git clone -b master --single-branch --filter=blob:none https://github.com/vernesong/OpenClash p-temp/clash
git clone https://github.com/sbwml/luci-app-quickfile package/quickfile
git clone https://github.com/ChesterGoodiny/luci-theme-proton2025 package/luci-theme-proton2025

exit 0
