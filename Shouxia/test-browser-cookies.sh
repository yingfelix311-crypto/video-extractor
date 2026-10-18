#!/bin/sh
set -eu
cd "$(dirname "$0")"
output=$(mktemp -t shouxia-browser-cookies)
trap 'rm -f "$output"' EXIT
swiftc Sources/BrowserCookies.swift Sources/BrowserCookieReader.swift Tests/BrowserCookieTests.swift -lsqlite3 -framework Security -o "$output"
"$output"
