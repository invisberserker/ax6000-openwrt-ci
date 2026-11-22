#!/usr/bin/env bash
# Runs inside the freshly cloned lede tree, BEFORE ./scripts/feeds update -a.
# Purpose: replace the bundled copies of the two proxy apps with their live
# upstream sources so the build picks up current releases.
set -euo pipefail

# --- luci-app-ssr-plus from fw876/helloworld --------------------------------
# lede bundles a copy under package/lean/ that lags behind; remove it and
# clone the upstream tree (README method 1: clone into package/helloworld).
rm -rf package/lean/luci-app-ssr-plus
rm -rf package/helloworld
git clone --depth=1 https://github.com/fw876/helloworld.git package/helloworld

# --- luci-app-openclash from vernesong/OpenClash (master = stable) -----------
rm -rf package/luci-app-openclash package/lean/luci-app-openclash
git clone --depth=1 https://github.com/vernesong/OpenClash.git /tmp/OpenClash
cp -a /tmp/OpenClash/luci-app-openclash package/luci-app-openclash
rm -rf /tmp/OpenClash

echo "diy-part1 done. App versions:"
grep -m1 -E '^(PKG_VERSION|LUCI_VERSION)' package/luci-app-openclash/Makefile || true
grep -m1 'PKG_VERSION' package/helloworld/xray-core/Makefile || true
