#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# 其它会话的文档变更不影响打包；应用的构建输入必须已经提交。
if [ -n "$(git status --porcelain -- Sources Resources Tests build.sh check.sh check-displays.sh check-performance.sh package.sh 试用说明.md)" ]; then
  echo "应用构建输入尚未提交，请先精确提交后打包。" >&2
  exit 1
fi
revision=$(git rev-parse HEAD)
bash build.sh
package_dir="build/packages/$revision"
mkdir -p "$package_dir"
archive="$package_dir/ccShort-0.1.0-dev-arm64.zip"
if [ -e "$archive" ]; then
  echo "同版本试用包已存在，请核对已有清单，不覆盖。" >&2
  exit 1
fi
codesign --verify --deep --strict build/ccShort.app
/usr/bin/ditto -c -k --keepParent --sequesterRsrc build/ccShort.app "$archive"
cp 试用说明.md "$package_dir/试用说明.md"
python3 - "$revision" "$archive" <<'PY'
import hashlib,json,pathlib,subprocess,sys
revision,archive=sys.argv[1:]; path=pathlib.Path(archive)
files=sorted(pathlib.Path('Sources').glob('*.swift'))+sorted(p for p in pathlib.Path('Resources').iterdir() if p.is_file())+[pathlib.Path('build.sh'),pathlib.Path('package.sh')]
manifest={'source_revision':revision,'package':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,'architecture':'arm64','deployment_target':'macOS14.0','tested_host':subprocess.check_output(['sw_vers','-productVersion'],text=True).strip(),'signing':'本地ad-hoc，非Developer ID公证','installed_verified':False,'public_release':False,'source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(path.parent/'构建清单.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(str(path.resolve()))
PY
