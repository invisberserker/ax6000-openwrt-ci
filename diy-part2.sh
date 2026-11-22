#!/usr/bin/env bash
# Runs AFTER ./scripts/feeds install -a.
# Purpose: drop duplicate copies of the packages we ship from package/ so
# kconfig never sees two sources with the same name.
set -euo pipefail

rm -rf package/feeds/luci/luci-app-ssr-plus
rm -rf package/feeds/luci/luci-app-openclash

echo "diy-part2 done."
