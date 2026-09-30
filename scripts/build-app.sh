#!/usr/bin/env bash
# Builds a release binary and wraps it in build/ScreenBrightness.app (ad-hoc signed).
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/ScreenBrightness.app"

# SwiftPM's link step only passes --sysroot, so the binary would record the
# deployment target (14.0) as its SDK version and AppKit would run it in
# pre-Liquid Glass compatibility mode. Pass -isysroot so the real SDK is stamped.
SDK="$(xcrun --show-sdk-path)"
FLAGS=(-c release --arch arm64 -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK")

swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/ScreenBrightness"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ScreenBrightness"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
