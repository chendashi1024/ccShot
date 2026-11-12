using System;
using System.Collections.Generic;
using System.Linq;
using ccShot.Core.Geometry;

namespace ccShot.Core.Ocr;

/// <summary>
/// Column-wise ink analysis of a text line. Used to recover the word spaces the recognizer drops:
/// the model often predicts no space at all, but the pixels still show a blank column band between words.
/// The background colour is estimated from the crop border so it works on light and dark themes.
/// </summary>
public static class InkProfile
{
    public const int DefaultContrast = 48;

    public static bool[] ColumnsWithInk(Imaging.PixelImage image, RectI crop, int contrast = DefaultContrast)
    {
        var result = new bool[Math.Max(0, crop.Width)];
        if (crop.IsEmpty) return result;

        var background = EstimateBackground(image, crop);
        for (int x = 0; x < crop.Width; x++)
        {
            bool ink = false;
            for (int y = 0; y < crop.Height; y++)
            {
                var pixel = image.GetPixel(crop.X + x, crop.Y + y);
                int delta = Math.Abs(pixel.R - background.R) + Math.Abs(pixel.G - background.G) + Math.Abs(pixel.B - background.B);
                if (delta > contrast)
                {
                    ink = true;
                    break;
                }
            }

            result[x] = ink;
        }

        return result;
    }

    /// <summary>
    /// Background is the most frequent colour in the crop, not the border colour: a tight detection box
    /// may touch the glyphs, which would make a border average look like text ink.
    /// </summary>
    private static (int R, int G, int B) EstimateBackground(Imaging.PixelImage image, RectI crop)
    {
        var buckets = new Dictionary<int, (long R, long G, long B, int Count)>();
        int stepX = Math.Max(1, crop.Width / 96);
        int stepY = Math.Max(1, crop.Height / 24);
        for (int y = 0; y < crop.Height; y += stepY)
        {
            for (int x = 0; x < crop.Width; x += stepX)
            {
                var p = image.GetPixel(crop.X + x, crop.Y + y);
                int key = (p.R >> 4) << 8 | (p.G >> 4) << 4 | (p.B >> 4);
                buckets.TryGetValue(key, out var bucket);
                buckets[key] = (bucket.R + p.R, bucket.G + p.G, bucket.B + p.B, bucket.Count + 1);
            }
        }

        if (buckets.Count == 0) return (255, 255, 255);
        var best = buckets.Values.OrderByDescending(b => b.Count).First();
        return ((int)(best.R / best.Count), (int)(best.G / best.Count), (int)(best.B / best.Count));
    }

    /// <summary>Longest run of blank columns inside [from, to) in crop-local coordinates.</summary>
    public static (int Start, int Length) LongestBlankRun(bool[] ink, int from, int to)
    {
        int bestStart = 0, bestLength = 0, currentStart = -1;
        from = Math.Max(0, from);
        to = Math.Min(ink.Length, to);
        for (int x = from; x < to; x++)
        {
            if (!ink[x])
            {
                if (currentStart < 0) currentStart = x;
                int length = x - currentStart + 1;
                if (length > bestLength)
                {
                    bestLength = length;
                    bestStart = currentStart;
                }
            }
            else
            {
                currentStart = -1;
            }
        }

        return (bestStart, bestLength);
    }

    /// <summary>
    /// Inserts a space glyph between two Latin characters when the pixels show a blank band at least
    /// 30% of the text height wide. Chinese never receives inserted spaces.
    /// </summary>
    public static IReadOnlyList<OcrGlyph> InsertWordSpaces(
        IReadOnlyList<OcrGlyph> glyphs,
        bool[] ink,
        RectI crop,
        float minBlankRatio = 0.25f)
    {
        if (glyphs.Count < 2 || ink.Length == 0 || crop.Height <= 0) return glyphs;
        float minBlank = Math.Max(3f, crop.Height * minBlankRatio);
        var result = new List<OcrGlyph>(glyphs.Count + 8);
        result.Add(glyphs[0]);

        for (int i = 1; i < glyphs.Count; i++)
        {
            var previous = glyphs[i - 1];
            var current = glyphs[i];
            bool latinPair = IsLatin(previous.Text) && IsLatin(current.Text);
            bool alreadySpaced = previous.Text == " " || current.Text == " ";
            if (latinPair && !alreadySpaced)
            {
                int from = (int)MathF.Round(previous.Box.X - crop.X + previous.Box.Width * 0.4f);
                int to = (int)MathF.Round(current.Box.X - crop.X + current.Box.Width * 0.6f);
                var (start, length) = LongestBlankRun(ink, from, to);
                if (length >= minBlank)
                {
                    float x = crop.X + start + length / 2f;
                    result.Add(new OcrGlyph(" ", RectF.FromEdges(x - 1f, previous.Box.Y, x + 1f, previous.Box.Bottom)));
                }
            }

            result.Add(current);
        }

        return result;
    }

    private static bool IsLatin(string text)
    {
        if (string.IsNullOrEmpty(text) || text.Length != 1) return false;
        char ch = text[0];
        if (ch > 0x2000) return false;
        return char.IsLetterOrDigit(ch) || ch is '.' or ',' or ';' or ':' or '!' or '?' or ')' or ']' or '}' or '%';
    }
}
