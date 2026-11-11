using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using CcShot.Core.Capture;
using CcShot.Core.Geometry;
using CcShot.Windows.Capture;
using CcShot.Windows.Interop;
using CcShot.Windows.Theme;

namespace CcShot.Windows.Capture;

internal enum CaptureMode
{
    Region,
    Window,
}

/// <summary>
/// Full-screen selection overlay, one borderless window per monitor so every monitor keeps its own DPI.
/// The screenshot itself is taken before the overlay appears, so the overlay can never end up in the
/// captured pixels and there is no flicker when the selection is confirmed.
/// </summary>
internal sealed class CaptureOverlayWindow : Window
{
    private readonly MonitorInfo _monitor;
    private readonly CaptureMode _mode;
    private readonly CaptureCanvas _canvas;
    private readonly TaskCompletionSource<RectI?> _completion;
    private readonly Action _closeAll;

    public CaptureOverlayWindow(MonitorInfo monitor, CaptureMode mode, TaskCompletionSource<RectI?> completion, Action closeAll)
    {
        _monitor = monitor;
        _mode = mode;
        _completion = completion;
        _closeAll = closeAll;

        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        Cursor = Cursors.Cross;
        Title = "ccShot 截图";

        _canvas = new CaptureCanvas(monitor, mode);
        _canvas.Picked += OnPicked;
        _canvas.Cancelled += OnCancel;
        Content = _canvas;

        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            NativeMethods.SetWindowPos(handle, IntPtr.Zero, monitor.BoundsPx.X, monitor.BoundsPx.Y,
                monitor.BoundsPx.Width, monitor.BoundsPx.Height,
                NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);
        };
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape)
            {
                OnCancel();
                e.Handled = true;
            }
        };
    }

    private void OnPicked(RectI localPixels)
    {
        var global = localPixels.Offset(_monitor.BoundsPx.X, _monitor.BoundsPx.Y);
        _completion.TrySetResult(global);
        _closeAll();
    }

    private void OnCancel()
    {
        _completion.TrySetResult(null);
        _closeAll();
    }

    protected override void OnMouseRightButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseRightButtonUp(e);
        OnCancel();
    }
}

/// <summary>Draws the dimming, the selection rectangle, its pixel size and the window highlight.</summary>
internal sealed class CaptureCanvas : FrameworkElement
{
    private readonly MonitorInfo _monitor;
    private readonly CaptureMode _mode;
    private Point _start;
    private Point _current;
    private bool _dragging;
    private bool _hasSelection;
    private RectI _windowRect = RectI.FromEdges(0, 0, 0, 0);

    public CaptureCanvas(MonitorInfo monitor, CaptureMode mode)
    {
        _monitor = monitor;
        _mode = mode;
        Focusable = true;
    }

    public event Action<RectI>? Picked;
    public event Action? Cancelled;

