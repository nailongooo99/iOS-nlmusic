#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -swift-version 5 -O NailongMusic/Core/Models.swift NailongMusic/Core/Lyrics.swift NailongMusic/Core/LXModels.swift tests/CoreTests.swift -o "$tmp/core-tests"
"$tmp/core-tests"
