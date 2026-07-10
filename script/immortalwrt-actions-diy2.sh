#!/bin/bash
rm -rf feeds/luci/applications/luci-app-openclash
mv p-temp/clash/luci-app-openclash feeds/luci/applications/luci-app-openclash
rm -rf p-temp

exit 0
