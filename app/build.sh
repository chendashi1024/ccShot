#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/ModuleCache build/CcShot.app/Contents/MacOS
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
  -module-cache-path "$PWD/build/ModuleCache" Sources/*.swift \
  -o build/CcShot.app/Contents/MacOS/CcShot
cat > build/CcShot.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ccshot.dev</string>
<key>CFBundleName</key><string>CcShot</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
<key>CFBundleExecutable</key><string>CcShot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0-dev</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - build/CcShot.app
