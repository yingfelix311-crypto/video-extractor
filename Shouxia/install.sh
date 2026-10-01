#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh
DEST="$HOME/Applications/Video Extractor.app"
mkdir -p "$HOME/Applications"
ditto "build/Video Extractor.app" "$DEST"
codesign --verify --deep --strict "$DEST"
if [ ! -e "$HOME/Desktop/Video Extractor.app" ]; then ln -s "$DEST" "$HOME/Desktop/Video Extractor.app"; fi
printf 'Installed: %s\n' "$DEST"
