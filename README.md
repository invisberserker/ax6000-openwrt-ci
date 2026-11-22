# Redmi AX6000 — self-built lede firmware (GitHub Actions)

Push-button firmware for the **Xiaomi Redmi Router AX6000** (MediaTek MT7986A,
128 MB NAND, 512 MB RAM), built on **coolsnowwolf/lede master** with the
default kernel (currently 6.18), firewall4/nftables and opkg (remote feeds
disabled in the image).

Primary proxy: **OpenClash + mihomo (Meta core)**. Backup proxy:
**luci-app-ssr-plus + Xray**, used for VLESS-XTLS-REALITY when you do not want
to touch the Clash config. Both are installed. Neither starts at boot until you
select one in **Services → Proxy Switch**.

## What is in / what is not

| Baked in | Notes |
|---|---|
| `luci-app-openclash` | from the luci `openwrt-25.12` feed; version 0.48.x |
| **mihomo core** | pinned v1.19.34, baked uncompressed at `/etc/openclash/core/clash_meta`; bump `MIHOMO_VERSION`/`MIHOMO_SHA256` in the workflow |
| `luci-app-ssr-plus` + **Xray core only** | from the helloworld `dev` feed (198); no optional proxy engines; the unavoidable UI helpers `dns2tcp`/`microsocks`/`ipt2socks` remain; VLESS/XTLS/REALITY are features of the single `xray-core` binary (26.11.9); Xray's built-in Naive/Cronet outbound is disabled |
| `dnsmasq-full` (nftset + ipset) | both proxy apps need nftset; ipset support is kept for the deliberate iptables fallback; plain `dnsmasq` is deselected; TFTP support is off |
| kmod-tun, kmod-inet-diag, kmod-nft-tproxy, kmod-nft-fullcone, kmod-nft-nat, kmod-nft-socket | baked `=y`; later opkg kmods would fail on kernel hash mismatch |
| `wpad-basic-mbedtls` | smallest WPA3-Personal/802.11r/802.11w-capable wpad |
| ppp + pppoe, zram-swap, htpdate, argon theme, zh-cn LuCI | PPPoE WAN; RAM swap; HTTP time sync against Chinese endpoints (no RTC) |
| UPnP, DDNS, nlbwmon, autoreboot, htop, QoS/XDP kmods, arpbind, WOL | kept deliberately for a non-empty LuCI and optional daily use |
| **Proxy Switch** LuCI page + `proxy-switch` helper | three options: OpenClash / Xray / Off; always restarts dnsmasq and firewall |
| Remote opkg feeds | cleared on first boot; signature checking restored; the image is treated as immutable — rebuild to change packages |

Not installed: FTP server, KMS server, parental controls, flow-offload/BBR UI,
third theme, benchmark, virtual Ethernet (containers), file transfer UI,
`luci-app-opkg` (replaced by `luci-app-package-manager`), DDNS provider
scripts, and dnsmasq TFTP support.

The bootloader is never touched. The modified U-Boot and its recovery web page
remain the brick safeguard.

## Step 0 — pre-flight check (read-only, on the router)

**Gate:** run this before building or flashing. The image cannot infer the
partition layout, and flashing the wrong profile is not recoverable by
sysupgrade. If the result does not match the table below, stop and switch the
layout in U-Boot first.

```sh
ubus call system board
cat /proc/mtd
fw_printenv mtd_layout_label 2>/dev/null
```

| What you see | Meaning | Profile |
|---|---|---|
| One big `ubi` (~108–112 MB) | immortalwrt-mt798x / custom-U-Boot 110m layout | default `xiaomi_redmi-router-ax6000` |
| `ubi_kernel` 30M + `ubi` 80M | U-Boot “default” layout | `..._DEVICE_xiaomi_redmi-router-ax6000-stock` |
| `ubi` 30M + `ubi1` 30M + `overlay` ~50M | Xiaomi stock layout | **neither profile** — switch layout in U-Boot first |
| `rsv0` 1M + `ubi` 110M | QWRT layout | **not compatible** — switch layout in U-Boot first |

