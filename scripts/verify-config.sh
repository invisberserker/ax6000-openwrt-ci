#!/usr/bin/env bash
# Verify the resolved .config before compiling.
# Usage: scripts/verify-config.sh [path/to/.config]
set -euo pipefail

CFG="${1:-.config}"
[ -f "$CFG" ] || { echo "verify-config: missing $CFG" >&2; exit 1; }

fail=0
require() {
	local sym="$1"
	if ! grep -qx "CONFIG_${sym}=y" "$CFG"; then
		echo "verify-config: missing CONFIG_${sym}=y" >&2
		fail=1
	fi
}
forbid() {
	local sym="$1"
	if grep -qx "CONFIG_${sym}=y" "$CFG"; then
		echo "verify-config: forbidden CONFIG_${sym}=y" >&2
		fail=1
	fi
}

# Target / storage
require TARGET_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000

# LuCI / package manager / PPPoE
require PACKAGE_luci
require PACKAGE_luci-app-firewall
require PACKAGE_luci-app-package-manager
require PACKAGE_luci-proto-ppp
require PACKAGE_luci-theme-bootstrap
require PACKAGE_luci-theme-argon

# OpenClash + mihomo (binary is baked by the workflow)
require PACKAGE_luci-app-openclash

# ssr-plus + Xray, with no other proxy engine selected
require PACKAGE_luci-app-ssr-plus
require PACKAGE_xray-core
require PACKAGE_luci-app-ssr-plus_INCLUDE_Xray
require PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client
require PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server
require PACKAGE_luci-app-ssr-plus_Nftables_Transparent_Proxy
forbid PACKAGE_luci-app-ssr-plus_Iptables_Transparent_Proxy
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Client
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Server
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Simple_Obfs
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_Http_Proxy
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_Mihomo
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_GeoData
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_Shadow_TLS
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_Kcptun
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_NaiveProxy
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_ChinaDNS_NG
forbid PACKAGE_luci-app-ssr-plus_INCLUDE_MosDNS

# DNS / firewall / proxy kmods
require PACKAGE_dnsmasq-full
require PACKAGE_dnsmasq_full_nftset
forbid PACKAGE_dnsmasq
require PACKAGE_firewall4
require PACKAGE_nftables-json
require PACKAGE_kmod-tun
require PACKAGE_kmod-inet-diag
require PACKAGE_kmod-nft-tproxy
require PACKAGE_kmod-nft-fullcone
require PACKAGE_kmod-nft-nat
require PACKAGE_kmod-nft-socket

# WiFi / device
require PACKAGE_wpad-basic-mbedtls
forbid PACKAGE_wpad-openssl
forbid PACKAGE_wpad-basic-wolfssl
require PACKAGE_kmod-mt7915e
require PACKAGE_kmod-mt7986-firmware
require PACKAGE_mt7986-wo-firmware
require PACKAGE_kmod-leds-ws2812b
require PACKAGE_kmod-crypto-hw-safexcel
require PACKAGE_uboot-envtools
require PACKAGE_autocore-arm

# WAN / IPv6 / runtime
require PACKAGE_ppp
require PACKAGE_ppp-mod-pppoe
require PACKAGE_odhcp6c
require PACKAGE_odhcpd-ipv6only
require PACKAGE_luci-proto-ipv6
require PACKAGE_zram-swap
require PACKAGE_htpdate

# UI extras deliberately kept
require PACKAGE_luci-app-upnp
require PACKAGE_luci-app-ddns
require PACKAGE_ddns-scripts
require PACKAGE_luci-app-arpbind
require PACKAGE_luci-app-wol
require PACKAGE_luci-app-nlbwmon
require PACKAGE_nlbwmon
require PACKAGE_luci-app-autoreboot
require PACKAGE_htop
require PACKAGE_kmod-sched-core
require PACKAGE_kmod-sched-bpf
require PACKAGE_kmod-xdp-sockets-diag

# Deliberately removed
forbid PACKAGE_luci-app-vsftpd
forbid PACKAGE_vsftpd-alt
forbid PACKAGE_luci-app-vlmcsd
forbid PACKAGE_vlmcsd
forbid PACKAGE_luci-app-filetransfer
forbid PACKAGE_luci-app-accesscontrol
forbid PACKAGE_luci-app-turboacc
forbid PACKAGE_coremark
forbid PACKAGE_kmod-veth
forbid PACKAGE_luci-theme-design
forbid PACKAGE_luci-app-opkg
forbid PACKAGE_luci-i18n-opkg-zh-cn

if [ "$fail" -ne 0 ]; then
	echo "verify-config: FAILED" >&2
	exit 1
fi

echo "verify-config: OK ($CFG)"
