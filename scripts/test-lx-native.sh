#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Apple native LX smoke test requires macOS/Xcode; not run on Linux."
  exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -swift-version 5 \
  NailongMusic/Core/Models.swift \
  NailongMusic/Core/LXModels.swift \
  NailongMusic/Services/LXNetwork.swift \
  NailongMusic/Services/LXCrypto.swift \
  NailongMusic/Services/LXRuntime.swift \
  tests/LXNativeTests.swift \
  -framework JavaScriptCore -framework Security -o "$tmp/lx-native-tests"
"$tmp/lx-native-tests"
