#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/ModuleCache
sources=()
for file in Sources/*.swift; do
  case "$file" in Sources/App.swift|Sources/*Verification.swift) continue ;; esac
  sources+=("$file")
done
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  -module-cache-path "$PWD/build/ModuleCache" "${sources[@]}" Tests/InteractionTests.swift \
  -o build/interaction-tests
build/interaction-tests "$@"
