#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh
xcrun swiftc Sources/CaptureGeometry.swift Sources/SelectionHandle.swift Sources/PixelSampler.swift Tests/GeometryTests.swift -o build/geometry-tests
build/geometry-tests
build/CcShot.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --smoke-test "$PWD/build/smoke.json"
cat build/smoke.json
