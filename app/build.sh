#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source_revision=$(git rev-parse HEAD)
version=${CCSHOT_VERSION:-0.1.0-dev}
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-dev)?$ ]]; then
  echo "版本号应为 MAJOR.MINOR.PATCH，可带 -dev。" >&2
  exit 1
fi
bundle_version=${version%-dev}
mkdir -p build/ModuleCache build/ccShot.app/Contents/{MacOS,Resources}
cp Resources/AppIcon.icns Resources/StatusIcon.pdf build/ccShot.app/Contents/Resources/
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
  -module-cache-path "$PWD/build/ModuleCache" Sources/*.swift \
  -o build/ccShot.app/Contents/MacOS/ccShot
cat > build/ccShot.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ccshot.dev</string>
<key>CFBundleName</key><string>ccShot</string>
<key>CFBundleDisplayName</key><string>ccShot</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
<key>CFBundleExecutable</key><string>ccShot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$bundle_version</string>
<key>CFBundleShortVersionString</key><string>$bundle_version</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :ccShotSourceRevision string $source_revision" build/ccShot.app/Contents/Info.plist
codesign --force --sign "${CCSHOT_SIGNING_IDENTITY:-${CCSHORT_SIGNING_IDENTITY:--}}" build/ccShot.app
