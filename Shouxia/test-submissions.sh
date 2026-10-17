#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 5 Sources/Models.swift Sources/DownloadPolicy.swift Sources/Backend.swift Sources/Destination.swift Sources/EngineUpdater.swift Sources/RuntimeSupport.swift Sources/Submission.swift Sources/Store.swift Tests/SubmissionTests.swift -o .build/submission-tests
.build/submission-tests
