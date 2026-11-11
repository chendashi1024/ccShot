using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using CcShot.Core.Geometry;

namespace CcShot.Core.Ocr;

/// <summary>
/// One recognized character with the pixel box it occupies. Glyph boxes come from the recognizer's
/// CTC time steps, which is a genuine per-character x range, not an evenly split line box.
/// </summary>
public sealed record OcrGlyph(string Text, RectF Box, int TimeStart = 0, int TimeEnd = 0)
{
    public float Width => Box.Width;
    public float CenterX => Box.CenterX;
}

/// <summary>One detected text line: the detection quad (axis-aligned) plus its characters in order.</summary>
public sealed class OcrLine
{
    public OcrLine(string text, RectF box, IReadOnlyList<OcrGlyph> glyphs, float score)
    {
        Text = text;
        Box = box;
        Glyphs = glyphs;
        Score = score;
    }

    public string Text { get; }
    public RectF Box { get; }
    public IReadOnlyList<OcrGlyph> Glyphs { get; }
    public float Score { get; }

    public override string ToString() => $"{Box} {Text}";
}

public sealed record OcrEngineInfo(
    string DetModel, string RecModel, string Dictionary, string Runtime, string Options, string RuntimeVersion)
{
    public string Describe() => $"det={DetModel}; rec={RecModel}; dict={Dictionary}; runtime={Runtime} {RuntimeVersion}; {Options}";
}

public sealed record OcrTiming(double PreprocessMs, double DetectMs, double RecognizeMs, double TotalMs);

/// <summary>Result of one recognition. Immutable; bound to a capture revision by the session layer.</summary>
public sealed class OcrPage
{
    public static readonly OcrPage Empty = new(Array.Empty<OcrLine>(), 0, 0, null, new OcrTiming(0, 0, 0, 0));

    public OcrPage(IReadOnlyList<OcrLine> lines, int imageWidth, int imageHeight, OcrEngineInfo? engine, OcrTiming timing)
    {
        Lines = lines;
        ImageWidth = imageWidth;
        ImageHeight = imageHeight;
        Engine = engine;
        Timing = timing;
    }

    public IReadOnlyList<OcrLine> Lines { get; }
    public int ImageWidth { get; }
    public int ImageHeight { get; }
    public OcrEngineInfo? Engine { get; }
    public OcrTiming Timing { get; }
    public bool HasText => Lines.Any(l => l.Glyphs.Count > 0);

    public string ToPlainText()
    {
        var sb = new StringBuilder();
        for (int i = 0; i < Lines.Count; i++)
        {
            if (i > 0) sb.Append('\n');
            sb.Append(Lines[i].Text);
        }

        return sb.ToString();
    }
}
