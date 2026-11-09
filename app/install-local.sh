#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

source_app="$PWD/build/ccShot.app"
target_app=/Applications/ccShot.app
bundle_id=com.ccshot.dev

if [[ ! -d "$source_app" ]]; then
  echo "请先运行 bash app/build.sh。" >&2
  exit 1
fi

# 先验证并准备完整的应用包，再退出旧版和重置授权。
stage=/Applications/.ccShot-install
mkdir "$stage"
cleanup() {
  if [[ -d "$stage/previous.app" && ! -e "$target_app" ]]; then
    mv "$stage/previous.app" "$target_app" || return 1
  fi
  rm -rf "$stage"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

/usr/bin/ditto "$source_app" "$stage/ccShot.app"
/usr/bin/codesign --verify --deep --strict -R="identifier \"$bundle_id\"" "$stage/ccShot.app"

if [[ -e "$target_app" ]]; then
  /usr/bin/osascript -l JavaScript - "$bundle_id" "$target_app" <<'JXA'
ObjC.import('AppKit');

function run([bundleId, targetPath]) {
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(bundleId);
  for (let index = 0; index < apps.count; index++) {
    const app = apps.objectAtIndex(index);
    if (ObjC.unwrap(app.bundleURL.path) !== targetPath) continue;
    app.terminate;
  }
}
JXA
  process_pattern='^/Applications/ccShot\.app/Contents/MacOS/ccShot([[:space:]]|$)'
  attempts=0
  while /usr/bin/pgrep -u "$(id -u)" -f "$process_pattern" >/dev/null; do
    if (( attempts >= 50 )); then
      echo "ccShot 尚未退出，请退出后重试。" >&2
      exit 1
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  /usr/bin/tccutil reset ScreenCapture "$bundle_id"
  mv "$target_app" "$stage/previous.app"
fi

mv "$stage/ccShot.app" "$target_app"
/usr/bin/open "$target_app"
echo "ccShot 已安装。首次截图时，请按 macOS 提示允许屏幕录制，然后重新打开 ccShot。"
