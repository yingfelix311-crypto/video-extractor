#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 5 Sources/Models.swift Sources/DownloadPolicy.swift Sources/Destination.swift Sources/Theme.swift Sources/ClipExporter.swift Sources/ClipEditor.swift Tests/ClipTimelineTests.swift -o .build/clip-timeline-tests
.build/clip-timeline-tests
