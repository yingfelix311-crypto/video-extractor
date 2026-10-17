#!/bin/sh
set -eu
cd "$(dirname "$0")"
output=$(mktemp -t shouxia-runtime)
trap 'rm -f "$output"' EXIT
swiftc Sources/Models.swift Sources/DownloadPolicy.swift Sources/Destination.swift Sources/Backend.swift Sources/EngineUpdater.swift Sources/RuntimeSupport.swift Tests/RuntimeSupportTests.swift -o "$output"
"$output"
