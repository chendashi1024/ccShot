using System;
using System.Collections.Generic;
using CcShot.Core.Geometry;

namespace CcShot.Core.Annotate;

public enum AnnotationKind
{
    Arrow,
    Rect,
    Ellipse,
    Pen,
    Highlight,
    Mask,
    Text,
    Number,
}

public enum MaskEffect
{
    /// <summary>Opaque solid fill. The only effect that is treated as a real redaction.</summary>
    Solid,
    Mosaic,
    Blur,
}

/// <summary>Per-tool style. Kept per tool so picking the arrow tool does not change text settings.</summary>
public sealed record AnnotationStyle(
    uint ColorArgb = 0xFFE0523F,
    float Thickness = 3f,
    float FontSize = 20f,
    bool Bold = false,
    bool Filled = false,
    uint FillArgb = 0x00000000)
{
    public static AnnotationStyle Default(AnnotationKind kind) => kind switch
    {
        AnnotationKind.Highlight => new AnnotationStyle(0x66FFD54F, 18f),
        AnnotationKind.Mask => new AnnotationStyle(0xFF1F2933, 18f),
        AnnotationKind.Text => new AnnotationStyle(0xFFE0523F, 3f, 20f),
        AnnotationKind.Number => new AnnotationStyle(0xFFE0523F, 3f, 16f, Filled: true),
        AnnotationKind.Pen => new AnnotationStyle(0xFFE0523F, 4f),
        _ => new AnnotationStyle(),
    };
}

/// <summary>One annotation. Immutable geometry is exposed through properties; edits go through the document.</summary>
public abstract class AnnotationItem
{
    protected AnnotationItem(AnnotationKind kind, AnnotationStyle style)
    {
        Kind = kind;
        Style = style;
    }

    public Guid Id { get; init; } = Guid.NewGuid();
    public AnnotationKind Kind { get; }
    public AnnotationStyle Style { get; set; }

    public abstract RectF Bounds { get; }

    /// <summary>Opaque area the annotation really covers; also used for hit testing and OCR invalidation.</summary>
    public virtual RectF EffectiveBounds => Bounds.Inflate(Style.Thickness / 2f);

    public abstract bool HitTest(PointF point, float tolerance);

    public abstract void Move(float dx, float dy);

    public abstract void SetBounds(RectF target);

    public abstract AnnotationItem Clone();

    protected static float DistanceToSegment(PointF p, PointF a, PointF b)
    {
        float dx = b.X - a.X, dy = b.Y - a.Y;
        float lengthSquared = dx * dx + dy * dy;
        if (lengthSquared <= 0.0001f) return MathF.Sqrt((p.X - a.X) * (p.X - a.X) + (p.Y - a.Y) * (p.Y - a.Y));
        float t = ((p.X - a.X) * dx + (p.Y - a.Y) * dy) / lengthSquared;
        t = Math.Clamp(t, 0f, 1f);
        float px = a.X + t * dx, py = a.Y + t * dy;
        return MathF.Sqrt((p.X - px) * (p.X - px) + (p.Y - py) * (p.Y - py));
    }

    protected static float DistanceToStroke(PointF p, IReadOnlyList<PointF> points)
    {
        if (points.Count == 1) return MathF.Sqrt((p.X - points[0].X) * (p.X - points[0].X) + (p.Y - points[0].Y) * (p.Y - points[0].Y));
        float best = float.MaxValue;
        for (int i = 1; i < points.Count; i++)
        {
            float d = DistanceToSegment(p, points[i - 1], points[i]);
            if (d < best) best = d;
        }

        return best;
    }

    protected static bool NearRectEdge(PointF p, RectF rect, float tolerance)
    {
        var outer = rect.Inflate(tolerance);
        var inner = rect.Inflate(-tolerance);
        if (!outer.Contains(p)) return false;
        return !(p.X > inner.X && p.X < inner.Right && p.Y > inner.Y && p.Y < inner.Bottom);
    }
}

public sealed class ArrowItem : AnnotationItem
{
    public ArrowItem(PointF start, PointF end, AnnotationStyle style, float curve = 0f) : base(AnnotationKind.Arrow, style)
    {
        Start = start;
        End = end;
        Curve = curve;
    }

    public PointF Start { get; private set; }
    public PointF End { get; private set; }

    /// <summary>Perpendicular offset of the middle control point; 0 is a straight arrow.</summary>
    public float Curve { get; set; }

