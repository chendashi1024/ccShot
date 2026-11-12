using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using ccShot.Core.Geometry;

namespace ccShot.Core.Ocr.Selection;

/// <summary>A half-open run of glyphs inside one line.</summary>
public readonly record struct LineRange(int LineIndex, int Start, int EndExclusive)
{
    public int Count => Math.Max(0, EndExclusive - Start);
    public bool IsEmpty => Count == 0;
}

/// <summary>An insertion point: between glyph <c>GlyphIndex-1</c> and <c>GlyphIndex</c> of a line.</summary>
public readonly record struct Caret(int LineIndex, int GlyphIndex, float X, float Y);

/// <summary>Selection expressed as per-line glyph ranges plus the order the user dragged in.</summary>
public sealed class TextSelection
{
    public static readonly TextSelection Empty = new(Array.Empty<LineRange>(), forward: true);

    public TextSelection(IReadOnlyList<LineRange> ranges, bool forward)
    {
        Ranges = ranges;
        Forward = forward;
    }

    public IReadOnlyList<LineRange> Ranges { get; }

    /// <summary>Drag direction: true when the caret ended after where it started.</summary>
    public bool Forward { get; }

    public bool IsEmpty => Ranges.Count == 0;
    public int GlyphCount
    {
        get
        {
            int n = 0;
            foreach (var r in Ranges) n += r.Count;
            return n;
        }
    }
}

/// <summary>
/// Maps pointer geometry onto glyph ranges. All coordinates are image pixels, so the caller converts
/// screen/DIP before asking. Nothing here assumes even character widths: the range is built from the
/// recognizer's per-character boxes, so single characters and punctuation are selectable on their own.
/// </summary>
public sealed class TextSelectionModel
{
    private readonly OcrPage _page;

    public TextSelectionModel(OcrPage page)
    {
        _page = page ?? throw new ArgumentNullException(nameof(page));
    }

    public OcrPage Page => _page;

    /// <summary>How a pointer position is turned into an insertion index inside a line.</summary>
    public enum CaretBias
    {
        /// <summary>Closest boundary; used for clicks.</summary>
        Nearest,

        /// <summary>Boundary at or before the pointer; used for the fixed end of a drag.</summary>
        Floor,

        /// <summary>Boundary at or after the pointer; used for the moving end of a drag.</summary>
        Ceiling,
    }

    public Caret CaretAt(PointF point) => CaretAt(point, CaretBias.Nearest);

    public Caret CaretAt(PointF point, CaretBias bias)
    {
        if (_page.Lines.Count == 0) return new Caret(0, 0, point.X, point.Y);

        int lineIndex = NearestLine(point);
        var line = _page.Lines[lineIndex];
        if (line.Glyphs.Count == 0) return new Caret(lineIndex, 0, line.Box.X, line.Box.CenterY);

        int insertion;
        if (bias == CaretBias.Nearest)
        {
            insertion = 0;
            float bestDistance = float.MaxValue;
            for (int i = 0; i <= line.Glyphs.Count; i++)
            {
                float boundaryX = BoundaryX(line, i);
                float distance = MathF.Abs(point.X - boundaryX);
                if (distance < bestDistance)
                {
                    bestDistance = distance;
                    insertion = i;
                }
            }
        }
        else
        {
            int floor = 0;
            for (int i = 0; i <= line.Glyphs.Count; i++)
            {
                if (BoundaryX(line, i) <= point.X) floor = i;
                else break;
            }

            insertion = bias == CaretBias.Floor ? floor : Math.Min(line.Glyphs.Count, floor + (BoundaryX(line, floor) < point.X ? 1 : 0));
        }

        return new Caret(lineIndex, insertion, BoundaryX(line, insertion), line.Box.CenterY);
    }

