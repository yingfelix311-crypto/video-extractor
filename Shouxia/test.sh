#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 6 Sources/Models.swift Sources/DownloadPolicy.swift Sources/Backend.swift Sources/Destination.swift Tests/CoreTests.swift -o .build/core-tests
.build/core-tests "$@"
