using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using CcShot.Core.Capture;
using CcShot.Core.Geometry;
using CcShot.Core.Imaging;
using CcShot.Windows.Interop;

namespace CcShot.Windows.Capture;

/// <summary>Reads the real desktop layout: physical pixel rectangles plus the effective DPI of each monitor.</summary>
internal static class MonitorService
{
    public static MonitorLayout Enumerate()
    {
        var monitors = new List<MonitorInfo>();
        var primaryHandle = IntPtr.Zero;

        NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr hdc, ref NativeMethods.RECT rect, IntPtr data) =>
        {
            var info = new NativeMethods.MONITORINFOEX { cbSize = Marshal.SizeOf<NativeMethods.MONITORINFOEX>() };
            if (!NativeMethods.GetMonitorInfo(hMonitor, ref info)) return true;

            double scale = 1.0;
            if (NativeMethods.GetDpiForMonitor(hMonitor, NativeMethods.MDT_EFFECTIVE_DPI, out uint dpiX, out _) == 0 && dpiX > 0)
                scale = dpiX / 96.0;
            else
                scale = GetScaleFromWindow(hMonitor);

            bool isPrimary = (info.dwFlags & 1) != 0;
            if (isPrimary) primaryHandle = hMonitor;
            monitors.Add(new MonitorInfo(info.szDevice, new RectI(info.rcMonitor.Left, info.rcMonitor.Top,
                info.rcMonitor.Width, info.rcMonitor.Height), scale, isPrimary));
            return true;
        }, IntPtr.Zero);

        if (monitors.Count == 0)
        {
            // Last resort so the app still starts (for example in a remote session with odd APIs).
            monitors.Add(new MonitorInfo("DISPLAY", new RectI(0, 0, 1920, 1080), 1.0, true));
        }

        bool anyPrimary = monitors.Exists(m => m.IsPrimary);
        if (!anyPrimary && primaryHandle != IntPtr.Zero) monitors[0] = monitors[0] with { IsPrimary = true };
        _ = primaryHandle;
        return new MonitorLayout(monitors);
    }

    private static double GetScaleFromWindow(IntPtr monitor)
    {
        // Fallback: compare the monitor rect against the work area is not reliable; assume 100%.
        _ = monitor;
        return 1.0;
    }

    public static MonitorInfo PrimaryMonitor() => Enumerate().Primary;
}

/// <summary>Bitmap capture through GDI. Produces the tightly packed BGRA buffer the rest of the app uses.</summary>
internal static class ScreenCaptureService
{
    public static PixelImage Capture(RectI rect)
    {
        if (rect.IsEmpty) return PixelImage.Empty;
        IntPtr screenDc = NativeMethods.GetDC(IntPtr.Zero);
        IntPtr memoryDc = NativeMethods.CreateCompatibleDC(screenDc);
        IntPtr bitmap = NativeMethods.CreateCompatibleBitmap(screenDc, rect.Width, rect.Height);
        IntPtr previous = NativeMethods.SelectObject(memoryDc, bitmap);
        try
        {
            bool copied = NativeMethods.BitBlt(memoryDc, 0, 0, rect.Width, rect.Height, screenDc, rect.X, rect.Y,
                NativeMethods.SRCCOPY | NativeMethods.CAPTUREBLT);
            if (!copied) throw new InvalidOperationException("屏幕截图失败：BitBlt 未完成。");

            var buffer = new byte[rect.Width * rect.Height * 4];
            var header = new NativeMethods.BITMAPINFOHEADER
            {
                biSize = (uint)Marshal.SizeOf<NativeMethods.BITMAPINFOHEADER>(),
                biWidth = rect.Width,
                biHeight = -rect.Height, // top-down rows
                biPlanes = 1,
                biBitCount = 32,
                biCompression = NativeMethods.BI_RGB,
            };
            int lines = NativeMethods.GetDIBits(memoryDc, bitmap, 0, (uint)rect.Height, buffer, ref header, NativeMethods.DIB_RGB_COLORS);
            if (lines == 0) throw new InvalidOperationException("屏幕截图失败：GetDIBits 未返回像素。");
            return new PixelImage(rect.Width, rect.Height, buffer);
        }
        finally
        {
            NativeMethods.SelectObject(memoryDc, previous);
            NativeMethods.DeleteObject(bitmap);
            NativeMethods.DeleteDC(memoryDc);
            NativeMethods.ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    public static PixelImage CaptureMonitor(MonitorInfo monitor) => Capture(monitor.BoundsPx);

    public static PixelImage CaptureVirtualDesktop(MonitorLayout layout) => Capture(layout.VirtualDesktopPx);

    /// <summary>Window under the given screen point, captured without the invisible DWM resize border.</summary>
    public static (PixelImage Image, RectI Rect)? CaptureWindowAt(PointF screenPoint)
    {
        var point = new NativeMethods.POINT { X = (int)MathF.Round(screenPoint.X), Y = (int)MathF.Round(screenPoint.Y) };
        IntPtr hwnd = NativeMethods.WindowFromPoint(point);
        if (hwnd == IntPtr.Zero) return null;
        IntPtr root = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
        if (root != IntPtr.Zero) hwnd = root;

        var rect = NativeMethods.GetVisibleWindowRect(hwnd);
        if (rect.Width <= 0 || rect.Height <= 0) return null;
        var bounds = new RectI(rect.Left, rect.Top, rect.Width, rect.Height);
        return (Capture(bounds), bounds);
    }
}