    /// <summary>Control point in the middle of the shaft, used for bending the arrow by dragging.</summary>
    public PointF ControlPoint
    {
        get
        {
            float mx = (Start.X + End.X) / 2f, my = (Start.Y + End.Y) / 2f;
            float dx = End.X - Start.X, dy = End.Y - Start.Y;
            float length = MathF.Sqrt(dx * dx + dy * dy);
            if (length < 0.001f) return new PointF(mx, my);
            // Normal of the shaft, scaled by the curve amount.
            return new PointF(mx - dy / length * Curve, my + dx / length * Curve);
        }
    }

    public override RectF Bounds => RectF.FromPoints(new[] { Start, End });

    public override RectF EffectiveBounds => RectF.FromPoints(new[] { Start, End, ControlPoint }).Inflate(Style.Thickness + 6f);

    /// <summary>Quadratic Bezier sampling used for drawing, hit testing and composite bounds.</summary>
    public IReadOnlyList<PointF> Shaft(int segments = 24)
    {
        var control = ControlPoint;
        var points = new List<PointF>(segments + 1);
        for (int i = 0; i <= segments; i++)
        {
            float t = i / (float)segments;
            float mt = 1 - t;
            points.Add(new PointF(
                mt * mt * Start.X + 2 * mt * t * control.X + t * t * End.X,
                mt * mt * Start.Y + 2 * mt * t * control.Y + t * t * End.Y));
        }

        return points;
    }

    public override bool HitTest(PointF point, float tolerance) =>
        DistanceToStroke(point, Shaft()) <= Style.Thickness / 2f + tolerance;

    public override void Move(float dx, float dy)
    {
        Start = new PointF(Start.X + dx, Start.Y + dy);
        End = new PointF(End.X + dx, End.Y + dy);
    }

    public void SetEndpoints(PointF start, PointF end)
    {
        Start = start;
        End = end;
    }

    public override void SetBounds(RectF target)
    {
        var current = Bounds;
        if (current.IsEmpty) return;
        float sx = target.Width / current.Width;
        float sy = target.Height / current.Height;
        Start = new PointF(target.X + (Start.X - current.X) * sx, target.Y + (Start.Y - current.Y) * sy);
        End = new PointF(target.X + (End.X - current.X) * sx, target.Y + (End.Y - current.Y) * sy);
    }

    public override AnnotationItem Clone() => new ArrowItem(Start, End, Style, Curve) { Id = Id };
}

public sealed class RectItem : AnnotationItem
{
    public RectItem(RectF rect, AnnotationStyle style, bool ellipse = false)
        : base(ellipse ? AnnotationKind.Ellipse : AnnotationKind.Rect, style) => Rect = rect;

    public RectF Rect { get; private set; }
    public override RectF Bounds => Rect;

    public override bool HitTest(PointF point, float tolerance)
    {
        if (Style.Filled && Rect.Contains(point)) return true;
        return NearRectEdge(point, Rect, Style.Thickness / 2f + tolerance);
    }

    public override void Move(float dx, float dy) => Rect = Rect.Offset(dx, dy);

    public override void SetBounds(RectF target) => Rect = target;

    public override AnnotationItem Clone() => new RectItem(Rect, Style, Kind == AnnotationKind.Ellipse) { Id = Id };
}

public sealed class PenItem : AnnotationItem
{
    public PenItem(IReadOnlyList<PointF> points, AnnotationStyle style, bool highlight = false)
        : base(highlight ? AnnotationKind.Highlight : AnnotationKind.Pen, style)
    {
        Points = new List<PointF>(points);
    }

    public List<PointF> Points { get; }
    public override RectF Bounds => RectF.FromPoints(Points);
    public override RectF EffectiveBounds => Bounds.Inflate(Style.Thickness);

    public override bool HitTest(PointF point, float tolerance) => DistanceToStroke(point, Points) <= Style.Thickness / 2f + tolerance;

    public override void Move(float dx, float dy)
    {
        for (int i = 0; i < Points.Count; i++) Points[i] = new PointF(Points[i].X + dx, Points[i].Y + dy);
    }

    public override void SetBounds(RectF target)
    {
        var current = Bounds;
        if (current.IsEmpty) return;
        float sx = target.Width / current.Width, sy = target.Height / current.Height;
        for (int i = 0; i < Points.Count; i++)
            Points[i] = new PointF(target.X + (Points[i].X - current.X) * sx, target.Y + (Points[i].Y - current.Y) * sy);
    }

    public override AnnotationItem Clone() => new PenItem(Points, Style, Kind == AnnotationKind.Highlight) { Id = Id };
}

public sealed class MaskItem : AnnotationItem
{
    public MaskItem(IReadOnlyList<PointF> points, AnnotationStyle style, MaskEffect effect, RectF? fillRect = null)
        : base(AnnotationKind.Mask, style)
    {
        Points = new List<PointF>(points);
        Effect = effect;
        FillRect = fillRect;
    }

