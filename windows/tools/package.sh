#!/usr/bin/env bash
# Builds the Windows preview packages and prints the size evidence required by WIN-06.
#
#   ./tools/package.sh            # framework-dependent + self-contained
#
# The framework-dependent package needs the .NET 8 Desktop Runtime; the self-contained one does not.
#
# Nothing here is signed. The package is a preview build, not a release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
STAMP="$(date +%Y%m%d)"
OUT="$ROOT/dist/packages/$VERSION"
rm -rf "$OUT"
mkdir -p "$OUT"

export DOTNET_CLI_TELEMETRY_OPTOUT=1

copy_common() {
  local target="$1"
  mkdir -p "$target/models/mobile" "$target/LICENSES"
  if [[ -f "$ROOT/models/mobile/det.onnx" ]]; then
    cp "$ROOT/models/mobile/det.onnx" "$ROOT/models/mobile/rec.onnx" "$ROOT/models/mobile/dict.txt" "$target/models/mobile/"
  else
    echo "warn: models/mobile 不存在，包内将不含模型（先运行 tools/fetch-models.sh）" >&2
  fi
  cp "$ROOT/third-party/licenses/"*.txt "$target/LICENSES/"
  cp "$ROOT/docs/使用说明.txt" "$target/README-使用说明.txt"
  cp "$ROOT/THIRD-PARTY-NOTICES.md" "$target/THIRD-PARTY-NOTICES.txt"
  printf 'ccShot Windows preview\ncommit: %s\nbuilt: %s\n' "$COMMIT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$target/BUILD-INFO.txt"
}

publish() {
  local selfcontained="$1" target="$2"
  dotnet publish src/CcShot.Windows/CcShot.Windows.csproj -c Release -r win-x64 \
    --self-contained "$selfcontained" -o "$target" -v quiet --nologo >/dev/null
  # Documentation and symbols are not part of a trial package.
  find "$target" -name '*.pdb' -delete
}

echo "== framework-dependent"
FD="$OUT/fd"
mkdir -p "$FD"
publish false "$FD"
copy_common "$FD"

echo "== self-contained"
SC="$OUT/sc"
mkdir -p "$SC"
publish true "$SC"
copy_common "$SC"

cd "$OUT"
rm -f ccShot-win-x64-fd.zip ccShot-win-x64-sc.zip
zip -qr ccShot-win-x64-fd.zip fd
zip -qr ccShot-win-x64-sc.zip sc

size_of() { du -sk "$1" | awk '{printf "%.1f MB", $1/1024}'; }
size_of_kb() {
  local total models
  total=$(du -sk "$1" | awk '{print $1}')
  models=$(du -sk "$1/models/mobile" 2>/dev/null | awk '{print $1}')
  models=${models:-0}
  awk -v a="$total" -v b="$models" 'BEGIN {printf "%.1f MB", (a-b)/1024}'
}

echo
echo "commit            $COMMIT"
echo "version tag       $VERSION"
if [[ -d "$FD/models/mobile" ]]; then
  echo "models (mobile)   $(size_of "$FD/models/mobile")"
fi
echo "installed fd      $(size_of "$FD")   (app $(size_of_kb "$FD") − models $(size_of "$FD/models/mobile"))"
echo "installed sc      $(size_of "$SC")"
echo "download fd       $(size_of ccShot-win-x64-fd.zip)"
echo "download sc       $(size_of ccShot-win-x64-sc.zip)"
echo
echo "SHA-256:"
shasum -a 256 ccShot-win-x64-fd.zip ccShot-win-x64-sc.zip | sed 's|  |  |'
