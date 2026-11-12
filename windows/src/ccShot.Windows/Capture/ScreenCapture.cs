using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using ccShot.Core.Capture;
using ccShot.Core.Geometry;
using ccShot.Core.Imaging;
using ccShot.Windows.Interop;

namespace ccShot.Windows.Capture;

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
        if (screenDc == IntPtr.Zero) throw new InvalidOperationException("无法读取屏幕。");
        IntPtr memoryDc = IntPtr.Zero, bitmap = IntPtr.Zero;
        try
        {
            memoryDc = NativeMethods.CreateCompatibleDC(screenDc);
            bitmap = NativeMethods.CreateCompatibleBitmap(screenDc, rect.Width, rect.Height);
            if (memoryDc == IntPtr.Zero || bitmap == IntPtr.Zero)
                throw new InvalidOperationException("无法为截图分配位图。");

            IntPtr previous = NativeMethods.SelectObject(memoryDc, bitmap);
            if (previous == IntPtr.Zero || previous == new IntPtr(-1))
                throw new InvalidOperationException("无法为截图选择位图。");
            try
            {
                if (!NativeMethods.BitBlt(memoryDc, 0, 0, rect.Width, rect.Height, screenDc, rect.X, rect.Y,
                        NativeMethods.SRCCOPY | NativeMethods.CAPTUREBLT))
                    throw new InvalidOperationException("无法读取屏幕像素。");
            }
            finally
            {
                NativeMethods.SelectObject(memoryDc, previous);
            }

            var buffer = new byte[checked(rect.Width * rect.Height * 4)];
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
            if (lines != rect.Height) throw new InvalidOperationException("未读取到完整的屏幕像素。");
            // BI_RGB 的第四字节未定义，屏幕快照按不透明图像处理。
            for (int alpha = 3; alpha < buffer.Length; alpha += 4) buffer[alpha] = 255;
            return new PixelImage(rect.Width, rect.Height, buffer);
        }
        finally
        {
            if (bitmap != IntPtr.Zero) NativeMethods.DeleteObject(bitmap);
            if (memoryDc != IntPtr.Zero) NativeMethods.DeleteDC(memoryDc);
            NativeMethods.ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    public static PixelImage CaptureMonitor(MonitorInfo monitor) => Capture(monitor.BoundsPx);

    public static PixelImage CaptureVirtualDesktop(MonitorLayout layout) => Capture(layout.VirtualDesktopPx);

    /// <summary>在遮罩打开前按层级保存可见窗口的物理屏幕坐标。</summary>
    public static IReadOnlyList<RectI> SnapshotWindowBounds(RectI desktop)
    {
        var bounds = new List<RectI>();
        IntPtr shell = NativeMethods.GetShellWindow();
        NativeMethods.EnumWindows((window, _) =>
        {
            if (window == shell || !NativeMethods.IsWindowVisible(window) || NativeMethods.IsIconic(window)) return true;
            if (NativeMethods.DwmGetWindowAttributeInt(window, NativeMethods.DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 && cloaked != 0)
                return true;

            var rect = NativeMethods.GetVisibleWindowRect(window);
            var visible = new RectI(rect.Left, rect.Top, rect.Width, rect.Height).Intersect(desktop);
            if (!visible.IsEmpty) bounds.Add(visible);
            return true;
        }, IntPtr.Zero);
        return bounds;
    }
}