    public List<PointF> Points { get; }
    public MaskEffect Effect { get; set; }

    /// <summary>Set for the rectangle mode; null for the brush mode.</summary>
    public RectF? FillRect { get; private set; }

    public override RectF Bounds => FillRect ?? RectF.FromPoints(Points);
    public override RectF EffectiveBounds => FillRect?.Inflate(1f) ?? Bounds.Inflate(Style.Thickness);

    /// <summary>True only for effects that fully replace the pixels underneath.</summary>
    public bool IsOpaqueRedaction => Effect == MaskEffect.Solid;

    public override bool HitTest(PointF point, float tolerance)
    {
        if (FillRect.HasValue) return FillRect.Value.Inflate(tolerance).Contains(point);
        return DistanceToStroke(point, Points) <= Style.Thickness / 2f + tolerance;
    }

    public override void Move(float dx, float dy)
    {
        if (FillRect.HasValue)
        {
            FillRect = FillRect.Value.Offset(dx, dy);
            return;
        }

        for (int i = 0; i < Points.Count; i++) Points[i] = new PointF(Points[i].X + dx, Points[i].Y + dy);
    }

    public override void SetBounds(RectF target)
    {
        if (FillRect.HasValue)
        {
            FillRect = target;
            return;
        }

        var current = Bounds;
        if (current.IsEmpty) return;
        float sx = target.Width / current.Width, sy = target.Height / current.Height;
        for (int i = 0; i < Points.Count; i++)
            Points[i] = new PointF(target.X + (Points[i].X - current.X) * sx, target.Y + (Points[i].Y - current.Y) * sy);
    }

    public override AnnotationItem Clone() => new MaskItem(Points, Style, Effect, FillRect) { Id = Id };
}

public sealed class TextItem : AnnotationItem
{
    public TextItem(string text, PointF origin, AnnotationStyle style, RectF measuredBox)
        : base(AnnotationKind.Text, style)
    {
        Text = text;
        Origin = origin;
        MeasuredBox = measuredBox;
    }

    public string Text { get; set; }
    public PointF Origin { get; private set; }

    /// <summary>Box measured by the UI layer with the real font; Core stays font-engine independent.</summary>
    public RectF MeasuredBox { get; private set; }

    public override RectF Bounds => RectF.FromEdges(MathF.Min(Origin.X, MeasuredBox.X), MathF.Min(Origin.Y, MeasuredBox.Y),
        MathF.Max(Origin.X + MeasuredBox.Width, MeasuredBox.Right), MathF.Max(Origin.Y + MeasuredBox.Height, MeasuredBox.Bottom));

    public bool HasBackground => (Style.FillArgb & 0xFF) != 0;

    public override bool HitTest(PointF point, float tolerance) => Bounds.Inflate(tolerance).Contains(point);

    public override void Move(float dx, float dy)
    {
        Origin = new PointF(Origin.X + dx, Origin.Y + dy);
        MeasuredBox = MeasuredBox.Offset(dx, dy);
    }

    public override void SetBounds(RectF target)
    {
        var current = Bounds;
        if (current.IsEmpty) return;
        Origin = new PointF(target.X + (Origin.X - current.X) * (target.Width / current.Width),
            target.Y + (Origin.Y - current.Y) * (target.Height / current.Height));
        MeasuredBox = new RectF(Origin.X, Origin.Y, target.Width, target.Height);
    }

    public override AnnotationItem Clone() => new TextItem(Text, Origin, Style, MeasuredBox) { Id = Id };
}

public sealed class NumberItem : AnnotationItem
{
    public NumberItem(int number, PointF center, AnnotationStyle style)
        : base(AnnotationKind.Number, style)
    {
        Number = number;
        Center = center;
    }

    public int Number { get; set; }
    public PointF Center { get; private set; }
    public float Radius { get; set; } = 14f;
    public override RectF Bounds => new(Center.X - Radius, Center.Y - Radius, Radius * 2, Radius * 2);

    public override bool HitTest(PointF point, float tolerance) =>
        MathF.Sqrt((point.X - Center.X) * (point.X - Center.X) + (point.Y - Center.Y) * (point.Y - Center.Y)) <= Radius + tolerance;

    public override void Move(float dx, float dy) => Center = new PointF(Center.X + dx, Center.Y + dy);

    public override void SetBounds(RectF target)
    {
        Center = target.Center;
        Radius = MathF.Max(4f, MathF.Min(target.Width, target.Height) / 2f);
    }

    public override AnnotationItem Clone() => new NumberItem(Number, Center, Style) { Id = Id, Radius = Radius };
}
