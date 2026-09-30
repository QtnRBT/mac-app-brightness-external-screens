#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the Icon Composer document
# Resources/AppIcon.icon. The .icns is the flat fallback that build-app.sh ships
# when actool cannot compile the .icon (see there). Re-run after editing the .icon.
# Needs Xcode 26+ on the dev machine: it uses Icon Composer's own renderer (ictool).
set -euo pipefail

cd "$(dirname "$0")/../.."
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# macOS icon grid: 1024 pt canvas with the 824 pt squircle centred (100 pt margin).
"$ICTOOL" Resources/AppIcon.icon --export-image --output-file "$WORK/shape.png" \
    --platform macOS --rendition Default --width 824 --height 824 --scale 1 >/dev/null
sips --padToHeightWidth 1024 1024 "$WORK/shape.png" --out "$WORK/master.png" >/dev/null

SET="$WORK/AppIcon.iconset"
mkdir "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/master.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/master.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
