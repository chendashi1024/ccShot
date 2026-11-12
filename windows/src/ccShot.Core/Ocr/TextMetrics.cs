using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace ccShot.Core.Ocr;

/// <summary>
/// Text normalization and error metrics. The definitions mirror the macOS prototype report so the two
/// platforms can be compared on the same fixtures: NFC, whitespace stripped for the main CER, a stricter
/// variant that keeps whitespace, punctuation and case preserved in both.
/// </summary>
public static class TextMetrics
{
    public static string Normalize(string? text, bool keepWhitespace = false)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        var nfc = text.Normalize(NormalizationForm.FormC).Replace("\r\n", "\n").Replace('\r', '\n');
        if (keepWhitespace) return nfc;
        var sb = new StringBuilder(nfc.Length);
        foreach (var ch in nfc)
        {
            if (!char.IsWhiteSpace(ch)) sb.Append(ch);
        }

        return sb.ToString();
    }

    /// <summary>Levenshtein distance over code points.</summary>
    public static int EditDistance(IReadOnlyList<string> reference, IReadOnlyList<string> hypothesis)
    {
        int n = reference.Count, m = hypothesis.Count;
        if (n == 0) return m;
        if (m == 0) return n;
        var prev = new int[m + 1];
        var cur = new int[m + 1];
        for (int j = 0; j <= m; j++) prev[j] = j;
        for (int i = 1; i <= n; i++)
        {
            cur[0] = i;
            for (int j = 1; j <= m; j++)
            {
                int cost = reference[i - 1] == hypothesis[j - 1] ? 0 : 1;
                cur[j] = Math.Min(Math.Min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
            }

            (prev, cur) = (cur, prev);
        }

        return prev[m];
    }

    private static List<string> ToCodePoints(string s)
    {
        var list = new List<string>(s.Length);
        for (int i = 0; i < s.Length; i++)
        {
            if (char.IsHighSurrogate(s[i]) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1]))
            {
                list.Add(s.Substring(i, 2));
                i++;
            }
            else
            {
                list.Add(s[i].ToString());
            }
        }

        return list;
    }

    public static int EditDistance(string reference, string hypothesis) =>
        EditDistance(ToCodePoints(reference), ToCodePoints(hypothesis));

    /// <summary>Character error rate. Empty reference and empty hypothesis count as 0; empty reference with output counts as 1.</summary>
    public static double Cer(string reference, string hypothesis, bool keepWhitespace = false)
    {
        var r = ToCodePoints(Normalize(reference, keepWhitespace));
        var h = ToCodePoints(Normalize(hypothesis, keepWhitespace));
        if (r.Count == 0) return h.Count == 0 ? 0d : 1d;
        return EditDistance(r, h) / (double)r.Count;
    }

    public static bool ExactMatch(string reference, string hypothesis, bool keepWhitespace = false) =>
        string.Equals(Normalize(reference, keepWhitespace), Normalize(hypothesis, keepWhitespace), StringComparison.Ordinal);

    /// <summary>True when the string contains at least one letter or digit (used to skip "empty output" faking success).</summary>
    public static bool ContainsWordChar(string? s)
    {
        if (string.IsNullOrEmpty(s)) return false;
        foreach (var ch in s)
        {
            var cat = CharUnicodeInfo.GetUnicodeCategory(ch);
            if (cat is UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter
                or UnicodeCategory.OtherLetter or UnicodeCategory.DecimalDigitNumber) return true;
        }

        return false;
    }
}
