#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/收下.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/Shouxia" -framework SwiftUI -framework AppKit
cp Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
