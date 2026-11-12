using System;
using System.Collections.Generic;
using System.Linq;
using ccShot.Core.Geometry;

namespace ccShot.Core.Capture;

/// <summary>
/// One monitor in physical pixels. <c>BoundsPx</c> uses the virtual-desktop coordinate space where the
/// primary monitor's top-left is (0,0) and secondary monitors can have negative x or y.
/// </summary>
public sealed record MonitorInfo(string DeviceName, RectI BoundsPx, double Scale, bool IsPrimary)
{
    /// <summary>Physical pixels per DIP, derived from the effective DPI (for example 1.5 at 150%).</summary>
    public double EffectiveScale => Scale <= 0 ? 1.0 : Scale;

    public RectI VirtualRectPx(int margin = 0) =>
        margin == 0 ? BoundsPx : new RectI(BoundsPx.X - margin, BoundsPx.Y - margin,
            BoundsPx.Width + margin * 2, BoundsPx.Height + margin * 2);
}

/// <summary>
/// Geometry of a multi-monitor desktop, independent of Win32 so it can be unit tested: hit testing,
/// negative origins, conversions between screen pixels and per-monitor capture pixels.
/// </summary>
public sealed class MonitorLayout
{
    public MonitorLayout(IEnumerable<MonitorInfo> monitors)
    {
        Monitors = monitors.ToList();
        if (Monitors.Count == 0) throw new ArgumentException("At least one monitor is required.", nameof(monitors));
        int left = Monitors.Min(m => m.BoundsPx.X);
        int top = Monitors.Min(m => m.BoundsPx.Y);
        int right = Monitors.Max(m => m.BoundsPx.Right);
        int bottom = Monitors.Max(m => m.BoundsPx.Bottom);
        VirtualDesktopPx = RectI.FromEdges(left, top, right, bottom);
    }

    public IReadOnlyList<MonitorInfo> Monitors { get; }

    /// <summary>Union of all monitors; the capture overlay for "all screens" uses this.</summary>
    public RectI VirtualDesktopPx { get; }

    public MonitorInfo Primary => Monitors.FirstOrDefault(m => m.IsPrimary) ?? Monitors[0];

    public MonitorInfo? MonitorAt(PointF screenPx)
    {
        foreach (var monitor in Monitors)
        {
            if (screenPx.X >= monitor.BoundsPx.X && screenPx.X < monitor.BoundsPx.Right &&
                screenPx.Y >= monitor.BoundsPx.Y && screenPx.Y < monitor.BoundsPx.Bottom)
            {
                return monitor;
            }
        }

        return null;
    }

    /// <summary>Monitor whose rectangle is closest to the point; used when the pointer sits in a gap.</summary>
    public MonitorInfo NearestMonitor(PointF screenPx)
    {
        MonitorInfo best = Monitors[0];
        float bestDistance = float.MaxValue;
        foreach (var monitor in Monitors)
        {
            var b = monitor.BoundsPx;
            float dx = screenPx.X < b.X ? b.X - screenPx.X : screenPx.X > b.Right ? screenPx.X - b.Right : 0f;
            float dy = screenPx.Y < b.Y ? b.Y - screenPx.Y : screenPx.Y > b.Bottom ? screenPx.Y - b.Bottom : 0f;
            float distance = dx * dx + dy * dy;
            if (distance < bestDistance)
            {
                bestDistance = distance;
                best = monitor;
            }
        }

        return best;
    }

    /// <summary>Screen pixel to capture-local pixel for a given monitor.</summary>
    public static PointF ScreenToLocal(MonitorInfo monitor, PointF screenPx) =>
        new(screenPx.X - monitor.BoundsPx.X, screenPx.Y - monitor.BoundsPx.Y);

    public static PointF LocalToScreen(MonitorInfo monitor, PointF localPx) =>
        new(localPx.X + monitor.BoundsPx.X, localPx.Y + monitor.BoundsPx.Y);

    /// <summary>Screen rectangle to capture-local pixel rectangle, clipped to the monitor.</summary>
    public static RectI ScreenRectToLocal(MonitorInfo monitor, RectI screenRect) =>
        screenRect.Offset(-monitor.BoundsPx.X, -monitor.BoundsPx.Y).Intersect(new RectI(0, 0, monitor.BoundsPx.Width, monitor.BoundsPx.Height));

    /// <summary>
    /// Converts a screen-pixel rectangle that may span several monitors into one image rectangle per
    /// monitor. Needed because each monitor is captured separately before being stitched.
    /// </summary>
    public IReadOnlyList<(MonitorInfo Monitor, RectI Local)> Split(ScreenRectSelection selection)
    {
        var result = new List<(MonitorInfo, RectI)>();
        foreach (var monitor in Monitors)
        {
            var local = ScreenRectToLocal(monitor, selection.ScreenRectPx);
            if (!local.IsEmpty) result.Add((monitor, local));
        }

        return result;
    }

    public MonitorLayout WithScales(IReadOnlyDictionary<string, double> scales) =>
        new(Monitors.Select(m => m with { Scale = scales.TryGetValue(m.DeviceName, out var s) && s > 0 ? s : m.Scale }));
}

/// <summary>A rectangle expressed in virtual-desktop screen pixels.</summary>
public readonly record struct ScreenRectSelection(RectI ScreenRectPx)
{
    public ScreenRectSelection Normalize() => new(ScreenRectPx);
}
