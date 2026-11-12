using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using ccShot.Core.Geometry;
using ccShot.Core.Ocr;
using ccShot.Core.Ocr.Selection;

namespace ccShot.Tools;

/// <summary>
/// Turns a recognized page plus per-character ground truth into selection evidence.
/// 字框几何与实际选中文字分别统计，选字结果以固定标准答案为准。
/// </summary>
internal static class SelectionChecks
{
    private const int MaxGlyphsPerFixture = 80;

    public static SelectionResult Evaluate(OcrPage page, Fixture fixture)
    {
        var result = new SelectionResult();
        if (fixture.Glyphs == null || fixture.Glyphs.Count == 0) return result;

        var model = new TextSelectionModel(page);
        var truthGlyphs = fixture.Glyphs;

        // 1. Glyph box quality: match truth characters to the nearest predicted glyph whose centre is inside.
        var predicted = page.Lines.SelectMany(l => l.Glyphs).ToList();
        double boundaryError = 0;
        double normalizedError = 0;
        int matched = 0;
        foreach (var truth in truthGlyphs)
        {
            var truthRect = new RectF((float)truth.X, (float)truth.Y, (float)truth.W, (float)truth.H);
            var centre = truthRect.Center;
            OcrGlyph? best = null;
            float bestDistance = float.MaxValue;
            foreach (var glyph in predicted)
            {
                if (!truthRect.Inflate(2f).Contains(glyph.Box.Center)) continue;
                float d = MathF.Abs(glyph.Box.CenterX - centre.X);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = glyph;
                }
            }

            if (best == null) continue;
            matched++;
            boundaryError += MathF.Abs(best.Box.X - truthRect.X) + MathF.Abs(best.Box.Right - truthRect.Right);
            normalizedError += (MathF.Abs(best.Box.X - truthRect.X) + MathF.Abs(best.Box.Right - truthRect.Right)) / MathF.Max(1f, truthRect.Width);
        }

        result.TruthGlyphs = truthGlyphs.Count;
        result.MatchedGlyphs = matched;
        if (matched > 0)
        {
            result.BoundaryMeanAbsErrorPx = boundaryError / (matched * 2);
            result.BoundaryMeanNormalizedError = normalizedError / (matched * 2);
        }

        // 2. Single character drag: a drag inside one character may select exactly one character.
        var sample = Sample(truthGlyphs, MaxGlyphsPerFixture);
        foreach (var truth in sample)
        {
            if (char.IsWhiteSpace(truth.Char.FirstOrDefault())) continue;
            float x0 = (float)(truth.X + truth.W * 0.3);
            float x1 = (float)(truth.X + truth.W * 0.7);
            float y = (float)(truth.Y + truth.H / 2);
            var selection = model.Select(new PointF(x0, y), new PointF(x1, y));
            var text = model.Text(selection);
            result.SingleCharTotal++;
            if (text == truth.Char)
            {
                result.SingleCharCorrect++;
            }
            else if (result.Mismatches.Count < 5)
            {
                result.Mismatches.Add($"single '{truth.Char}' at ({x0:0},{y:0}) -> '{text}'");
            }
        }

        // 用样本坐标起止拖选整行，识别漏行同样计入。
        if (fixture.TruthLines is { Count: > 0 } lines)
        {
            int offset = 0;
            foreach (string expected in lines)
            {
                var tokens = expected.EnumerateRunes().Where(rune => !Rune.IsWhiteSpace(rune)).Select(rune => rune.ToString()).ToArray();
                if (tokens.Length == 0) continue;
                var glyphs = truthGlyphs.Skip(offset).Take(tokens.Length).ToArray();
                offset += tokens.Length;
                if (!glyphs.Select(glyph => glyph.Char).SequenceEqual(tokens))
                    throw new InvalidDataException($"{fixture.Id} 的逐字框与行真值不一致");
                var first = glyphs[0];
                var last = glyphs[^1];
                var centers = glyphs.Select(glyph => glyph.Y + glyph.H / 2).OrderBy(y => y).ToArray();
                float y = (float)centers[centers.Length / 2];
                var start = new PointF((float)(first.X + first.W * 0.2), y);
                var end = new PointF((float)(last.X + last.W * 0.8), y);
                string text = model.Text(model.Select(start, end));
                result.RangeTotal++;
                if (text == expected && model.Text(model.Select(end, start)) == expected) result.RangeCorrect++;
                else if (result.Mismatches.Count < 5) result.Mismatches.Add($"line '{expected}' -> '{text}'");
            }
            if (offset != truthGlyphs.Count) throw new InvalidDataException($"{fixture.Id} 有未计入的逐字框");
        }

        return result;
    }

    private static List<TruthGlyph> Sample(List<TruthGlyph> glyphs, int max)
    {
        if (glyphs.Count <= max) return glyphs;
        var result = new List<TruthGlyph>(max);
        double step = glyphs.Count / (double)max;
        for (int i = 0; i < max; i++) result.Add(glyphs[(int)(i * step)]);
        return result;
    }
}
