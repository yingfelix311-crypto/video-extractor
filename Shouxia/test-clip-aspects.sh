#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 5 Sources/ClipCanvas.swift Tests/ClipCanvasTests.swift -o .build/clip-canvas-tests
.build/clip-canvas-tests
swiftc -swift-version 5 Sources/ClipCanvas.swift Tests/ClipCustomCanvasTests.swift -o .build/clip-custom-tests
.build/clip-custom-tests
inputs=(Sources/Models.swift Sources/DownloadPolicy.swift Sources/Destination.swift Sources/Theme.swift Sources/ClipCanvas.swift Sources/ClipExporter.swift Sources/ClipEditor.swift)
swiftc -swift-version 5 "${inputs[@]}" Tests/ClipAspectModelTests.swift -o .build/clip-aspect-model-tests
.build/clip-aspect-model-tests
if [ "${1:-}" = '--export' ]; then
 fixtures=$(mktemp -d "${TMPDIR:-/tmp}/clip-aspects.XXXXXX")
 trap 'rm -rf "$fixtures"' EXIT
 ffmpeg_cli="${SHOUXIA_FFMPEG:-$HOME/.local/bin/ffmpeg}"
 "$ffmpeg_cli" -v error -f lavfi -i color=c=red:s=640x360:r=30:d=1 -f lavfi -i sine=frequency=440:duration=1 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$fixtures/normal.mp4"
 "$ffmpeg_cli" -v error -i "$fixtures/normal.mp4" -c copy -metadata:s:v:0 rotate=90 "$fixtures/rotated.mp4"
 swiftc -swift-version 5 Sources/Models.swift Sources/DownloadPolicy.swift Sources/Destination.swift Sources/ClipCanvas.swift Sources/ClipExporter.swift Tests/ClipAspectExportTests.swift -o .build/clip-aspect-export-tests
 .build/clip-aspect-model-tests "$fixtures/normal.mp4"
 .build/clip-aspect-export-tests "$fixtures/normal.mp4"
 .build/clip-aspect-export-tests "$fixtures/rotated.mp4"
fi