    private int NearestLine(PointF point)
    {
        int best = 0;
        float bestDistance = float.MaxValue;
        for (int i = 0; i < _page.Lines.Count; i++)
        {
            var box = _page.Lines[i].Box;
            float dy = point.Y < box.Y ? box.Y - point.Y : point.Y > box.Bottom ? point.Y - box.Bottom : 0f;
            float dx = point.X < box.X ? box.X - point.X : point.X > box.Right ? point.X - box.Right : 0f;
            // Vertical distance dominates so a drag far to the right still resolves to the closest line.
            float distance = dy * 1000f + dx;
            if (distance < bestDistance)
            {
                bestDistance = distance;
                best = i;
            }
        }

        return best;
    }

    private static float BoundaryX(OcrLine line, int insertion)
    {
        if (line.Glyphs.Count == 0) return line.Box.X;
        if (insertion <= 0) return line.Glyphs[0].Box.X;
        if (insertion >= line.Glyphs.Count) return line.Glyphs[^1].Box.Right;
        return (line.Glyphs[insertion - 1].Box.Right + line.Glyphs[insertion].Box.X) / 2f;
    }

    /// <summary>
    /// Drag selection. The direction is decided first, then the anchor snaps to the boundary before the
    /// pointer and the moving end to the boundary after it, so every character the pointer crosses is
    /// included - the behaviour native text selection has, and the reason a drag starting and ending
    /// inside one character still copies that character.
    /// </summary>
    public TextSelection Select(PointF anchor, PointF focus)
    {
        var rawAnchor = CaretAt(anchor);
        var rawFocus = CaretAt(focus);
        // A click is not a drag: below the motion threshold nothing is selected.
        if (rawAnchor == rawFocus && MathF.Abs(focus.X - anchor.X) < 2f && MathF.Abs(focus.Y - anchor.Y) < 2f)
            return TextSelection.Empty;
        bool forward = Compare(rawAnchor, rawFocus) <= 0;
        var start = CaretAt(anchor, forward ? CaretBias.Floor : CaretBias.Ceiling);
        var end = CaretAt(focus, forward ? CaretBias.Ceiling : CaretBias.Floor);
        return Select(start, end);
    }

    public TextSelection Select(Caret anchor, Caret focus)
    {
        bool forward = Compare(anchor, focus) <= 0;
        var start = forward ? anchor : focus;
        var end = forward ? focus : anchor;
        if (start.LineIndex == end.LineIndex && start.GlyphIndex == end.GlyphIndex)
            return TextSelection.Empty;

        var ranges = new List<LineRange>();
        if (start.LineIndex == end.LineIndex)
        {
            ranges.Add(new LineRange(start.LineIndex, Math.Min(start.GlyphIndex, end.GlyphIndex), Math.Max(start.GlyphIndex, end.GlyphIndex)));
        }
        else
        {
            int startCount = _page.Lines[start.LineIndex].Glyphs.Count;
            if (start.GlyphIndex < startCount) ranges.Add(new LineRange(start.LineIndex, start.GlyphIndex, startCount));
            for (int line = start.LineIndex + 1; line < end.LineIndex; line++)
            {
                int count = _page.Lines[line].Glyphs.Count;
                if (count > 0) ranges.Add(new LineRange(line, 0, count));
            }

            if (end.GlyphIndex > 0) ranges.Add(new LineRange(end.LineIndex, 0, Math.Min(end.GlyphIndex, _page.Lines[end.LineIndex].Glyphs.Count)));
        }

        return new TextSelection(ranges, forward);
    }

    private static int Compare(Caret a, Caret b) =>
        a.LineIndex != b.LineIndex ? a.LineIndex.CompareTo(b.LineIndex) : a.GlyphIndex.CompareTo(b.GlyphIndex);

    public TextSelection SelectAll()
    {
        var ranges = new List<LineRange>();
        for (int i = 0; i < _page.Lines.Count; i++)
        {
            int count = _page.Lines[i].Glyphs.Count;
            if (count > 0) ranges.Add(new LineRange(i, 0, count));
        }

        return new TextSelection(ranges, forward: true);
    }

