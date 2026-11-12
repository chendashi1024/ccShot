using System;
using System.Collections.Generic;

namespace ccShot.Core.Geometry;

/// <summary>Sub-pixel point in image pixel space (origin at top-left of the image).</summary>
public readonly record struct PointF(float X, float Y)
{
    public static PointF operator +(PointF a, PointF b) => new(a.X + b.X, a.Y + b.Y);
    public static PointF operator -(PointF a, PointF b) => new(a.X - b.X, a.Y - b.Y);
    public override string ToString() => $"({X:0.##},{Y:0.##})";
}

/// <summary>Sub-pixel axis-aligned rectangle. X/Y may be negative on virtual desktops.</summary>
public readonly record struct RectF(float X, float Y, float Width, float Height)
{
    public float Right => X + Width;
    public float Bottom => Y + Height;
    public float CenterX => X + Width / 2f;
    public float CenterY => Y + Height / 2f;
    public bool IsEmpty => Width <= 0f || Height <= 0f;
    public PointF Center => new(CenterX, CenterY);
    public PointF TopLeft => new(X, Y);

    public static RectF FromEdges(float left, float top, float right, float bottom) =>
        new(left, top, right - left, bottom - top);

    public static RectF FromPoints(PointF a, PointF b) =>
        FromEdges(MathF.Min(a.X, b.X), MathF.Min(a.Y, b.Y), MathF.Max(a.X, b.X), MathF.Max(a.Y, b.Y));

    public static RectF FromPoints(IEnumerable<PointF> points)
    {
        float minX = float.MaxValue, minY = float.MaxValue, maxX = float.MinValue, maxY = float.MinValue;
        bool any = false;
        foreach (var p in points)
        {
            any = true;
            if (p.X < minX) minX = p.X;
            if (p.Y < minY) minY = p.Y;
            if (p.X > maxX) maxX = p.X;
            if (p.Y > maxY) maxY = p.Y;
        }

        return any ? FromEdges(minX, minY, maxX, maxY) : default;
    }

    public RectF Inflate(float dx, float dy) => new(X - dx, Y - dy, Width + 2 * dx, Height + 2 * dy);
    public RectF Inflate(float d) => Inflate(d, d);

    public RectF Offset(float dx, float dy) => new(X + dx, Y + dy, Width, Height);

    public bool Contains(PointF p) => p.X >= X && p.X <= Right && p.Y >= Y && p.Y <= Bottom;

    public bool IntersectsWith(RectF other) =>
        other.X < Right && X < other.Right && other.Y < Bottom && Y < other.Bottom;

    public RectF Intersect(RectF other)
    {
        float left = MathF.Max(X, other.X);
        float top = MathF.Max(Y, other.Y);
        float right = MathF.Min(Right, other.Right);
        float bottom = MathF.Min(Bottom, other.Bottom);
        return right <= left || bottom <= top ? new RectF(left, top, 0, 0) : FromEdges(left, top, right, bottom);
    }

    public RectF Union(RectF other)
    {
        if (IsEmpty) return other;
        if (other.IsEmpty) return this;
        return FromEdges(MathF.Min(X, other.X), MathF.Min(Y, other.Y), MathF.Max(Right, other.Right), MathF.Max(Bottom, other.Bottom));
    }

    /// <summary>Intersection-over-union, used for box matching in reports and tests.</summary>
    public static float IoU(RectF a, RectF b)
    {
        var inter = a.Intersect(b);
        if (inter.IsEmpty) return 0f;
        float interArea = inter.Width * inter.Height;
        float union = a.Width * a.Height + b.Width * b.Height - interArea;
        return union <= 0f ? 0f : interArea / union;
    }

    public override string ToString() => $"[{X:0.##},{Y:0.##} {Width:0.##}x{Height:0.##}]";
}

/// <summary>Integer pixel rectangle. Capture results, crops and clipboard output use whole pixels only.</summary>
public readonly record struct RectI(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
    public bool IsEmpty => Width <= 0 || Height <= 0;
    public RectF ToRectF() => new(X, Y, Width, Height);

    public static RectI FromEdges(int left, int top, int right, int bottom) =>
        new(left, top, Math.Max(0, right - left), Math.Max(0, bottom - top));

    /// <summary>Rounds outward so that a selection always covers the pixels the user saw.</summary>
    public static RectI FromRectFRoundOut(RectF r) => FromEdges(
        (int)MathF.Floor(r.X),
        (int)MathF.Floor(r.Y),
        (int)MathF.Ceiling(r.Right),
        (int)MathF.Ceiling(r.Bottom));

    /// <summary>Rounds to the nearest pixel edges; used when mapping between DPI-scaled spaces.</summary>
    public static RectI FromRectFRound(RectF r) => FromEdges(
        (int)MathF.Round(r.X),
        (int)MathF.Round(r.Y),
        (int)MathF.Round(r.Right),
        (int)MathF.Round(r.Bottom));

    public RectI Intersect(RectI other) => FromEdges(
        Math.Max(X, other.X), Math.Max(Y, other.Y), Math.Min(Right, other.Right), Math.Min(Bottom, other.Bottom));

    public bool Contains(int x, int y) => x >= X && x < Right && y >= Y && y < Bottom;

    public RectI Offset(int dx, int dy) => new(X + dx, Y + dy, Width, Height);

    public override string ToString() => $"[{X},{Y} {Width}x{Height}]";
}
