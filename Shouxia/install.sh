#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh
DEST="$HOME/Applications/收下.app"
mkdir -p "$HOME/Applications"
ditto "build/收下.app" "$DEST"
codesign --verify --deep --strict "$DEST"
if [ ! -e "$HOME/Desktop/收下.app" ]; then ln -s "$DEST" "$HOME/Desktop/收下.app"; fi
printf 'Installed: %s\n' "$DEST"
