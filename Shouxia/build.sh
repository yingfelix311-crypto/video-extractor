#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/Video Extractor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/Shouxia" -framework SwiftUI -framework AppKit -lsqlite3 -framework Security
cp Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
cp Resources/Mascot.png "$APP/Contents/Resources/"
ditto Resources/Fonts "$APP/Contents/Resources/Fonts"
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
