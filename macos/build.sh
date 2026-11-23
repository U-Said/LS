#!/bin/bash
# Builds build/macos/LiteSwitcher.app — one universal binary for Apple Silicon and Intel, macOS 11+.
# Needs only the Xcode command line tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/macos
APP=$OUT/LiteSwitcher.app
FLAGS=(-O2 -Wall -Wextra -Wno-unused-parameter -arch arm64 -arch x86_64 -mmacosx-version-min=11.0)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

clang -std=c11 "${FLAGS[@]}" -c core/ls_core.c -o "$OUT/ls_core.o"
clang -fobjc-arc "${FLAGS[@]}" -Icore macos/main.m "$OUT/ls_core.o" \
  -framework Cocoa -framework Carbon -framework ApplicationServices \
  -o "$APP/Contents/MacOS/LiteSwitcher"
clang -std=c11 "${FLAGS[@]}" core/coretest.c core/ls_core.c -o "$OUT/coretest"

cp macos/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
iconutil -c icns macos/LS.iconset -o "$APP/Contents/Resources/LS.icns"

# Ad-hoc signature: Apple Silicon runs only signed code. Without a paid Apple ID the app is not notarized,
# so the first launch needs "Open Anyway" (see README).
codesign --force --sign - "$APP"
codesign --verify --verbose=1 "$APP"
lipo -info "$APP/Contents/MacOS/LiteSwitcher"
echo "Built $APP"
