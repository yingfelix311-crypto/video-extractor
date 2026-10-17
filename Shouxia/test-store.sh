#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 5 Sources/Models.swift Sources/DownloadPolicy.swift Sources/Backend.swift Sources/Destination.swift Sources/EngineUpdater.swift Sources/RuntimeSupport.swift Sources/Submission.swift Sources/BrowserCookies.swift Sources/BrowserCookieReader.swift Sources/TaskCookies.swift Sources/BrowserSessionStore.swift Sources/Store.swift Tests/StoreTests.swift -lsqlite3 -framework Security -o .build/store-tests
.build/store-tests
