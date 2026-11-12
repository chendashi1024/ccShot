using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ccShot.Core.Annotate;
using ccShot.Core.Geometry;
using ccShot.Windows.Theme;

namespace ccShot.Windows.Rendering;

/// <summary>Full-image bitmaps used for the mosaic and blur previews, plus the rectangle they fill.</summary>
internal sealed record MaskImages(BitmapSource Image, BitmapSource? Pixelated, BitmapSource? Blurred, Rect ImageRect);

/// <summary>
/// Draws annotations onto a <see cref="DrawingContext"/>. The editor canvas and the export compositor use
/// the same code, so what the user sees and what is copied or saved cannot drift apart.
/// </summary>
internal static class AnnotationRenderer
{
    public static readonly Typeface UiTypeface = new(
        new FontFamily("Microsoft YaHei UI, Segoe UI, sans-serif"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);

    public static void Draw(DrawingContext dc, AnnotationItem item, double scale, MaskImages? masks = null)
    {
        var color = Palette.ColorFor(item.Style.ColorArgb);
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        var pen = MakePen(brush, item.Style.Thickness * scale);

        switch (item)
        {
            case ArrowItem arrow:
                DrawArrow(dc, arrow, scale, brush, pen);
                break;
            case RectItem rect when rect.Kind == AnnotationKind.Ellipse:
                var bounds = ToRect(rect.Rect, scale);
                dc.DrawEllipse(rect.Style.Filled ? BrushFor(item.Style.FillArgb, color) : null, pen,
                    new Point(bounds.X + bounds.Width / 2, bounds.Y + bounds.Height / 2),
                    bounds.Width / 2, bounds.Height / 2);
                break;
            case RectItem rect:
                dc.DrawRoundedRectangle(rect.Style.Filled ? BrushFor(item.Style.FillArgb, color) : null, pen,
                    ToRect(rect.Rect, scale), 6 * scale, 6 * scale);
                break;
            case PenItem penItem:
                DrawPolyline(dc, penItem.Points, scale, pen);
                break;
            case MaskItem mask:
                DrawMask(dc, mask, scale, brush, pen, masks);
                break;
            case TextItem text:
                DrawText(dc, text, scale);
                break;
            case NumberItem number:
                DrawNumber(dc, number, scale, brush, pen);
                break;
        }
    }

    private static Brush BrushFor(uint argb, Color fallback) =>
        (argb & 0xFF) == 0 ? new SolidColorBrush(fallback) : Palette.BrushFor(argb);

    private static Pen MakePen(Brush brush, double thickness) =>
        new(brush, Math.Max(0.8, thickness)) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };

    private static Rect ToRect(RectF rect, double scale) =>
        new(rect.X * scale, rect.Y * scale, Math.Max(1, rect.Width * scale), Math.Max(1, rect.Height * scale));

    private static void DrawPolyline(DrawingContext dc, IReadOnlyList<PointF> points, double scale, Pen pen)
    {
        if (points.Count == 0) return;
        if (points.Count == 1)
        {
            dc.DrawEllipse(pen.Brush, null, new Point(points[0].X * scale, points[0].Y * scale), pen.Thickness / 2, pen.Thickness / 2);
            return;
        }

        var geometry = new StreamGeometry();
        using (var ctx = geometry.Open())
        {
            ctx.BeginFigure(new Point(points[0].X * scale, points[0].Y * scale), false, false);
            ctx.PolyLineTo(ToPoints(points, scale, 1), true, true);
        }

        geometry.Freeze();
        dc.DrawGeometry(null, pen, geometry);
    }

    private static List<Point> ToPoints(IReadOnlyList<PointF> points, double scale, int startIndex)
    {
        var list = new List<Point>(points.Count);
        for (int i = startIndex; i < points.Count; i++) list.Add(new Point(points[i].X * scale, points[i].Y * scale));
        return list;
    }

