"""生成可离线打开的单文件官网，并写出可部署的静态目录。"""
from pathlib import Path
import argparse
import base64
import json
import re
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--inline-output', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent
repo = root.parents[1]
fragment = (root / 'preview.html').read_text()
for asset in sorted(set(re.findall(r'assets/[a-z-]+\.(?:png|jpg)', fragment))):
    path = root / asset
    mime = 'image/png' if path.suffix == '.png' else 'image/jpeg'
    fragment = fragment.replace(asset, f'data:{mime};base64,' + base64.b64encode(path.read_bytes()).decode())
assert len(fragment.encode()) < 1_000_000, '会话预览需保持小于 1 MB'

EXITS = {
    'github': '/go/github?to=repo',
    'release': '/go/github?to=release',
    'download': '/go/download',
    'download-github': '/go/download?source=github',
}

def rewrite_exits(html):
    def repl(match):
        tag = match.group(0)
        kind = re.search(r'data-exit="([^"]+)"', tag).group(1)
        if kind not in EXITS:
            raise SystemExit(f'未知 data-exit：{kind}')
        if 'href="' not in tag:
            raise SystemExit('data-exit 链接缺少 href')
        return re.sub(r'href="[^"]*"', f'href="{EXITS[kind]}"', tag, count=1)
    return re.sub(r'<a\b[^>]*\bdata-exit="[^"]+"[^>]*>', repl, html)

structured = {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    'name': 'ccShot',
    'operatingSystem': 'macOS',
    'applicationCategory': 'UtilitiesApplication',
    'softwareVersion': '0.1.2',
    'url': 'https://ccshot.app/',
    'downloadUrl': 'https://github.com/chendashi1024/ccShot/releases/download/v0.1.2/ccShot-0.1.2-macos-arm64.dmg',
    'license': 'https://opensource.org/licenses/MIT',
    'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
}
head = (
    '<meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<meta name="description" content="ccShot 是免费的 macOS 原生截图工具。截完图可以直接选字，也能标注、保存和钉在桌面上。">'
    '<meta name="robots" content="index,follow">'
    '<meta name="referrer" content="strict-origin-when-cross-origin">'
    '<link rel="canonical" href="https://ccshot.app/">'
    '<meta property="og:type" content="website">'
    '<meta property="og:locale" content="zh_CN">'
    '<meta property="og:site_name" content="ccShot">'
    '<meta property="og:title" content="ccShot · 截完图，直接选字">'
    '<meta property="og:description" content="免费的 macOS 原生截图工具。v0.1.2 公开预览版只提供 Apple Silicon（arm64），截图后可以直接选字、标注和钉图。">'
    '<meta property="og:url" content="https://ccshot.app/">'
    '<meta name="twitter:card" content="summary_large_image">'
    '<meta name="theme-color" content="#2b664f">'
    '<title>ccShot · 截完图，直接选字</title>'
    '<script type="application/ld+json">' + json.dumps(structured, ensure_ascii=False, separators=(',', ':')) + '</script>'
    '<style>body{margin:0;background:#fafbf7}</style>'
)
deploy_head = head + '<link rel="icon" href="/icon.png" type="image/png"><meta property="og:image" content="https://ccshot.app/og.jpg"><meta name="twitter:image" content="https://ccshot.app/og.jpg">'

def document(body, head_html):
    return '<!doctype html>\n<html lang="zh-CN"><head>' + head_html + '</head><body>\n' + body + '\n</body></html>\n'

offline = document(fragment, head)
(root / 'index.html').write_text(offline)
if args.inline_output:
    if not args.inline_output.parent.is_dir():
        raise SystemExit('请使用当前会话已提供的预览目录')
    args.inline_output.write_text(fragment)

public = repo / 'website' / 'public'
public.mkdir(parents=True, exist_ok=True)
(public / 'index.html').write_text(document(rewrite_exits(fragment), deploy_head))
shutil.copyfile(root / 'assets' / 'icon.png', public / 'icon.png')
shutil.copyfile(root / 'assets' / 'arrow.jpg', public / 'og.jpg')
(public / 'robots.txt').write_text('User-agent: *\nAllow: /\n\nSitemap: https://ccshot.app/sitemap.xml\n')
(public / 'sitemap.xml').write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    '  <url><loc>https://ccshot.app/</loc></url>\n'
    '</urlset>\n'
)
(public / '404.html').write_text(
    '<!doctype html>\n<html lang="zh-CN"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<meta name="robots" content="noindex"><title>找不到页面 · ccShot</title>'
    '<style>body{margin:0;background:#fafbf7;color:#23382d;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}'
    'main{max-width:640px;margin:18vh auto;padding:0 24px}a{color:#2b664f}</style></head><body><main>'
    '<h1>这个地址没有页面。</h1><p><a href="/">回到首页</a> · <a href="/go/github?to=repo">GitHub 标星</a></p>'
    '</main></body></html>\n'
)
print(f'离线页面已生成：{len(offline.encode())} 字节')
print(f'部署目录：{public}')
