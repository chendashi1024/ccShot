using System;
using System.Collections.Generic;
using ccShot.Core.Geometry;

namespace ccShot.Core.Ocr.Paddle;

/// <summary>
/// DB (differentiable binarisation) post-processing without OpenCV: threshold the probability map,
/// label connected components, unclip each component and merge the fragments that belong to one text line.
/// </summary>
internal static class DetPostProcessor
{
    public sealed record DetBox(RectF Box, float Score);

    public static List<DetBox> Process(
        float[] probability,
        int width,
        int height,
        float bitmapThreshold,
        float boxThreshold,
        float unclipRatio,
        int minSize,
        float scaleX,
        float scaleY,
        int sourceWidth,
        int sourceHeight)
    {
        var components = FindComponents(probability, width, height, bitmapThreshold);
        var boxes = new List<DetBox>(components.Count);
        foreach (var component in components)
        {
            float area = component.Count;
            if (area < minSize * minSize) continue;

            float score = 0f;
            int minX = int.MaxValue, minY = int.MaxValue, maxX = int.MinValue, maxY = int.MinValue;
            foreach (var index in component)
            {
                score += probability[index];
                int x = index % width;
                int y = index / width;
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }

            score /= component.Count;
            if (score < boxThreshold) continue;

            float boxW = maxX - minX + 1;
            float boxH = maxY - minY + 1;
            float perimeter = 2f * (boxW + boxH);
            float distance = perimeter <= 0f ? 0f : area * unclipRatio / perimeter;
            var expanded = RectF.FromEdges(minX - distance, minY - distance, maxX + 1 + distance, maxY + 1 + distance);
            var inSource = RectF.FromEdges(
                expanded.X / scaleX, expanded.Y / scaleY, expanded.Right / scaleX, expanded.Bottom / scaleY);
            inSource = inSource.Intersect(new RectF(0, 0, sourceWidth, sourceHeight));
            if (inSource.IsEmpty || inSource.Width < minSize || inSource.Height < minSize) continue;
            boxes.Add(new DetBox(inSource, score));
        }

        return MergeIntoLines(boxes);
    }

    private static List<List<int>> FindComponents(float[] probability, int width, int height, float threshold)
    {
        var visited = new bool[width * height];
        var components = new List<List<int>>();
        var stack = new Stack<int>();
        for (int start = 0; start < visited.Length; start++)
        {
            if (visited[start] || probability[start] <= threshold) continue;
            var component = new List<int>();
            stack.Push(start);
            visited[start] = true;
            while (stack.Count > 0)
            {
                int index = stack.Pop();
                component.Add(index);
                int x = index % width;
                int y = index / width;
                for (int dy = -1; dy <= 1; dy++)
                {
                    int ny = y + dy;
                    if (ny < 0 || ny >= height) continue;
                    for (int dx = -1; dx <= 1; dx++)
                    {
                        if (dx == 0 && dy == 0) continue;
                        int nx = x + dx;
                        if (nx < 0 || nx >= width) continue;
                        int neighbor = ny * width + nx;
                        if (visited[neighbor] || probability[neighbor] <= threshold) continue;
                        visited[neighbor] = true;
                        stack.Push(neighbor);
                    }
                }
            }

            components.Add(component);
        }

        return components;
    }

    /// <summary>
    /// Characters of one line usually arrive as separate fragments once the DB map is thresholded.
    /// Fragments are merged when their vertical centres roughly agree and the horizontal gap is small
    /// relative to the text height, which keeps separate lines and separate columns apart.
    /// </summary>
    private static List<DetBox> MergeIntoLines(List<DetBox> boxes)
    {
        var current = new List<DetBox>(boxes);
        bool changed = true;
        while (changed)
        {
            changed = false;
            current.Sort((a, b) => a.Box.Y.CompareTo(b.Box.Y));
            for (int i = 0; i < current.Count && !changed; i++)
            {
                for (int j = i + 1; j < current.Count; j++)
                {
                    if (!SameLine(current[i], current[j])) continue;
                    var merged = Merge(current[i], current[j]);
                    current[i] = merged;
                    current.RemoveAt(j);
                    changed = true;
                    break;
                }
            }
        }

        current.Sort(CompareReadingOrder);
        return current;
    }

    private static bool SameLine(DetBox a, DetBox b)
    {
        var boxA = a.Box;
        var boxB = b.Box;
        float overlapTop = MathF.Max(boxA.Y, boxB.Y);
        float overlapBottom = MathF.Min(boxA.Bottom, boxB.Bottom);
        float overlap = MathF.Max(0f, overlapBottom - overlapTop);
        float minHeight = MathF.Min(boxA.Height, boxB.Height);
        if (overlap < minHeight * 0.45f) return false;

        float centerDelta = MathF.Abs(boxA.CenterY - boxB.CenterY);
        if (centerDelta > minHeight * 0.5f) return false;

        float gap = boxA.X < boxB.X ? boxB.X - boxA.Right : boxA.X - boxB.Right;
        float maxGap = MathF.Max(minHeight * 1.1f, 8f);
        return gap <= maxGap;
    }

    private static DetBox Merge(DetBox a, DetBox b)
    {
        float areaA = a.Box.Width * a.Box.Height;
        float areaB = b.Box.Width * b.Box.Height;
        float total = areaA + areaB;
        float score = total <= 0 ? a.Score : (a.Score * areaA + b.Score * areaB) / total;
        return new DetBox(a.Box.Union(b.Box), score);
    }

    private static int CompareReadingOrder(DetBox a, DetBox b)
    {
        float heightA = MathF.Min(a.Box.Height, b.Box.Height);
        float tolerance = MathF.Max(4f, heightA * 0.5f);
        if (MathF.Abs(a.Box.Y - b.Box.Y) > tolerance) return a.Box.Y.CompareTo(b.Box.Y);
        return a.Box.X.CompareTo(b.Box.X);
    }
}
