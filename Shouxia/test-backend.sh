#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 5 Sources/Models.swift Sources/DownloadPolicy.swift Sources/Backend.swift Sources/Destination.swift Tests/BackendTests.swift -o .build/backend-tests
.build/backend-tests
