#!/usr/bin/env bash
# 生成框架依赖和自包含两个 Windows 预览包，并记录大小和校验值。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
OUT="$ROOT/dist/packages/$VERSION"
# 每个 .NET 桌面运行时版本都有对应的第三方声明。
RUNTIME_VERSION=8.0.34
export RUNTIME_VERSION
PYTHON="${PYTHON:-python3}"
mkdir -p "$(dirname "$OUT")"
STAGING="$(mktemp -d "$(dirname "$OUT")/.package-$VERSION.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export PYTHONUTF8=1

"$PYTHON" - <<'PY'
import hashlib
import json
from pathlib import Path

assets = json.loads(Path('models/models.lock.json').read_text(encoding='utf-8'))['assets']
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
  cp "$ROOT/docs/使用说明.txt" "$target/README.txt"
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
  # 试用包不附调试符号。
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

"$PYTHON" - "$SC" <<'PY'
import json
import os
import shutil
import sys
from pathlib import Path

target = Path(sys.argv[1])
assets = json.loads(Path('src/CcShot.Windows/obj/project.assets.json').read_text(encoding='utf-8-sig'))
packs = json.loads((target / 'CcShot.deps.json').read_text(encoding='utf-8-sig'))['libraries']
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

"$PYTHON" "$ROOT/tools/stage-vc-runtime.py" "$FD" "$SC"

cd "$STAGING"
"$PYTHON" - <<'PY'
import hashlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

with Path("SHA256SUMS.txt").open("w", encoding="ascii", newline="\n") as sums:
    for kind in ("fd", "sc"):
        name = f"ccShot-win-x64-{kind}.zip"
        with ZipFile(name, "w", ZIP_DEFLATED) as archive:
            for path in sorted(Path(kind).rglob("*")):
                if path.is_file():
                    archive.write(path, path.as_posix())
        digest = hashlib.sha256()
        with Path(name).open("rb") as package:
            for chunk in iter(lambda: package.read(1024 * 1024), b""):
                digest.update(chunk)
        sums.write(f"{digest.hexdigest()}  {name}\n")
PY

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
cat SHA256SUMS.txt
cd "$ROOT"
if [[ -e "$OUT" ]]; then
  OUT="$OUT-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mv "$STAGING" "$OUT"
echo "包目录 $OUT"
