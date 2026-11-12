using System;
using System.Collections.Generic;
using System.Linq;

namespace ccShot.Core.Ocr;

/// <summary>
/// Reading order for horizontal text: group lines into rows by vertical overlap, then left-to-right.
/// Keeps multi-column layouts from interleaving as long as the columns are vertically separated.
/// </summary>
public static class ReadingOrder
{
    public static IReadOnlyList<OcrLine> Sort(IReadOnlyList<OcrLine> lines)
    {
        if (lines.Count <= 1) return lines;
        var remaining = new List<OcrLine>(lines);
        remaining.Sort((a, b) => a.Box.Y.CompareTo(b.Box.Y));
        var result = new List<OcrLine>(lines.Count);
        var row = new List<OcrLine>();

        foreach (var line in remaining)
        {
            if (row.Count == 0)
            {
                row.Add(line);
                continue;
            }

            float rowTop = row.Min(l => l.Box.Y);
            float rowBottom = row.Max(l => l.Box.Bottom);
            float overlap = MathF.Min(rowBottom, line.Box.Bottom) - MathF.Max(rowTop, line.Box.Y);
            float minHeight = MathF.Min(row.Max(l => l.Box.Height), line.Box.Height);
            if (overlap >= minHeight * 0.4f)
            {
                row.Add(line);
            }
            else
            {
                result.AddRange(row.OrderBy(l => l.Box.X));
                row.Clear();
                row.Add(line);
            }
        }

        if (row.Count > 0) result.AddRange(row.OrderBy(l => l.Box.X));
        return result;
    }
}
