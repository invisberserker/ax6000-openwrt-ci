# Redmi AX6000 — self-built lede firmware (GitHub Actions)

Push-button custom firmware for the **Xiaomi Redmi Router AX6000** (MediaTek
MT7986A, 128 MB NAND, 512 MB RAM), built on **coolsnowwolf/lede master**
(kernel 6.12, firewall4/nftables) with exactly what you want baked in and
nothing else:

| Baked in | Notes |
|---|---|
| `luci-app-ssr-plus` + **Xray core only** | from upstream `fw876/helloworld`; all other engines/helpers (Mihomo/SS/SSR/kcptun/naive/hysteria/tuic/obfs/geodata…) disabled in the seed |
| `luci-app-openclash` | refreshed from upstream `vernesong/OpenClash` master |
| **mihomo (clash_meta) core** | downloaded by the workflow, lands at `/etc/openclash/core/clash_meta` |
| dnsmasq-full (nftset), kmod-tun / kmod-nft-tproxy / kmod-nft-fullcone / kmod-inet-diag | kmods are baked in `=y` because opkg-installed kmods fail on kernel-hash mismatch |
| wpad-basic-mbedtls | smallest WPA3-Personal/802.11r/802.11w capable wpad |
| ppp + pppoe, zram-swap, htpdate, argon theme, zh-cn LuCI | PPPoE WAN; RAM swap for the proxy cores; HTTP time sync (no RTC ⇒ TLS fails on cold boot otherwise) |

Your **bootloader is never touched**: you keep the modded uboot and its
recovery web page (hold **Reset** while powering on → set your PC to a static
IP → `192.168.31.1`) as the brick safeguard, and day-to-day flashing stays
web-UI sysupgrade + factory reset, exactly as with the mpdn builds.

---

## Step 0 — pre-flight check (once, on the router, read-only)

SSH into the router and run:

```sh
ubus call system board
cat /proc/mtd
fw_printenv mtd_layout_label 2>/dev/null
```

Interpret `/proc/mtd`:

| What you see | Meaning | Seed to use |
|---|---|---|
| One big `ubi` (≈ 108–112 MB) | custom-U-Boot big layout — expected, since your mpdn images run there | default (`...DEVICE_xiaomi_redmi-router-ax6000=y`) |
| `ubi` 30M + `ubi1` 30M + `overlay` ~50M (or `ubi_kernel` 30M + `ubi` 80M) | stock-sized layout | swap to `...DEVICE_xiaomi_redmi-router-ax6000-stock=y` in `configs/ax6000.seed` |

`fw_printenv mtd_layout_label` printing something (e.g. `default` or
`immortalwrt-110m`) confirms the uboot is hanwckf's bl-mt798x and shows its
current mode. If the mode disagrees with what `/proc/mtd` shows under your
running firmware, trust `/proc/mtd` — layouts are only ever switched from the
uboot recovery page, and the running firmware always matches the active mode.

## Setup (one time)

1. Create a **public** GitHub repo (public ⇒ free 4-core/16 GB runners;
   private works too but uses slower 2-core runners and billed minutes).
   Nothing secret lives in this repo — subscription URLs are entered on the
   router at runtime, never committed.
2. Push this folder's contents to the repo:
   ```sh
   cd ax6000-openwrt-ci
   git init && git add -A && git commit -m "ax6000 build ci"
   git remote add origin git@github.com:<you>/<repo>.git
   git push -u origin main
   ```
3. Repo → **Actions** tab → enable workflows if asked.

## Build

Actions → **Build lede for Redmi AX6000** → *Run workflow* → (optionally
override the mihomo core version) → Run.

- First run ≈ 2–3 h; the `dl/` cache makes later runs noticeably faster.
- Download the `ax6000-firmware-<run#>` artifact and unzip it. You want
  `bin/targets/mediatek/filogic/*sysupgrade*.bin` for your profile. The
  artifact also contains the kmod ipks (usable as a self-hosted feed later)
  and `diffconfig.txt` — the exact config that was built.

## Flash

LuCI → System → Backup / Flash Firmware → upload the `sysupgrade.bin`,
**uncheck "Keep settings"** (your factory-reset habit). Same-profile rebuilds
can also be flashed with settings kept.

Recovery path if a ROM ever fails to boot: power off, hold Reset, power on,
hold ~15 s → recovery page at `192.168.31.1` → flash a known-good image.

## Post-flash checklist (runtime, not baked)

1. **Only one proxy engine at a time.** OpenClash is the workhorse; disable
   ssr-plus autostart: System → Startup → `shadowsocksr` → Disable. If you
   ever switch engines: stop the old one first, then restart dnsmasq +
   firewall (both engines fight over DNS/port 53 and nft rules).
