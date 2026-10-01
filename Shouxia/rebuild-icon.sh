#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
swift Scripts/MakeIcon.swift Resources/Mascot.png .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
