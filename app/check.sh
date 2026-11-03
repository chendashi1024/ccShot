#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh
xcrun swiftc Sources/CaptureGeometry.swift Sources/SelectionHandle.swift Sources/PixelSampler.swift Sources/WindowTarget.swift Tests/GeometryTests.swift -o build/geometry-tests
build/geometry-tests
xcrun swiftc Sources/AppPreferences.swift Tests/PreferencesTests.swift -o build/preferences-tests
build/preferences-tests
xcrun swiftc Sources/AnnotationModel.swift Sources/AnnotationRenderer.swift Sources/AnnotationPreferences.swift Sources/AppPreferences.swift Sources/PixelSampler.swift Tests/AnnotationTests.swift -o build/annotation-tests
build/annotation-tests
build/CcShot.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --smoke-test "$PWD/build/smoke.json"
cat build/smoke.json
