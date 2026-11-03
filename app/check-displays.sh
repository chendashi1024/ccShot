#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# 临时显示自制样本，测试结束即关闭；仅消费已有屏幕录制权限。
bash build.sh
xcrun swiftc -parse-as-library Tests/DisplayFixtureHost.swift -o build/display-fixture-host
build/CcShot.app/Contents/MacOS/CcShot \
  --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png" \
  --display-smoke-test "$PWD/build/display-smoke.json" \
  --display-fixture-host "$PWD/build/display-fixture-host"
cat build/display-smoke.json
