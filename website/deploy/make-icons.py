"""从现有应用图标生成网站图标，需要 Pillow；不改动稳定的 icon.png。"""
from pathlib import Path
from PIL import Image

repo = Path(__file__).resolve().parents[2]
public = repo / 'website/public'
with Image.open(repo / 'app/Resources/AppIcon.icns') as source:
    source.load()
    image = source.convert('RGBA')
    assert image.size == (1024, 1024)
    image.save(public / 'favicon.ico', sizes=[(n, n) for n in (16, 32, 48, 64, 128, 256)])
    for name, size in [('apple-touch-icon.png', 180), ('icon-192.png', 192)]:
        image.resize((size, size), Image.Resampling.LANCZOS).save(public / name, optimize=True)
print('已从 AppIcon.icns 生成 ICO、180 PNG 和 192 PNG')
