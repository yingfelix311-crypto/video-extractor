#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p '.build/Folder Picker.app/Contents/MacOS'
swiftc FolderPicker.swift -framework AppKit -o '.build/Folder Picker.app/Contents/MacOS/FolderPicker'
python3 - <<'PY'
import plistlib
from pathlib import Path
Path('.build/Folder Picker.app/Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.felix.videoextractor.previewpicker',
    'CFBundleName': 'Folder Picker', 'CFBundleExecutable': 'FolderPicker',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True,
}))
PY
codesign --force --sign - '.build/Folder Picker.app'
exec python3 preview_server.py