2. **Flow offloading OFF while proxying**: Network → Firewall → General
   Settings → uncheck *Software flow offloading* (and hardware, if shown).
   Offloaded flows bypass the proxy's TPROXY/TUN path (leaks + broken
   connections). Leave **Packet steering ON** (Network → Interfaces → Global
   network options) — that's what keeps ~1 Gbps NAT on the 4×A53 without
   offload.
3. **OpenClash core**: LuCI → Services → OpenClash → Version Update should
   show the Meta core at `/etc/openclash/core/clash_meta` (the baked mihomo).
   It stays updatable from that page. Optional: enable 小闪存模式 (small-flash
   mode) to keep runtime churn in `/tmp`.
4. **WED** (WiFi Ethernet Dispatch): check
   `cat /sys/module/mt7915e/parameters/wed_enable` — if `N`, follow the
   OpenWrt WED doc (`options mt7915e wed_enable=Y`). 5 GHz only; `bridger`
   is already in the image for AP-mode bridging.
5. **Fullcone NAT**: Network → Firewall → enable *Fullcone* (the kmod is
   baked in).
6. **Time sync**: System → Time Synchronization — htpdate is included;
   confirm the clock is right before trusting subscription/TLS errors.
7. **PPPoE + WiFi credentials**: re-enter after a factory-reset flash; set a
   root password on first boot (default `192.168.1.1`, no password).
8. **IPv6**: left at lede defaults. If IPv6 traffic leaks around the proxy,
   set `wan6` to disabled / turn off RA on the LAN — a runtime preference.

## Maintenance

- **Change plugins / trim more**: edit `configs/ax6000.seed` → push → Run
  workflow. The workflow log prints the resolved config; unknown symbols are
  silently dropped by `make defconfig`, so verify yours appear there.
- **Bump the clash core**: Run workflow with a newer `mihomo_version` input
  (release tags of MetaCubeX/mihomo), or update it later from LuCI.
- **Rebuild cadence**: lede master moves daily; rebuilding every month or so
  picks up kernel/security fixes. Every rebuild is a plain sysupgrade.

## Local debug build (only if CI fails)

Your ARM64 VM (2 cores / 3.8 GB) can build this natively — expect ~5–8 h:

```sh
sudo apt install build-essential clang flex bison gawk gettext libncurses-dev \
  libssl-dev libelf-dev zlib1g-dev python3-setuptools python3-pip rsync swig \
  unzip file wget curl ccache
git clone --depth 1 https://github.com/coolsnowwolf/lede && cd lede
/path/to/ax6000-openwrt-ci/diy-part1.sh
./scripts/feeds update -a && ./scripts/feeds install -a
/path/to/ax6000-openwrt-ci/diy-part2.sh
mkdir -p files/etc/openclash/core
curl -fsSL https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-linux-arm64-v1.19.33.gz \
  | gunzip > files/etc/openclash/core/clash_meta && chmod +x files/etc/openclash/core/clash_meta
cp /path/to/ax6000-openwrt-ci/configs/ax6000.seed .config && make defconfig
make download -j2
make -j2 || make V=s -j1     # on failure, the serial verbose pass names the culprit
```

## Traps encoded in this repo (so you don't rediscover them)

- **dnsmasq vs dnsmasq-full**: both plugins need `-full`; keeping both
  selected breaks the image build. Seed forces `-full` and unsets plain.
- **No clash core in the ipk**: the workflow bakes mihomo into
  `files/etc/openclash/core/clash_meta`; first-launch download would need
  direct GitHub access from the router.
- **kmod vermagic**: later `opkg install kmod-*` fails against official feeds
  (different kernel hash) — everything needed is baked `=y`.
- **Proxy vs flow offloading**: see checklist #2.
- **Dual-engine DNS conflict**: see checklist #1.
- **No-RTC TLS failures on cold boot**: htpdate included.
- **wpad variant bloat**: basic-mbedtls keeps WPA3-Personal/11r/11w at the
  smallest size.
- **Xray build needs host clang**: installed in the workflow's dependency
  step.

## Sources behind these choices

hanwckf/immortalwrt-mt798x README + bl-mt798x docs · openwrt.org TOH
Redmi AX6000 (layouts, exploit) · fw876/helloworld README + Makefile ·
vernesong/OpenClash README/issues #399 (baking cores) · MetaCubeX/mihomo
releases · openwrt.org flow-offloading + WED docs · P3TERX/Actions-OpenWrt
CI patterns.
