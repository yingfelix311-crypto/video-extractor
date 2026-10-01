#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 5 Sources/Models.swift Sources/Backend.swift Sources/Destination.swift Sources/EngineUpdater.swift Sources/Store.swift Tests/StoreTests.swift -o .build/store-tests
.build/store-tests
