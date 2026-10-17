#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 5 Sources/Models.swift Sources/DownloadPolicy.swift Sources/Destination.swift Sources/ClipCanvas.swift Sources/ClipExporter.swift Tests/ClipTests.swift -o .build/clip-tests
.build/clip-tests "$@"

swiftc -swift-version 5 Sources/ClipCanvas.swift Tests/ClipCanvasTests.swift -o .build/clip-canvas-tests
.build/clip-canvas-tests
