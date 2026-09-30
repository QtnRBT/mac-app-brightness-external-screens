#!/usr/bin/env bash
# Builds a release binary and wraps it in build/ScreenBrightness.app (ad-hoc signed).
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/ScreenBrightness.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/ScreenBrightness"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ScreenBrightness"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