    private double Scale => _monitor.EffectiveScale;

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);

        if (_mode == CaptureMode.Window && !_hasSelection)
        {
            dc.DrawRectangle(Palette.DimBrush, null, bounds);
            if (!_windowRect.IsEmpty)
            {
                var highlight = new Rect(_windowRect.X / Scale, _windowRect.Y / Scale, _windowRect.Width / Scale, _windowRect.Height / Scale);
                dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(0x18, 0xFF, 0xFF, 0xFF)), new Pen(Palette.AccentSoftBrush, 2), highlight);
                DrawLabel(dc, highlight, $"{_windowRect.Width} × {_windowRect.Height}");
            }

            DrawHint(dc, bounds);
            return;
        }

        if (!_hasSelection)
        {
            dc.DrawRectangle(Palette.DimBrush, null, bounds);
            DrawHint(dc, bounds);
            return;
        }

        var selection = SelectionDip();
        var dim = new CombinedGeometry(GeometryCombineMode.Exclude,
            new RectangleGeometry(bounds), new RectangleGeometry(selection));
        dc.DrawGeometry(Palette.DimBrush, null, dim);
        dc.DrawRectangle(null, new Pen(Palette.AccentSoftBrush, 1.5), selection);
        DrawLabel(dc, selection, $"{_windowRect.Width} × {_windowRect.Height}");
    }

    private Rect SelectionDip() => new(Math.Min(_start.X, _current.X), Math.Min(_start.Y, _current.Y),
        Math.Abs(_current.X - _start.X), Math.Abs(_current.Y - _start.Y));

    private void DrawLabel(DrawingContext dc, Rect selection, string sizeText)
    {
        var text = sizeText;
        if (string.IsNullOrEmpty(text)) return;
        var formatted = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface("Microsoft YaHei UI"), 13, Palette.WhiteBrush, 1.0);
        double width = formatted.Width + 14;
        double height = formatted.Height + 8;
        double x = selection.X;
        double y = selection.Y - height - 6;
        if (y < 0) y = selection.Y + 6;
        var panel = new Rect(x, y, width, height);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0xCC, 0x1F, 0x25, 0x2B)), null, panel, 5, 5);
        dc.DrawText(formatted, new Point(panel.X + 7, panel.Y + 4));
    }

    private void DrawHint(DrawingContext dc, Rect bounds)
    {
        string hint = _mode == CaptureMode.Window ? "点击要截取的窗口，Esc 取消" : "拖动选择区域，Esc 取消";
        var formatted = new FormattedText(hint, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface("Microsoft YaHei UI"), 15, Palette.WhiteBrush, 1.0);
        var center = new Point(bounds.Width / 2 - formatted.Width / 2, 42);
        var panel = new Rect(center.X - 16, center.Y - 8, formatted.Width + 32, formatted.Height + 16);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0xD0, 0x1F, 0x25, 0x2B)), null, panel, 8, 8);
        dc.DrawText(formatted, center);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        Focus();
        _start = _current = e.GetPosition(this);
        _dragging = true;
        _hasSelection = false;
        CaptureMouse();
        InvalidateVisual();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var position = e.GetPosition(this);
        if (_dragging)
        {
            _current = position;
            _hasSelection = true;
            _windowRect = LocalPixels();
            InvalidateVisual();
            return;
        }

        if (_mode == CaptureMode.Window)
        {
            var screenPoint = new PointF(
                (float)(position.X * Scale) + _monitor.BoundsPx.X,
                (float)(position.Y * Scale) + _monitor.BoundsPx.Y);
            var window = ScreenCaptureService.CaptureWindowAt(screenPoint);
            if (window.HasValue)
            {
                var local = window.Value.Rect.Offset(-_monitor.BoundsPx.X, -_monitor.BoundsPx.Y);
                if (local != _windowRect)
                {
                    _windowRect = local;
                    InvalidateVisual();
                }
            }
        }
    }

    private RectI LocalPixels()
    {
        double scale = Scale;
        float x0 = (float)(Math.Min(_start.X, _current.X) * scale);
        float y0 = (float)(Math.Min(_start.Y, _current.Y) * scale);
        float x1 = (float)(Math.Max(_start.X, _current.X) * scale);
        float y1 = (float)(Math.Max(_start.Y, _current.Y) * scale);
        return RectI.FromEdges((int)Math.Round(x0), (int)Math.Round(y0), (int)Math.Round(x1), (int)Math.Round(y1));
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        ReleaseMouseCapture();
        _dragging = false;

        if (_mode == CaptureMode.Window)
        {
            var position = e.GetPosition(this);
            var screenPoint = new PointF(
                (float)(position.X * Scale) + _monitor.BoundsPx.X,
                (float)(position.Y * Scale) + _monitor.BoundsPx.Y);
            var window = ScreenCaptureService.CaptureWindowAt(screenPoint);
            if (window.HasValue) Picked?.Invoke(window.Value.Rect);
            else Cancelled?.Invoke();
            return;
        }

        var selection = LocalPixels();
        if (selection.Width < 4 || selection.Height < 4)
        {
            _hasSelection = false;
            InvalidateVisual();
            return;
        }

        Picked?.Invoke(selection);
    }
}