`fw_printenv mtd_layout_label` should print `immortalwrt-110m` for the default
profile, or `default` for the stock/U-Boot-default profile. Confirm
`board_name` from `ubus call system board` is `xiaomi,redmi-router-ax6000` for
the default profile.

**Changing partition layout must be done in U-Boot, and the firmware flashed
from the U-Boot recovery page — never by sysupgrade from the running system.**
For the AX6000 the recovery page is `192.168.31.1`; set the PC to
`192.168.31.100`, hold Reset while powering on for ~15 s.

## Build

Actions → **Build lede for Redmi AX6000** → **Run workflow**. The only input
is optional `lede_ref` (default `master`); mihomo, the config and the helper
scripts are pinned in the repo/workflow.

- `lede_ref` pins the lede tree to a commit, branch or tag for a rollback run.
  A full commit SHA is best. Feeds still come from current heads.
- The workflow builds from lede/feed **current heads**. It runs `make prereq`,
  patches the default-settings password guard, and records the exact `lede`,
  feed, repo and mihomo revisions in `sources.lock`, and uploads it with the
  image. That is the rollback record, not a forward-compatibility promise: a
  later feed snapshot is still a fresh build.
- A successful build also creates a **GitHub Release** with the sysupgrade
  image, manifest, `SHA256SUMS`, `sources.lock`, `diffconfig.txt` and build
  log. Artifacts alone expire after 30 days.
- The workflow fails fast if a required symbol/package is missing, a forbidden
  engine appears, the image exceeds 100 MB, or the sysupgrade `BOARD` does not
  match the AX6000 profile. It does not silently ship a wrong config.

Download the `ax6000-firmware-<run>-<attempt>` artifact or the release. The
sysupgrade image is `bin/targets/mediatek/filogic/*sysupgrade*.bin`.

## Flash

LuCI → System → Backup / Flash Firmware → upload the sysupgrade image →
**uncheck “Keep settings”** for the first flash (or when changing firmware
lineage), check it for a same-profile rebuild. “Keep settings” preserves
proxy configs but intentionally resets the active proxy mode to Off.

Before flashing, test the image on the router:

```sh
sysupgrade -T /tmp/openwrt-mediatek-filogic-xiaomi_redmi-router-ax6000-squashfs-sysupgrade.bin
```

If `-T` rejects it, do not flash it.

Recovery if a ROM ever fails to boot: power off, hold Reset, power on, hold
~15 s → `192.168.31.1` → flash a known-good sysupgrade/factory image. Keep the
last known-good image offline; GitHub is not a decade archive.

## First boot and Proxy Switch

1. Configure WAN (PPPoE) and WiFi. The default LAN IP is `192.168.1.1`; the
   first-boot root password is `password` — change it immediately. The
   default-settings guard only seeds that hash while the shadow entry is empty,
   so a changed password survives sysupgrade.
2. **Neither proxy is running.** OpenClash ships `enable=0`; ssr-plus is
   disabled at the rc.d level because its `boot()` always calls `start()` and
   does not check an enable flag.
3. Open **Services → Proxy Switch** and choose exactly one:

   - **Off (direct internet)**
   - **OpenClash (mihomo)**
   - **Xray (ssr-plus)**

   Switching stops both, waits for `clash`/`xray` to exit, restarts dnsmasq
   and firewall, then starts the selected one. Existing connections drop
   during the switch. The choice persists across a normal reboot.

   A **sysupgrade with “Keep settings” intentionally resets the mode to Off**
   and disables both proxies. Re-select one after an upgrade. This is a safety
   choice, not a bug.

Do not use the per-app Enable toggles as the master control; use Proxy Switch.
If you enable one app manually while the other is running, you can still create
a DNS/nftables conflict.

### Xray / VLESS-XTLS-REALITY

In ssr-plus add a server, choose **VLESS**, enable **REALITY**, and fill public
key, short ID, spiderX, fingerprint and `xtls-rprx-vision` as required. This is
the only Xray protocol configured; no other engine is installed. The current
helloworld `dev` UI exposes these fields, and `xray-core` 26.11.9 supports
standard VLESS-REALITY (including the newer ML-DSA-65 field).

### OpenClash / mihomo

