#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh
xcrun swiftc Sources/CaptureGeometry.swift Sources/SelectionHandle.swift Sources/PixelSampler.swift Sources/WindowTarget.swift Tests/GeometryTests.swift -o build/geometry-tests
build/geometry-tests
xcrun swiftc Sources/AppPreferences.swift Tests/PreferencesTests.swift -o build/preferences-tests
build/preferences-tests
xcrun swiftc Sources/AnnotationModel.swift Sources/AnnotationTextLayout.swift Sources/CaptureGeometry.swift Sources/SelectionHandle.swift Sources/PixelSampler.swift Sources/WindowTarget.swift Sources/SelectionView.swift Tests/SelectionOutputTests.swift -o build/selection-output-tests
build/selection-output-tests
xcrun swiftc Sources/AnnotationModel.swift Sources/AnnotationTextLayout.swift Sources/AnnotationRenderer.swift Sources/AnnotationPreferences.swift Sources/AppPreferences.swift Sources/PixelSampler.swift Tests/AnnotationTests.swift -o build/annotation-tests
xcrun swiftc Sources/AnnotationModel.swift Sources/AnnotationTextLayout.swift Sources/AnnotationRenderer.swift Sources/PixelSampler.swift Tests/SolidMaskTests.swift -o build/solid-mask-tests
build/solid-mask-tests
build/annotation-tests
xcrun swiftc Sources/AnnotationModel.swift Sources/AnnotationTextLayout.swift Tests/TextAnnotationTests.swift -o build/text-tests
build/text-tests
xcrun swiftc Sources/SafeTextImage.swift Tests/SafeTextGeometryTests.swift -o build/privacy-geometry-tests
build/privacy-geometry-tests
xcrun swiftc Sources/ImageEncoding.swift Tests/ImageEncodingTests.swift -o build/image-encoding-tests
build/image-encoding-tests > build/image-encoding.json
build/CcShot.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --smoke-test "$PWD/build/smoke.json"
cat build/smoke.json
build/CcShot.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --privacy-smoke-test "$PWD/build/privacy-smoke.json"
cat build/privacy-smoke.json
build/CcShot.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --text-smoke-test "$PWD/build/text-smoke.json"
cat build/text-smoke.json
