#!/usr/bin/env bash
# 生成一个自包含的 Windows x64 ZIP 和校验文件。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION=$(<"$ROOT/../VERSION")
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION 应为 MAJOR.MINOR.PATCH。" >&2
  exit 1
fi
NAME="ccShot-$VERSION-windows-x64"
REVISION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
OUT="$ROOT/dist/packages/$REVISION"
# 每个 .NET 桌面运行时版本都有对应的第三方声明。
RUNTIME_VERSION=8.0.34
export RUNTIME_VERSION
PYTHON="${PYTHON:-python3}"
mkdir -p "$(dirname "$OUT")"
STAGING="$(mktemp -d "$(dirname "$OUT")/.package-$REVISION.XXXXXX")"
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

TARGET="$STAGING/$NAME"
dotnet publish src/ccShot.Windows/ccShot.Windows.csproj -c Release -r win-x64 \
  --self-contained true -p:RuntimeFrameworkVersion="$RUNTIME_VERSION" -o "$TARGET" -v quiet --nologo
find "$TARGET" -name '*.pdb' -delete

mkdir -p "$TARGET/models/mobile" "$TARGET/LICENSES"
cp "$ROOT/models/mobile/det.onnx" "$ROOT/models/mobile/rec.onnx" "$ROOT/models/mobile/dict.txt" "$TARGET/models/mobile/"
cp "$ROOT/../LICENSE" "$TARGET/LICENSES/ccShot-LICENSE.txt"
cp "$ROOT/third-party/licenses/"*.txt "$TARGET/LICENSES/"
cp "$ROOT/docs/使用说明.txt" "$TARGET/README.txt"
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$TARGET/THIRD-PARTY-NOTICES.txt"
printf 'ccShot Windows\nversion: %s\ncommit: %s\nbuilt: %s\n' \
  "$VERSION" "$COMMIT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TARGET/BUILD-INFO.txt"

"$PYTHON" - "$TARGET" <<'PY'
import json
import os
import shutil
import sys
from pathlib import Path

target = Path(sys.argv[1])
assets = json.loads(Path('src/ccShot.Windows/obj/project.assets.json').read_text(encoding='utf-8-sig'))
packs = json.loads((target / 'ccShot.deps.json').read_text(encoding='utf-8-sig'))['libraries']
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

"$PYTHON" "$ROOT/tools/stage-vc-runtime.py" "$TARGET"

cd "$STAGING"
"$PYTHON" - "$NAME" "$OUT" <<'PY'
import hashlib
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

target, output = map(Path, sys.argv[1:])
deliverables = Path("package")
deliverables.mkdir()
package = deliverables / f"{target.name}.zip"
with ZipFile(package, "w", ZIP_DEFLATED) as archive:
    for path in sorted(target.rglob("*")):
        if path.is_file():
            archive.write(path, path.as_posix())

digest = hashlib.sha256()
with package.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
checksum = f"{digest.hexdigest()}  {package.name}"
with (deliverables / "SHA256SUMS.txt").open("w", encoding="ascii", newline="\n") as sums:
    sums.write(checksum + "\n")
size = package.stat().st_size

if output.exists():
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = output.with_name(f"{output.name}-{stamp}-{os.getpid()}")
deliverables.rename(output)
print(f"{package.name}  {size:,} 字节（{size / 1_000_000:.2f} MB）")
print(f"SHA-256  {checksum}")
print(f"包目录 {output}")
PY