The baked core is at `/etc/openclash/core/clash_meta` and is detected by
OpenClash. `small_flash_memory=1` is baked on: ad-hoc core updates and runtime
caches live in `/tmp` (RAM), not in the writable overlay. They disappear on
reboot, and the baked core is used again. After a couple of months, flash a new
image with the upgraded core baked in. A sysupgrade restores the baked version;
the default preserve list keeps OpenClash configuration, subscription YAMLs,
custom rules and overwrite files.

## Post-flash checklist

1. **Only one proxy active.** Use Services → Proxy Switch.
2. **Flow offloading is already off** and **packet steering is already on**
   via `files/etc/uci-defaults/99-router-defaults`. Don’t turn offloading back
   on while proxying; offloaded flows bypass TPROXY/TUN.
3. **OpenClash core** should show mihomo v1.19.34 at
   `/etc/openclash/core/clash_meta`.
4. **WED** is optional. `bridger` is not installed by default; if you enable
   WED, add `CONFIG_PACKAGE_bridger=y` and the `mt7915e wed_enable=Y` module
   option. Leave it off unless you need it.
5. **Fullcone NAT** is available in Firewall settings (kmod baked in).
6. **Time sync**: htpdate is enabled with Chinese HTTP endpoints
   (`www.baidu.com`, `www.qq.com`, `www.taobao.com`, `www.jd.com`; IPv4 only).
   Confirm the clock before debugging TLS or REALITY failures on a cold boot.
7. **UPnP** is installed and kept deliberately; it can open WAN holes. Enable
   it only for devices that need it.
8. **IPv6** is left at lede defaults. If IPv6 leaks around the proxy, disable
   `wan6`/RA on LAN as a runtime preference.
9. **OpenClash and ssr-plus configs are preserved** across sysupgrade with
   “Keep settings” via `files/etc/sysupgrade.conf`; OpenClash subscription
   YAMLs under `/etc/openclash/config/` are included. The active proxy mode is
   intentionally reset to Off by `99-proxy-defaults`.
10. **Remote opkg feeds are disabled** and signature checking is restored by
    `99-zz-immutable-opkg`. Use the package manager read-only, or rebuild the
    image for package changes.

## Maintenance

- **Update firmware**: just run the workflow again. It follows lede master and
  current feed heads, records them in `sources.lock`, and creates a release if
  the build passes.
- **If master is broken**: check lede's own Actions history for the last green
  scheduled build, then rerun this workflow with `lede_ref=<that commit>`. This
  rolls back lede only; feeds remain current. If that fails because feeds also
  drifted, use the feed revisions in the last successful release's
  `sources.lock`, or restore the last good release image.
- **Bump mihomo**: change `MIHOMO_VERSION` and `MIHOMO_SHA256` in
  `.github/workflows/openwrt-build.yml` (use a stable tag; ignore
  `Prerelease-Alpha`). The workflow checks the SHA and ELF architecture.
- **Bump Xray**: the helloworld `dev` feed currently carries 26.11.9. The
  `dev` branch is used deliberately because it has the current ssr-plus (198)
  and xray-core; pin/bump via `configs/feeds.conf` if you want a specific feed
  revision.
- **Change packages**: edit `configs/ax6000.seed` and run the workflow. The
  verifier prints and fails on missing/forbidden symbols.
- **Do not install packages from remote feeds**: `99-zz-immutable-opkg` clears
  the opkg feeds and restores signature checking. Baked packages are tested
  together; runtime installs can mismatch this kernel/ABI. Rebuild instead.
- **Known-good rollback**: keep the release image and `sources.lock`. The image
  is the fast emergency path; the lock records the exact lede/feed/mihomo tree
  for a later `lede_ref` rebuild or bisect. `sources.lock` attached to a failed
  build identifies the tree but is not a known-good release.

## Local debug build

Use the same repo files; don’t reproduce a different tree.

