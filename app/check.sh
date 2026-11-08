#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh
xcrun swiftc Sources/CaptureGeometry.swift Sources/SelectionHandle.swift Sources/PixelSampler.swift Sources/WindowTarget.swift Tests/GeometryTests.swift -o build/geometry-tests
build/geometry-tests
xcrun swiftc Sources/ScreenshotLayout.swift Tests/ScreenshotLayoutTests.swift -o build/screenshot-layout-tests
build/screenshot-layout-tests
xcrun swiftc Sources/WindowTarget.swift Tests/WindowPlacementTests.swift -o build/window-placement-tests
build/window-placement-tests
xcrun swiftc Sources/AppPreferences.swift Tests/PreferencesTests.swift -o build/preferences-tests
build/preferences-tests
xcrun swiftc Sources/AnnotationModel.swift Sources/AnnotationTextLayout.swift Sources/CaptureGeometry.swift Sources/SelectionHandle.swift Sources/PixelSampler.swift Sources/WindowTarget.swift Sources/CoreAppearance.swift Sources/SelectionView.swift Tests/SelectionOutputTests.swift -o build/selection-output-tests
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
build/ccShort.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --smoke-test "$PWD/build/smoke.json"
cat build/smoke.json
build/ccShort.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --privacy-smoke-test "$PWD/build/privacy-smoke.json"
cat build/privacy-smoke.json
build/ccShort.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --text-smoke-test "$PWD/build/text-smoke.json"
cat build/text-smoke.json

build/ccShort.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --inline-smoke-test "$PWD/build/inline-smoke.json"
cat build/inline-smoke.json

build/ccShort.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --window-inline-smoke-test "$PWD/build/window-inline-smoke.json"
cat build/window-inline-smoke.json

# 钉图使用自制便笺，检查图片与浮动操作层，不写剪贴板。
build/ccShort.app/Contents/MacOS/CcShot \
  --fixture "$PWD/Tests/Fixtures/pin-note.png" \
  --pin-smoke-test "$PWD/build/pin-smoke.json"
cat build/pin-smoke.json
