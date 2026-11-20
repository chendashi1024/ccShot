"""从共同源生成离线预览与正式首页；仅写本地文件，不发布。"""
from pathlib import Path
import argparse
import base64
import html
import json
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--inline-output', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent
repo = root.parents[1]
public = repo / 'website/public'
version = (repo / 'VERSION').read_text().strip()
fragment = (root / 'preview.html').read_text().replace('{{VERSION}}', version)
mac = f'https://download.ccshot.app/ccShot-{version}-macos-arm64.dmg'
windows = f'https://download.ccshot.app/ccShot-{version}-windows-x64.zip'
github = 'https://github.com/chendashi1024/ccShot'

def plain(value):
    return html.unescape(re.sub(r'<[^>]+>', '', value)).strip()

# FAQ 结构化内容直接来自可见问答，避免维护两份答案。
faq = re.search(r'<section id="cc-faq"[\s\S]*?</section>', fragment)
assert faq, '缺少可见 FAQ'
questions = re.findall(r'<dt>(.*?)</dt><dd>(.*?)</dd>', faq[0], re.S)
assert questions, 'FAQ 内容为空'
structured = [
    {
        '@context': 'https://schema.org', '@type': 'SoftwareApplication',
        '@id': 'https://ccshot.app/#software', 'name': 'ccShot',
        'description': '免费、MIT 开源的 macOS 和 Windows 截图识字工具，支持本机离线识字、标注、保存与桌面钉图，无需账号或 API Key。',
        'operatingSystem': ['macOS 14+ (Apple Silicon)', 'Windows x64'],
        'applicationCategory': 'UtilitiesApplication', 'softwareVersion': version,
        'url': 'https://ccshot.app/', 'downloadUrl': [mac, windows],
        'sameAs': [github], 'image': 'https://ccshot.app/icon-192.png',
        'license': 'https://opensource.org/licenses/MIT',
        'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
    },
    {
        '@context': 'https://schema.org', '@type': 'WebSite',
        '@id': 'https://ccshot.app/#website', 'name': 'ccShot',
        'url': 'https://ccshot.app/', 'inLanguage': 'zh-CN', 'sameAs': [github],
    },
    {
        '@context': 'https://schema.org', '@type': 'FAQPage',
        '@id': 'https://ccshot.app/#cc-faq',
        'mainEntity': [{'@type': 'Question', 'name': plain(q),
                        'acceptedAnswer': {'@type': 'Answer', 'text': plain(a)}}
                       for q, a in questions],
    },
]
jsonld = '\n'.join('<script type="application/ld+json">' +
                   json.dumps(item, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c') +
                   '</script>' for item in structured)
head = (root / 'head.html').read_text().replace('{{STRUCTURED_DATA}}', jsonld)

def render(online):
    body = fragment
    for asset in sorted(set(re.findall(r'assets/[a-z-]+\.(?:png|jpg)', body))):
        path = root / asset
        # 正式页保持已有品牌 PNG 的字节，离线页保留原预览图标。
        if online and asset == 'assets/icon.png':
            path = public / 'icon.png'
        mime = 'image/png' if path.suffix == '.png' else 'image/jpeg'
        body = body.replace(asset, f'data:{mime};base64,' + base64.b64encode(path.read_bytes()).decode())
    if online:
        routes = {mac: '/go/download', windows: '/go/download?platform=windows',
                  github: '/go/github?to=repo', github + f'/releases/tag/v{version}': '/go/github?to=release'}
        for url, route in routes.items():
            body = body.replace(f'href="{url}"', f'href="{route}"')
        body = re.sub(r'(<a\b[^>]*href="/go/download[^"]*") target="_blank" rel="noopener"', r'\1', body)
    # 图标独立存放；离线文件使用仓库内相对路径，不追加 base64。
    page_head = head.replace('{{ICON_BASE}}', '' if online else '../../website/public')
    document = '<!doctype html>\n<html lang="zh-CN"><head>\n' + page_head + '</head><body>\n' + body + '\n</body></html>\n'
    assert len(document.encode()) < 1_000_000, '页面需保持小于 1 MB'
    return document, body

offline, inline = render(False)
(root / 'index.html').write_text(offline)
online, _ = render(True)
(public / 'index.html').write_text(online)
if args.inline_output:
    if not args.inline_output.parent.is_dir():
        raise SystemExit('请使用当前会话已提供的预览目录')
    args.inline_output.write_text(inline)
print(f'离线页面：{len(offline.encode())} 字节；正式首页：{len(online.encode())} 字节')
