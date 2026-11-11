using System;
using System.Collections.Generic;
using System.Linq;
using CcShot.Core.Geometry;
using CcShot.Core.Ocr;
using CcShot.Core.Ocr.Selection;

namespace CcShot.Tools;

/// <summary>
/// Turns a recognized page plus per-character ground truth into selection evidence.
/// Recognition error and selection error are scored separately on purpose: a wrong character must not
/// be reported as a selection bug, and a wrong selection range must not hide behind a good CER.
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
            if (text.Length == 1)
            {
                result.SingleCharCorrect++;
            }
            else if (result.Mismatches.Count < 5)
            {
                result.Mismatches.Add($"single '{truth.Char}' at ({x0:0},{y:0}) -> '{text}'");
            }
        }

        // 3. Whole line drag: selecting from the first to the last character must reproduce the line.
        foreach (var line in page.Lines)
        {
            if (line.Glyphs.Count == 0) continue;
            var first = line.Glyphs[0].Box;
            var last = line.Glyphs[^1].Box;
            // A single-glyph line needs a real drag (edge to edge); centre to centre is a click.
            var selection = line.Glyphs.Count == 1
                ? model.Select(new PointF(first.X + 0.5f, first.CenterY), new PointF(first.Right - 0.5f, first.CenterY))
                : model.Select(new PointF(first.X + 1f, first.CenterY), new PointF(last.Right - 1f, last.CenterY));
            var text = model.Text(selection);
            result.RangeTotal++;
            if (text == line.Text) result.RangeCorrect++;
            else if (result.Mismatches.Count < 5) result.Mismatches.Add($"line '{line.Text}' -> '{text}'");
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
