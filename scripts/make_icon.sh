#!/usr/bin/env bash
set -euo pipefail

SRC="/Applications/Quip.app/Contents/Resources/AppIcon.icns"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
OUT="$SCRIPT_DIR/../Resources/AppIcon.icns"

mkdir -p "$(dirname "$OUT")"
iconutil --convert iconset --output "$ICONSET" "$SRC"

# Quip only ships 16px and 128px — upscale from 256px source to fill all slots
SRC256="$ICONSET/icon_128x128@2x.png"

make_size() {
    local name="$1" px="$2"
    local dest="$ICONSET/$name"
    [ -f "$dest" ] || sips -z "$px" "$px" "$SRC256" --out "$dest" > /dev/null
}

make_size icon_32x32.png        32
make_size icon_32x32@2x.png     64
make_size icon_256x256.png      256
make_size icon_256x256@2x.png   512
make_size icon_512x512.png      512
make_size icon_512x512@2x.png   1024

for png in "$ICONSET"/*.png; do
    swift "$SCRIPT_DIR/compose_icon.swift" "$png" "$png"
done

iconutil --convert icns --output "$OUT" "$ICONSET"
rm -rf "$WORK"
echo "Icon written to Resources/AppIcon.icns"
