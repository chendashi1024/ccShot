using System;
using System.Collections.Generic;
using System.Linq;
using CcShot.Core.Geometry;
using CcShot.Core.Ocr;

namespace CcShot.Core.Tests;

/// <summary>Builds deterministic OCR pages so selection behaviour can be asserted without a model.</summary>
internal static class FakeOcr
{
    /// <summary>
    /// Lays out one line where each character occupies <paramref name="advance"/> pixels, mirroring
    /// the per-glyph boxes the recognizer produces from CTC time steps.
    /// </summary>
    public static OcrPage Line(string text, float originX, float originY, float advance, float height, int lineIndex = 0)
    {
        var glyphs = new List<OcrGlyph>();
        float x = originX;
        foreach (var ch in text)
        {
            var token = ch.ToString();
            float width = ch == ' ' ? advance * 0.6f : advance;
            glyphs.Add(new OcrGlyph(token, new RectF(x, originY, width, height)));
            x += width;
        }

        var line = new OcrLine(text, RectF.FromEdges(originX, originY, x, originY + height), glyphs, 0.95f);
        return new OcrPage(new[] { line }, 1000, 600, null, OcrPage.Empty.Timing);
    }

    public static OcrPage Lines(params (string Text, float X, float Y)[] lines)
    {
        var result = new List<OcrLine>();
        foreach (var (text, x, y) in lines)
        {
            var glyphs = new List<OcrGlyph>();
            float cx = x;
            foreach (var ch in text)
            {
                glyphs.Add(new OcrGlyph(ch.ToString(), new RectF(cx, y, 20f, 30f)));
                cx += 20f;
            }

            result.Add(new OcrLine(text, RectF.FromEdges(x, y, cx, y + 30f), glyphs, 0.95f));
        }

        return new OcrPage(result, 1000, 600, null, OcrPage.Empty.Timing);
    }

    public static OcrPage VaryingWidths((string Char, float X, float Width)[] chars, float y)
    {
        var glyphs = chars.Select(c => new OcrGlyph(c.Char, new RectF(c.X, y, c.Width, 32f))).ToList();
        var text = string.Concat(chars.Select(c => c.Char));
        var box = glyphs.Aggregate(glyphs[0].Box, (acc, g) => acc.Union(g.Box));
        return new OcrPage(new[] { new OcrLine(text, box, glyphs, 0.9f) }, 1000, 600, null, OcrPage.Empty.Timing);
    }
}
