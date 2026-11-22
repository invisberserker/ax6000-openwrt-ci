#!/usr/bin/env bash
# Guard lede's default-settings root password seds with an empty-hash check.
#
# Background: default-settings installs /etc/uci-defaults/99-default-settings,
# which seeds root's password to "password" on first boot. Its sed patterns
# only match an empty shadow field, so a password changed later normally
# survives sysupgrade. Make that explicit and future-proof.
#
# Usage: scripts/patch-default-settings.sh [path-to-openwrt-tree]
set -euo pipefail

ROOT="${1:-openwrt}"
FILE="$ROOT/package/lean/default-settings/files/zzz-default-settings"

[ -f "$FILE" ] || {
	echo "patch-default-settings: missing $FILE" >&2
	exit 1
}

if grep -q 'AX6000_PASSWORD_GUARD' "$FILE"; then
	echo "patch-default-settings: already patched"
	exit 0
fi

python3 - "$FILE" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()

old1 = "sed -i 's/root::0:0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.:0:0:99999:7:::/g' /etc/shadow"
old2 = "sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.:0:0:99999:7:::/g' /etc/shadow"
old = old1 + "\n" + old2

if old not in text:
    raise SystemExit("patch-default-settings: expected root-password lines not found")

new = (
    "# AX6000_PASSWORD_GUARD: only seed the default password on first boot.\n"
    "if grep -q '^root::' /etc/shadow; then\n"
    + old1 + "\n"
    + old2 + "\n"
    "fi"
)

text = text.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY

grep -n -A4 'AX6000_PASSWORD_GUARD' "$FILE"
