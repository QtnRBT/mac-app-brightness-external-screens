#!/usr/bin/env bash
# Builds a release binary and wraps it in build/ScreenBrightness.app (ad-hoc signed).
# Optional env: VERSION (e.g. 1.2.0) and BUILD_NUMBER override the Info.plist ones.
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
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

# App icon. actool (Xcode 26+) compiles the Icon Composer document into
# Assets.car (Liquid Glass icon, macOS 26+) plus AppIcon.icns (older macOS), and
# emits the matching CFBundleIconName/CFBundleIconFile keys. Without a working
# actool (Command Line Tools only, or Xcode's first-launch setup not done) the
# prebuilt flat Resources/AppIcon.icns is shipped instead; CI must not fall back.
ICON_PLIST="build/AppIcon.partial.plist"
if xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
        --app-icon AppIcon --platform macosx --target-device mac \
        --minimum-deployment-target 14.0 --output-partial-info-plist "$ICON_PLIST" \
        --output-format human-readable-text --errors --warnings \
    && [[ -s "$APP/Contents/Resources/Assets.car" ]]; then
    /usr/libexec/PlistBuddy -c "Merge $ICON_PLIST" "$APP/Contents/Info.plist"
else
    if [[ -n "${CI:-}" ]]; then
        echo "error: actool could not compile Resources/AppIcon.icon" >&2
        exit 1
    fi
    echo "warning: actool unavailable, shipping the flat Resources/AppIcon.icns" >&2
    rm -f "$APP/Contents/Resources/Assets.car"
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi
rm -f "$ICON_PLIST"

codesign --force --sign - "$APP"

echo "Built $APP"
