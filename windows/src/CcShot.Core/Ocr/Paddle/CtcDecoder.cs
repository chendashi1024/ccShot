using System;
using System.Collections.Generic;

namespace CcShot.Core.Ocr.Paddle;

internal readonly record struct CtcChar(string Text, int TimeStart, int TimeEnd, float Confidence);

/// <summary>
/// Greedy CTC decoding that keeps the time range of every emitted character. The time range is what
/// turns a line-level recognition result into real per-character boxes: character k spans the input
/// columns covered by its time steps, not an evenly divided share of the line.
/// </summary>
internal static class CtcDecoder
{
    public static List<CtcChar> Decode(
        float[] logits,
        int timeSteps,
        int classes,
        IReadOnlyList<string> dictionary,
        float minConfidence = 0f)
    {
        // PP-OCR recognition heads differ: some export raw logits, others already apply softmax.
        // Detect which one this model produces so the confidence number means the same thing for both.
        bool alreadyProbabilities = LooksLikeProbabilities(logits);
        var result = new List<CtcChar>(Math.Max(4, timeSteps / 2));
        var runs = new List<(int Index, int Start, int End)>();
        for (int t = 0; t < timeSteps; t++)
        {
            int index = ArgMax(logits, t * classes, classes);
            if (runs.Count > 0 && runs[^1].Index == index)
            {
                var last = runs[^1];
                runs[^1] = (last.Index, last.Start, t);
            }
            else
            {
                runs.Add((index, t, t));
            }
        }

        int previousIndex = 0;
        foreach (var run in runs)
        {
            if (run.Index != 0 && run.Index != previousIndex)
            {
                var text = Map(run.Index, dictionary);
                if (text != null)
                {
                    float confidence = alreadyProbabilities
                        ? logits[run.Start * classes + run.Index]
                        : SoftmaxAt(logits, run.Start * classes, classes, run.Index);
                    if (confidence >= minConfidence) result.Add(new CtcChar(text, run.Start, run.End, confidence));
                }
            }

            previousIndex = run.Index;
        }

        return result;
    }

    private static bool LooksLikeProbabilities(float[] logits)
    {
        float max = float.NegativeInfinity;
        float min = float.PositiveInfinity;
        int sample = Math.Min(logits.Length, 65536);
        for (int i = 0; i < sample; i++)
        {
            float v = logits[i];
            if (v > max) max = v;
            if (v < min) min = v;
        }

        return min >= -0.0001f && max <= 1.0001f;
    }

    private static string? Map(int index, IReadOnlyList<string> dictionary)
    {
        if (index <= 0) return null;
        if (index <= dictionary.Count) return dictionary[index - 1];
        return index == dictionary.Count + 1 ? " " : null;
    }

    private static int ArgMax(float[] values, int offset, int count)
    {
        int best = 0;
        float bestValue = values[offset];
        for (int i = 1; i < count; i++)
        {
            float v = values[offset + i];
            if (v > bestValue)
            {
                bestValue = v;
                best = i;
            }
        }

        return best;
    }

    private static float SoftmaxAt(float[] values, int offset, int count, int index)
    {
        float max = float.NegativeInfinity;
        for (int i = 0; i < count; i++)
        {
            float v = values[offset + i];
            if (v > max) max = v;
        }

        double sum = 0;
        for (int i = 0; i < count; i++) sum += Math.Exp(values[offset + i] - max);
        return sum <= 0 ? 0f : (float)(Math.Exp(values[offset + index] - max) / sum);
    }
}
