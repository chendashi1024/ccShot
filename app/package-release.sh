#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

version=$(<../VERSION)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION 应为 MAJOR.MINOR.PATCH。" >&2
  exit 1
fi
if [[ "${1:-$version}" != "$version" ]]; then
  echo "打包版本必须与 VERSION 中的 $version 一致。" >&2
  exit 1
fi
if [ -n "$(git status --porcelain -- Sources Resources build.sh package-release.sh ../LICENSE ../VERSION)" ]; then
  echo "请先提交构建输入，再生成发行包。" >&2
  exit 1
fi

revision=$(git rev-parse HEAD)
name="ccShot-$version-macos-arm64"
output_dir="$PWD/build/releases/$revision/$name"
if [ -e "$output_dir" ]; then
  echo "同一提交和版本的发行包已存在。" >&2
  exit 1
fi

CCSHOT_VERSION="$version" CCSHOT_SIGNING_IDENTITY=- bash build.sh
codesign --verify --deep --strict build/ccShot.app
work_dir=$(mktemp -d "$PWD/build/.release.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
mkdir "$work_dir/image"
ditto build/ccShot.app "$work_dir/image/ccShot.app"
ln -s /Applications "$work_dir/image/Applications"
cp ../LICENSE "$work_dir/image/LICENSE"
hdiutil create -quiet -volname ccShot -srcfolder "$work_dir/image" -format UDZO "$work_dir/$name.dmg"
hdiutil verify -quiet "$work_dir/$name.dmg"
(cd "$work_dir" && shasum -a 256 "$name.dmg" > "$name.dmg.sha256")

mkdir -p "$(dirname "$output_dir")"
mkdir "$output_dir"
mv "$work_dir/$name.dmg" "$work_dir/$name.dmg.sha256" "$output_dir/"
printf '%s\n' "$output_dir/$name.dmg"
