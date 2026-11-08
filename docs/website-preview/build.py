"""生成可离线打开的单文件官网设计稿，可选同步到当前会话预览目录。"""
from pathlib import Path
import argparse
import base64
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--inline-output', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent
fragment = (root / 'preview.html').read_text()
for asset in sorted(set(re.findall(r'assets/[a-z-]+\.(?:png|jpg)', fragment))):
    path = root / asset
    mime = 'image/png' if path.suffix == '.png' else 'image/jpeg'
    fragment = fragment.replace(asset, f'data:{mime};base64,' + base64.b64encode(path.read_bytes()).decode())
assert len(fragment.encode()) < 1_000_000, '会话预览需保持小于 1 MB'
document = '<!doctype html>\n<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="description" content="ccShot 是免费的 macOS 原生截图工具。截图后直接选字，支持标注、保存与桌面钉图。"><link rel="canonical" href="https://ccshot.app/"><title>ccShot · 截完图，直接选字</title><style>body{margin:0;background:#fafbf7}</style></head><body>\n' + fragment + '\n</body></html>\n'
(root / 'index.html').write_text(document)
if args.inline_output:
    if not args.inline_output.parent.is_dir():
        raise SystemExit('请使用当前会话已提供的预览目录')
    args.inline_output.write_text(fragment)
print(f'离线页面已生成：{len(document.encode())} 字节')
