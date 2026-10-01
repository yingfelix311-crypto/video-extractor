#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 6 Sources/Models.swift Sources/Backend.swift Tests/CoreTests.swift -o .build/core-tests
.build/core-tests "$@"