    /// <summary>Double-click behaviour: a CJK character selects itself, Latin becomes a word.</summary>
    public TextSelection SelectWordAt(PointF point)
    {
        var caret = CaretAt(point);
        var line = _page.Lines[caret.LineIndex];
        if (line.Glyphs.Count == 0) return TextSelection.Empty;

        int index = Math.Clamp(caret.GlyphIndex, 0, line.Glyphs.Count - 1);
        // Prefer the character the pointer is actually over when the caret sits on a boundary.
        for (int i = 0; i < line.Glyphs.Count; i++)
        {
            if (line.Glyphs[i].Box.Contains(point)) { index = i; break; }
        }

        bool wordChar = IsWordGlyph(line.Glyphs[index].Text);
        int start = index, end = index + 1;
        if (wordChar)
        {
            while (start > 0 && IsWordGlyph(line.Glyphs[start - 1].Text)) start--;
            while (end < line.Glyphs.Count && IsWordGlyph(line.Glyphs[end].Text)) end++;
        }

        return new TextSelection(new[] { new LineRange(caret.LineIndex, start, end) }, forward: true);
    }

    private static bool IsWordGlyph(string text)
    {
        if (string.IsNullOrEmpty(text)) return false;
        char ch = text[0];
        // CJK has no word spacing: a double click selects one character, never the whole line.
        if (IsCjk(ch)) return false;
        return char.IsLetterOrDigit(ch) || ch == '_' || ch == '-' || ch == '\'';
    }

    /// <summary>Selected text. Lines are joined with a newline, matching what a user expects to paste.</summary>
    public string Text(TextSelection selection)
    {
        if (selection.IsEmpty) return string.Empty;
        var sb = new StringBuilder();
        bool first = true;
        foreach (var range in selection.Ranges)
        {
            if (range.IsEmpty) continue;
            if (!first) sb.Append('\n');
            first = false;
            var glyphs = _page.Lines[range.LineIndex].Glyphs;
            for (int i = range.Start; i < range.EndExclusive && i < glyphs.Count; i++) sb.Append(glyphs[i].Text);
        }

        return sb.ToString();
    }

    /// <summary>
    /// Merged highlight rectangles, one per contiguous run inside a line. The clipboard text and these
    /// rectangles are produced from the same ranges, so a mismatch is a bug rather than a rounding artefact.
    /// </summary>
    public IReadOnlyList<(RectF Box, int LineIndex)> HighlightRects(TextSelection selection)
    {
        var result = new List<(RectF, int)>();
        foreach (var range in selection.Ranges)
        {
            if (range.IsEmpty) continue;
            var glyphs = _page.Lines[range.LineIndex].Glyphs;
            int i = range.Start;
            while (i < range.EndExclusive && i < glyphs.Count)
            {
                var box = glyphs[i].Box;
                int j = i + 1;
                while (j < range.EndExclusive && j < glyphs.Count && glyphs[j].Text != " ")
                {
                    box = box.Union(glyphs[j].Box);
                    j++;
                }

                // Spaces are not highlighted on their own but keep the run continuous.
                if (glyphs[i].Text != " ") result.Add((box, range.LineIndex));
                i = j;
            }
        }

        return result;
    }

    public RectF SelectionBounds(TextSelection selection)
    {
        var rects = HighlightRects(selection);
        if (rects.Count == 0) return default;
        var box = rects[0].Box;
        for (int i = 1; i < rects.Count; i++) box = box.Union(rects[i].Box);
        return box;
    }

    public static bool IsCjk(char ch)
    {
        if (ch >= 0x4E00 && ch <= 0x9FFF) return true;
        if (ch >= 0x3400 && ch <= 0x4DBF) return true;
        if (ch >= 0x3000 && ch <= 0x303F) return true; // CJK punctuation
        if (ch >= 0xFF00 && ch <= 0xFFEF) return true; // full-width forms
        var cat = CharUnicodeInfo.GetUnicodeCategory(ch);
        return cat == UnicodeCategory.OtherLetter;
    }
}