```sh
sudo apt install build-essential binutils clang flex bison gawk gettext intltool \
  autoconf automake autopoint libtool cmake ninja-build pkgconf libncurses-dev \
  libssl-dev libelf-dev zlib1g-dev liblzma-dev libbz2-dev libzstd-dev \
  libyaml-dev libreadline-dev libgmp-dev libffi-dev libpcre2-dev \
  libglib2.0-dev libltdl-dev libmpc-dev libmpfr-dev libpython3-dev \
  python3 python3-setuptools python3-pip python3-wheel python3-ply \
  python3-pyelftools p7zip-full \
  device-tree-compiler bc cpio patch rsync swig squashfs-tools xz-utils \
  zstd bzip2 unzip file wget curl git subversion ccache jq xxd texinfo \
  gperf re2c

git clone --depth 1 https://github.com/coolsnowwolf/lede openwrt
(cd openwrt && make prereq)
./scripts/patch-default-settings.sh openwrt
mkdir -p openwrt/files
cp -a files/. openwrt/files/
cp configs/feeds.conf openwrt/feeds.conf
cd openwrt
./scripts/feeds update -a && ./scripts/feeds install -a
mkdir -p files/etc/openclash/core
curl --retry 5 -fsSL -o /tmp/mihomo.gz \
  https://github.com/MetaCubeX/mihomo/releases/download/v1.19.34/mihomo-linux-arm64-v1.19.34.gz
echo "daaf78a6240a282cdfd75bcbf98fe321f6bd52765cc29e79f344191198f0b50f  /tmp/mihomo.gz" | sha256sum -c -
gunzip -c /tmp/mihomo.gz > files/etc/openclash/core/clash_meta
chmod 755 files/etc/openclash/core/clash_meta
cp ../configs/ax6000.seed .config
make defconfig
../scripts/verify-config.sh .config
make download -j2
make -j2 V=s 2>&1 | tee build.log
../scripts/verify-manifest.sh bin/targets/mediatek/filogic
```

On a 2-core / 3.8 GB VM use `-j1` or add swap; `-j2` can OOM during Go/Ruby
builds. No serial fallback is baked into CI; inspect `build.log` on failure.

## Source map / traps

- **ssr-plus + xray-core** live in the `fw876/helloworld` `dev` branch feed
  (ssr-plus 198, xray-core 26.11.9). lede no longer bundles ssr-plus under
  `package/lean`. `Http_Proxy` and the optional engines are off; Xray's own
  Naive/Cronet outbound is disabled with `CONFIG_XRAY_CORE_NAIVE=n`.
- **OpenClash** lives in the luci `openwrt-25.12` feed and is the same 0.48.x
  as upstream. No clone/shadowing scripts are needed; the old `diy-part*.sh`
  have been removed.
- **mihomo** is not a package used by OpenClash; it is the baked core binary.
- **luci-app-opkg does not exist** in the 25.12 luci feed; the package manager
  is `luci-app-package-manager`.
- **ssr-plus boot ignores enable**: disable its rc.d symlink; the Proxy Switch
  page handles this.
- **OpenClash conffiles are empty**: `sysupgrade.conf` preserves `/etc/config/openclash`,
  `/etc/openclash/config/`, custom rules and overwrite files.
- **No flow offload** while proxying; this is baked off.
- **No dual proxy**: the switch helper stops both before starting one; a
  sysupgrade with Keep settings intentionally resets the mode to Off.
- **No-RTC TLS failures**: htpdate is included, enabled, and points at Chinese
  HTTP endpoints.
- **Baked core size**: ~57 MB uncompressed, ~14 MB in the xz squashfs; the
  110 MB UBI has room for both mihomo and Xray in the static image. Ad-hoc
  core updates use `small_flash_memory=1` (`/tmp`), so they do not need to fit
  in the writable overlay and do not survive a reboot.
- **Root password**: first boot seeds `password`; the default-settings patch
  only applies it when the shadow entry is empty, so a changed password
  survives sysupgrade.
- **Remote opkg feeds**: cleared on first boot; signature checking restored.
  Rebuild for package changes.

## Sources

coolsnowwolf/lede · coolsnowwolf/luci · coolsnowwolf/packages ·
fw876/helloworld · vernesong/OpenClash · MetaCubeX/mihomo ·
hanwckf/bl-mt798x · OpenWrt flow-offloading/WED docs.