    private static void DrawArrow(DrawingContext dc, ArrowItem arrow, double scale, Brush brush, Pen pen)
    {
        var shaft = arrow.Shaft();
        DrawPolyline(dc, shaft, scale, pen);

        // Arrow head built from the last two sample points so curved arrows keep pointing along the curve.
        var end = shaft[^1];
        var before = shaft[Math.Max(0, shaft.Count - 3)];
        float dx = end.X - before.X, dy = end.Y - before.Y;
        float length = MathF.Sqrt(dx * dx + dy * dy);
        if (length < 0.01f) return;
        dx /= length;
        dy /= length;

        float headLength = MathF.Max(8f, arrow.Style.Thickness * 4f);
        float headWidth = headLength * 0.55f;
        var tip = new Point(end.X * scale, end.Y * scale);
        var left = new Point((end.X - dx * headLength + dy * headWidth) * scale, (end.Y - dy * headLength - dx * headWidth) * scale);
        var right = new Point((end.X - dx * headLength - dy * headWidth) * scale, (end.Y - dy * headLength + dx * headWidth) * scale);

        var head = new StreamGeometry();
        using (var ctx = head.Open())
        {
            ctx.BeginFigure(tip, true, true);
            ctx.PolyLineTo(new[] { left, right }, true, true);
        }

        head.Freeze();
        dc.DrawGeometry(brush, null, head);
    }

    private static void DrawMask(DrawingContext dc, MaskItem mask, double scale, Brush brush, Pen pen, MaskImages? masks)
    {
        Geometry geometry;
        if (mask.FillRect is { } rect)
        {
            geometry = new RectangleGeometry(ToRect(rect, scale));
        }
        else
        {
            var path = new StreamGeometry();
            using (var ctx = path.Open())
            {
                var points = mask.Points;
                if (points.Count == 0) return;
                ctx.BeginFigure(new Point(points[0].X * scale, points[0].Y * scale), false, false);
                if (points.Count > 1) ctx.PolyLineTo(ToPoints(points, scale, 1), true, true);
                else ctx.LineTo(new Point(points[0].X * scale + 0.1, points[0].Y * scale), true, true);
            }

            path.Freeze();
            geometry = path.GetWidenedPathGeometry(pen);
        }

        switch (mask.Effect)
        {
            case MaskEffect.Solid:
                var solid = new SolidColorBrush(Palette.ColorFor(mask.Style.ColorArgb)) { Opacity = 1 };
                solid.Freeze();
                dc.DrawGeometry(solid, null, geometry);
                break;
            case MaskEffect.Mosaic when masks?.Pixelated != null:
                dc.PushClip(geometry);
                dc.DrawImage(masks.Pixelated, masks.ImageRect);
                dc.Pop();
                break;
            case MaskEffect.Blur when masks?.Blurred != null:
                dc.PushClip(geometry);
                dc.DrawImage(masks.Blurred, masks.ImageRect);
                dc.Pop();
                break;
            default:
                dc.DrawGeometry(Palette.DimBrush, null, geometry);
                break;
        }
    }

    private static void DrawText(DrawingContext dc, TextItem text, double scale)
    {
        var brush = new SolidColorBrush(Palette.ColorFor(text.Style.ColorArgb));
        brush.Freeze();
        var formatted = new FormattedText(
            string.IsNullOrEmpty(text.Text) ? " " : text.Text,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            text.Style.Bold
                ? new Typeface(UiTypeface.FontFamily, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal)
                : UiTypeface,
            Math.Max(6, text.Style.FontSize * scale),
            brush,
            1.0);

        var origin = new Point(text.Origin.X * scale, text.Origin.Y * scale);
        if (text.HasBackground)
        {
            var background = new SolidColorBrush(Palette.ColorFor(text.Style.FillArgb));
            background.Freeze();
            dc.DrawRectangle(background, null, new Rect(origin.X - 4 * scale, origin.Y - 2 * scale,
                formatted.Width + 8 * scale, formatted.Height + 4 * scale));
        }

        dc.DrawText(formatted, origin);
    }

    private static void DrawNumber(DrawingContext dc, NumberItem number, double scale, Brush brush, Pen pen)
    {
        var center = new Point(number.Center.X * scale, number.Center.Y * scale);
        var radius = Math.Max(6, number.Radius * scale);
        dc.DrawEllipse(brush, pen, center, radius, radius);

        var formatted = new FormattedText(
            number.Number.ToString(CultureInfo.InvariantCulture),
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface(UiTypeface.FontFamily, FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal),
            radius * 1.05,
            Brushes.White,
            1.0);
        dc.DrawText(formatted, new Point(center.X - formatted.Width / 2, center.Y - formatted.Height / 2));
    }

    /// <summary>Measures a text annotation so its box matches what will be painted.</summary>
    public static Size MeasureText(string text, AnnotationStyle style, double scale) =>
        new(text.Length * style.FontSize * 0.62 * scale, style.FontSize * 1.35 * scale);
}
