#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 5 Sources/Models.swift Sources/Destination.swift Sources/ClipExporter.swift Tests/ClipTests.swift -o .build/clip-tests
.build/clip-tests "$@"
