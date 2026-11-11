#!/usr/bin/env python3
"""Generates the Windows OCR fixtures: known text, known per-character boxes.

The macOS prototype set (prototype/local-ocr/results/2026-11-03-native-01) has 32 images with text truth
but no character positions, and it has no English-only, code-only or genuinely small-text sample. This
script fills that gap with images where every character's advance width is known, so character boxes and
drag-selection ranges can be scored instead of eyeballed.

    python3 tools/gen_windows_fixtures.py [--out testdata/windows-01]

Requires Pillow. Fonts are resolved from the system; the chosen font file and size are recorded in the
manifest so a run can be reproduced on another machine.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT_CANDIDATES_CN = [
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/Supplemental/Songti.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
]
FONT_CANDIDATES_MONO = [
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Supplemental/Courier New.ttf",
]
FONT_CANDIDATES_LATIN = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
]


def pick(candidates: list[str]) -> str:
    for path in candidates:
        if os.path.exists(path):
            return path
    raise SystemExit("找不到可用字体，请在本机安装其中一种：" + ", ".join(candidates))


# Each entry: id prefix, category, text lines, font kind, point size, pixel scale, colours, condition label.
CASES = [
    (
        "en", "纯英文", [
            "The quick brown fox jumps over the lazy dog.",
            "Screenshots should be selectable without OCR switches.",
            "Copy only what the pointer covers.",
        ], "latin", 18, 1, ("#ffffff", "#1f2933"), "英文18pt@1x",
    ),
    (
        "en2x", "纯英文", [
            "Release notes: fixed the stale text cache.",
            "Retina sample rendered at 2x for sharpness.",
        ], "latin", 18, 2, ("#ffffff", "#1f2933"), "英文18pt@2x",
    ),
    (
        "code", "代码", [
            "var page = engine.Recognize(image);",
            "if (page.HasText) Clipboard.SetText(page.Text);",
            "return page.Lines.Count > 0;",
        ], "mono", 15, 1, ("#0f172a", "#e2e8f0"), "代码15pt@1x深色",
    ),
    (
        "code2x", "代码", [
            "for (int i = 0; i < glyphs.Count; i++) {",
            "    Console.WriteLine(glyphs[i].Box);",
            "}",
        ], "mono", 15, 2, ("#ffffff", "#111827"), "代码15pt@2x",
    ),
    (
        "small", "小字", [
            "小字十像素，用于检验最小可读字高。",
            "第二行：识别与选取应保持同步。",
        ], "cn", 10, 1, ("#ffffff", "#111111"), "中文10pt@1x",
    ),
    (
        "small11", "小字", [
            "十一像素的中文也需要逐字选取。",
            "标点、数字 12345 和英文 mixed 混排。",
        ], "cn", 11, 1, ("#ffffff", "#111111"), "中文11pt@1x",
    ),
    (
        "mixed", "中英混排", [
            "用 ccShot 截图后直接拖选文字，Ctrl+C 复制。",
            "PaddleOCR 在本地 CPU 运行，无需网络。",
        ], "cn", 16, 1, ("#ffffff", "#1f2933"), "中英16pt@1x",
    ),
    (
        "lowcontrast", "低对比", [
            "低对比背景上的文字也要能选。",
            "第二次尝试仍需保持一致。",
        ], "cn", 14, 1, ("#e8e8e8", "#b4b4b4"), "低对比14pt@1x",
    ),
    (
        "punct", "标点", [
            "括号（）引号「」逗号，句号。",
            "数字 3.14159 与 100% 都要准确。",
        ], "cn", 14, 1, ("#ffffff", "#1f2933"), "标点14pt@1x",
    ),
    (
        "dense", "密集", [
            "第一列文字与第二列文字靠得很近，仍然逐列识别。",
            "这一行紧接着上一行，行距只有半行。",
        ], "cn", 12, 1, ("#ffffff", "#111111"), "中文12pt@1x紧行距",
    ),
]


def font_for(kind: str, size: int) -> ImageFont.FreeTypeFont:
    path = {"cn": FONT_CANDIDATES_CN, "mono": FONT_CANDIDATES_MONO, "latin": FONT_CANDIDATES_LATIN}[kind]
    chosen = pick(path)
    return ImageFont.truetype(chosen, size)


def render(case, out_dir: str, index: int) -> dict:
    prefix, category, lines, kind, size, scale, (bg, fg), condition = case
    px = size * scale
    font = font_for(kind, px)
    ascent, descent = font.getmetrics()
    line_height = int((ascent + descent) * 1.45)
    padding = int(px * 1.2)

    # Measure first, then create the canvas so every line fits.
    widths = [font.getlength(line) for line in lines]
    width = int(max(widths) + padding * 2)
    height = int(line_height * len(lines) + padding * 2)

    image = Image.new("RGB", (width, height), bg)
    draw = ImageDraw.Draw(image)

    glyphs = []
    y = padding
    for line in lines:
        draw.text((padding, y), line, font=font, fill=fg)
        baseline_top = y + ascent - ascent  # draw.text anchors at the ascender line box
        x_cursor = padding
        for ch in line:
            advance = font.getlength(ch)
            if not ch.isspace():
                bbox = font.getbbox(ch)
                # Ink box: left/top relative to the glyph cell, so it stays inside the advance cell.
                gx = x_cursor + bbox[0]
                gy = baseline_top + bbox[1]
                gw = max(1.0, bbox[2] - bbox[0])
                gh = max(1.0, bbox[3] - bbox[1])
                glyphs.append({"char": ch, "x": round(gx, 2), "y": round(gy, 2), "w": round(gw, 2), "h": round(gh, 2)})
            x_cursor += advance
        y += line_height

    name = f"{index:02d}-{prefix}.png"
    path = os.path.join(out_dir, name)
    image.save(path, "PNG")
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()

    return {
        "id": f"{index:02d}-{prefix}",
        "file": name,
        "text": "\n".join(lines),
        "truthLines": lines,
        "category": category,
        "condition": condition,
        "font": os.path.basename(font.path),
        "fontSize": size,
        "scale": scale,
        "width": width,
        "height": height,
        "sha256": digest,
        "glyphs": glyphs,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "testdata", "windows-01"))
    args = parser.parse_args()
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    manifest = []
    for i, case in enumerate(CASES, start=1):
        entry = render(case, out_dir, i)
        manifest.append(entry)
        print(f"{entry['id']:<12} {entry['width']}x{entry['height']}  {entry['condition']}  glyphs={len(entry['glyphs'])}")

    manifest_path = os.path.join(out_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
    print(f"\nmanifest: {manifest_path}  ({len(manifest)} images)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
