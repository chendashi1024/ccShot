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
OUT="$ROOT/dist/packages/$VERSION"
# 每个 .NET 桌面运行时版本都有对应的第三方声明。
RUNTIME_VERSION=8.0.34
export RUNTIME_VERSION
mkdir -p "$(dirname "$OUT")"
STAGING="$(mktemp -d "$(dirname "$OUT")/.package-$VERSION.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

export DOTNET_CLI_TELEMETRY_OPTOUT=1

python3 - <<'PY'
import hashlib
import json
from pathlib import Path

assets = json.loads(Path('models/models.lock.json').read_text())['assets']
for asset in assets:
    path = Path(asset['path'])
    if path.parts[:2] != ('models', 'mobile'):
        continue
    if not path.is_file():
        raise SystemExit(f'缺少 {path}，请运行 tools/fetch-models.sh mobile。')
    data = path.read_bytes()
    if len(data) != asset['bytes'] or hashlib.sha256(data).hexdigest() != asset['sha256']:
        raise SystemExit(f'{path} 与锁定的模型不一致。')
PY

copy_common() {
  local target="$1"
  mkdir -p "$target/models/mobile" "$target/LICENSES"
  cp "$ROOT/models/mobile/det.onnx" "$ROOT/models/mobile/rec.onnx" "$ROOT/models/mobile/dict.txt" "$target/models/mobile/"
  cp "$ROOT/../LICENSE" "$target/LICENSES/ccshot-LICENSE.txt"
  cp "$ROOT/third-party/licenses/"*.txt "$target/LICENSES/"
  cp "$ROOT/docs/使用说明.txt" "$target/README-使用说明.txt"
  cp "$ROOT/THIRD-PARTY-NOTICES.md" "$target/THIRD-PARTY-NOTICES.txt"
  printf 'ccShot Windows preview\ncommit: %s\nbuilt: %s\n' "$COMMIT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$target/BUILD-INFO.txt"
}

publish() {
  local selfcontained="$1" target="$2"
  set --
  if [[ "$selfcontained" == true ]]; then
    set -- "-p:RuntimeFrameworkVersion=$RUNTIME_VERSION"
  fi
  dotnet publish src/CcShot.Windows/CcShot.Windows.csproj -c Release -r win-x64 \
    --self-contained "$selfcontained" -o "$target" -v quiet --nologo "$@"
  # Documentation and symbols are not part of a trial package.
  find "$target" -name '*.pdb' -delete
}

echo "== framework-dependent"
FD="$STAGING/fd"
mkdir -p "$FD"
publish false "$FD"
copy_common "$FD"

echo "== self-contained"
SC="$STAGING/sc"
mkdir -p "$SC"
publish true "$SC"
copy_common "$SC"

python3 - "$SC" <<'PY'
import json
import os
import shutil
import sys
from pathlib import Path

target = Path(sys.argv[1])
assets = json.loads(Path('src/CcShot.Windows/obj/project.assets.json').read_text())
packs = json.loads((target / 'CcShot.deps.json').read_text())['libraries']
for product, files in (
    ('Microsoft.NETCore.App.Runtime.win-x64', ('LICENSE.TXT', 'THIRD-PARTY-NOTICES.TXT')),
    ('Microsoft.WindowsDesktop.App.Runtime.win-x64', ('LICENSE',)),
):
    version = os.environ['RUNTIME_VERSION']
    if f'runtimepack.{product}/{version}' not in packs:
        raise SystemExit(f'自包含包的运行时与许可版本不一致：{product} {version}')
    for name in files:
        sources = [Path(folder) / product.lower() / version / name for folder in assets['packageFolders']]
        source = next((path for path in sources if path.is_file()), None)
        if source is None:
            raise SystemExit(f'找不到 {product} {version} 的许可文件 {name}')
        shutil.copyfile(source, target / 'LICENSES' / f'{product}-{Path(name).stem}.txt')
notices = Path('third-party/licenses/dotnet-desktop') / os.environ['RUNTIME_VERSION']
for component in ('wpf', 'winforms'):
    name = f'{component}-THIRD-PARTY-NOTICES.txt'
    shutil.copyfile(notices / name, target / 'LICENSES' / name)
PY

cd "$STAGING"
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
cd "$ROOT"
if [[ -e "$OUT" ]]; then
  OUT="$OUT-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mv "$STAGING" "$OUT"
echo "包目录 $OUT"
