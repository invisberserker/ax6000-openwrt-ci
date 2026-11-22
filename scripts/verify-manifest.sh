#!/usr/bin/env bash
# Verify the built image, manifest, size and sysupgrade metadata.
# Usage: scripts/verify-manifest.sh [target-dir]
set -euo pipefail

DIR="${1:-bin/targets/mediatek/filogic}"
MAX_IMAGE_BYTES="${MAX_IMAGE_BYTES:-100000000}" # 100 MB safety ceiling

[ -d "$DIR" ] || { echo "verify-manifest: missing $DIR" >&2; exit 1; }

MANIFEST="$(find "$DIR" -maxdepth 1 -name '*.manifest' -type f | head -n1 || true)"
[ -n "$MANIFEST" ] || { echo "verify-manifest: no *.manifest in $DIR" >&2; exit 1; }

fail=0
has_pkg() {
	local pkg="$1"
	awk -v p="$pkg" '$1 == p { found = 1 } END { exit found ? 0 : 1 }' "$MANIFEST" || {
		echo "verify-manifest: missing package $pkg" >&2
		fail=1
	}
}
no_pkg() {
	local pkg="$1"
	if awk -v p="$pkg" '$1 == p { found = 1 } END { exit found ? 0 : 1 }' "$MANIFEST"; then
		echo "verify-manifest: forbidden package $pkg" >&2
		fail=1
	fi
}

# Must be present
for p in \
	luci-app-openclash \
	luci-app-ssr-plus \
	xray-core \
	luci-compat \
	ipt2socks \
	dns2tcp \
	microsocks \
	nping \
	resolveip \
	lyaml \
	idn2 \
	coreutils-timeout \
	luci-app-package-manager \
	luci-proto-ppp \
	luci-app-firewall \
	luci-app-upnp \
	miniupnpd-nftables \
	luci-app-ddns \
	ddns-scripts \
	luci-app-arpbind \
	luci-app-wol \
	etherwake \
	luci-app-nlbwmon \
	luci-lib-chartjs \
	luci-app-autoreboot \
	htop \
	dnsmasq-full \
	kmod-tun \
	kmod-inet-diag \
	kmod-nft-tproxy \
	kmod-nft-fullcone \
	kmod-nft-nat \
	kmod-nft-socket \
	kmod-sched-core \
	kmod-sched-bpf \
	kmod-xdp-sockets-diag \
	wpad-basic-mbedtls \
	ppp \
	ppp-mod-pppoe \
	zram-swap \
	htpdate \
	ruby \
	ruby-yaml \
	bash \
	curl \
	ca-bundle \
	ip-full \
	unzip
do
	has_pkg "$p"
done

# Must not be present
for p in \
	luci-app-vsftpd \
	vsftpd-alt \
	luci-app-vlmcsd \
	vlmcsd \
	luci-app-filetransfer \
	luci-app-accesscontrol \
	luci-app-turboacc \
	luci-theme-design \
	coremark \
	kmod-veth \
	shadowsocks-rust-sslocal \
	shadowsocks-rust-ssserver \
	shadowsocks-libev-ss-local \
	shadowsocks-libev-ss-server \
	shadowsocks-libev-ss-redir \
	shadowsocksr-libev-ssr-local \
	shadowsocksr-libev-ssr-redir \
	shadowsocksr-libev-ssr-server \
	simple-obfs-client \
	v2ray-core \
	v2ray-plugin \
	hysteria \
	tuic-client \
	naiveproxy \
	kcptun-client \
	shadow-tls \
	trojan \
	chinadns-ng \
	mosdns \
	dnsproxy \
	redsocks2 \
	dns2socks-rust \
	3proxy \
	mihomo \
	v2ray-geoip \
	v2ray-geosite
do
	no_pkg "$p"
done

IMAGE="$(find "$DIR" -maxdepth 1 -name '*sysupgrade*.bin' -type f | head -n1 || true)"
[ -n "$IMAGE" ] || { echo "verify-manifest: no sysupgrade image in $DIR" >&2; exit 1; }

SIZE="$(stat -c%s "$IMAGE")"
printf 'verify-manifest: image %s = %s bytes (%.1f MiB), limit %s bytes\n' \
	"$(basename "$IMAGE")" "$SIZE" "$(awk -v b="$SIZE" 'BEGIN { printf "%.1f", b/1048576 }')" "$MAX_IMAGE_BYTES"
if [ "$SIZE" -gt "$MAX_IMAGE_BYTES" ]; then
	echo "verify-manifest: image exceeds size ceiling" >&2
	fail=1
fi

# sysupgrade-tar layout: a CONTROL file and root/kernel entries.
TAR_LIST="$(mktemp)"
trap 'rm -f "$TAR_LIST"' EXIT
tar -tf "$IMAGE" > "$TAR_LIST" 2>/dev/null || true
if ! grep -qE '/CONTROL$' "$TAR_LIST"; then
	echo "verify-manifest: image has no CONTROL file" >&2
	fail=1
else
	CONTROL="$(grep -E '/CONTROL$' "$TAR_LIST" | head -n1)"
	BOARD="$(tar -xOf "$IMAGE" "$CONTROL" 2>/dev/null | sed -n 's/^BOARD=//p' | head -n1 || true)"
	if [ "$BOARD" != "xiaomi_redmi-router-ax6000" ]; then
		echo "verify-manifest: unexpected BOARD='$BOARD' (want xiaomi_redmi-router-ax6000)" >&2
		fail=1
	else
		echo "verify-manifest: BOARD=$BOARD"
	fi
fi

for entry in root kernel; do
	if ! grep -qE "/${entry}$" "$TAR_LIST"; then
		echo "verify-manifest: image has no ${entry} entry" >&2
		fail=1
	fi
done

# Convenience checksum file for the artifact/release.
(
	cd "$DIR"
	sha256sum ./*sysupgrade*.bin ./*.manifest > SHA256SUMS
)
echo "verify-manifest: wrote $DIR/SHA256SUMS"

if [ "$fail" -ne 0 ]; then
	echo "verify-manifest: FAILED" >&2
	exit 1
fi

echo "verify-manifest: OK"
