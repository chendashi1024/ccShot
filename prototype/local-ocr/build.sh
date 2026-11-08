#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/ModuleCache build/ccShotPrototype.app/Contents/MacOS
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
  -module-cache-path "$PWD/build/ModuleCache" Sources/*.swift \
  -o build/ccShotPrototype.app/Contents/MacOS/ccShotPrototype
cat > build/ccShotPrototype.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.ccshot.ocr-prototype</string>
<key>CFBundleName</key><string>ccShotPrototype</string>
<key>CFBundleExecutable</key><string>ccShotPrototype</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - build/ccShotPrototype.app
printf '%s\n' "$PWD/build/ccShotPrototype.app"
