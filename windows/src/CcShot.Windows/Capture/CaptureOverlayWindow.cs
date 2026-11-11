using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CcShot.Core.Capture;
using CcShot.Core.Geometry;
using CcShot.Windows.Interop;
using CcShot.Windows.Theme;

namespace CcShot.Windows.Capture;

internal enum CaptureMode { Region, Window }

/// <summary>所有屏幕共享物理像素选区，避免在不同 DPI 的窗口之间重复换算。</summary>
internal sealed class CaptureSelection
{
    public RectI Bounds { get; private set; }
    public event Action? Changed;

    public void Set(RectI bounds)
    {
        if (Bounds == bounds) return;
        Bounds = bounds;
        Changed?.Invoke();
    }
}

internal sealed class CaptureOverlayWindow : Window
{
    public CaptureOverlayWindow(MonitorInfo monitor, RectI desktop, CaptureMode mode, BitmapSource background,
        IReadOnlyList<RectI> targets, CaptureSelection selection, Action<RectI?> finish)
    {
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        Title = "ccShot 截图";

        var canvas = new CaptureCanvas(monitor, desktop, mode, background, targets, selection, finish);
        Content = canvas;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            var bounds = monitor.BoundsPx;
            NativeMethods.SetWindowPos(handle, IntPtr.Zero, bounds.X, bounds.Y, bounds.Width, bounds.Height,
                NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
        };
        Loaded += (_, _) => canvas.Focus();
        Closed += (_, _) =>
        {
            canvas.Detach();
            finish(null);
        };
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) finish(null);
            else if (e.Key == Key.Enter && mode == CaptureMode.Region) canvas.ConfirmRegion();
            else return;
            e.Handled = true;
        };
    }
}

internal sealed class CaptureCanvas : FrameworkElement
{
    private readonly MonitorInfo _monitor;
    private readonly RectI _desktop;
    private readonly CaptureMode _mode;
    private readonly BitmapSource _background;
    private readonly IReadOnlyList<RectI> _targets;
    private readonly CaptureSelection _selection;
    private readonly Action<RectI?> _finish;
    private PointF _start;
    private RectI _initial;
    private int _horizontalEdge, _verticalEdge;
    private bool _dragging;
    private bool _adjusting;

    public CaptureCanvas(MonitorInfo monitor, RectI desktop, CaptureMode mode, BitmapSource background,
        IReadOnlyList<RectI> targets, CaptureSelection selection, Action<RectI?> finish)
    {
        _monitor = monitor;
        _desktop = desktop;
        _mode = mode;
        _background = background;
        _targets = targets;
        _selection = selection;
        _finish = finish;
        Focusable = true;
        ClipToBounds = true;
        Cursor = Cursors.Cross;
        _selection.Changed += InvalidateVisual;
    }

    public void Detach() => _selection.Changed -= InvalidateVisual;

    private double DipPerPixel => ActualWidth / _monitor.BoundsPx.Width;

    protected override void OnRender(DrawingContext dc)
    {
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        dc.DrawImage(_background, bounds);
        var picked = _selection.Bounds;
        if (picked.IsEmpty || DipPerPixel <= 0)
        {
            dc.DrawRectangle(Palette.DimBrush, null, bounds);
            DrawLabel(dc, new Point(16, 16), _mode == CaptureMode.Window ? "点选窗口 · Esc 取消" : "拖动框选 · Esc 取消");
            return;
        }

        double scale = DipPerPixel;
        var local = picked.Offset(-_monitor.BoundsPx.X, -_monitor.BoundsPx.Y);
        var selection = new Rect(local.X * scale, local.Y * scale, local.Width * scale, local.Height * scale);
        var dim = new CombinedGeometry(GeometryCombineMode.Exclude,
            new RectangleGeometry(bounds), new RectangleGeometry(selection));
        dc.DrawGeometry(Palette.DimBrush, null, dim);
        dc.DrawRectangle(null, new Pen(Palette.AccentSoftBrush, 1.5), selection);
        if (!selection.IntersectsWith(bounds)) return;

        if (_mode == CaptureMode.Region && !_dragging)
        {
            foreach (var x in new[] { selection.Left, selection.Right })
            foreach (var y in new[] { selection.Top, selection.Bottom })
                dc.DrawRectangle(Palette.WhiteBrush, new Pen(Palette.AccentBrush, 1), new Rect(x - 3, y - 3, 6, 6));
        }

        string size = $"{picked.Width} × {picked.Height}";
        string text = _mode == CaptureMode.Region && !_dragging ? size + " · 回车确认" : size;
        DrawLabel(dc, new Point(Math.Max(8, selection.Left), Math.Max(8, selection.Top - 28)), text);
    }

    private void DrawLabel(DrawingContext dc, Point origin, string text)
    {
        var label = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface("Microsoft YaHei UI"), 13, Palette.WhiteBrush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        var background = new SolidColorBrush(Color.FromArgb(0xD0, 0x1F, 0x25, 0x2B));
        double x = Math.Clamp(origin.X, 0, Math.Max(0, ActualWidth - label.Width - 14));
        var rect = new Rect(x, origin.Y, label.Width + 14, label.Height + 8);
        dc.DrawRoundedRectangle(background, null, rect, 5, 5);
        dc.DrawText(label, new Point(x + 7, origin.Y + 4));
    }

    private static PointF CursorPosition()
    {
        NativeMethods.GetCursorPos(out var point);
        return new PointF(point.X, point.Y);
    }

    private RectI TargetAt(PointF point) =>
        _targets.FirstOrDefault(rect => rect.Contains((int)point.X, (int)point.Y));

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        Focus();
        if (_mode == CaptureMode.Window) return;
        _start = CursorPosition();
        _initial = _selection.Bounds;
        double edge = 7 / Math.Max(0.25, DipPerPixel);
        _adjusting = !_initial.IsEmpty && _initial.ToRectF().Inflate((float)edge).Contains(_start);
        if (_adjusting && e.ClickCount == 2)
        {
            ConfirmRegion();
            return;
        }

        _horizontalEdge = Math.Abs(_start.X - _initial.X) <= edge ? -1 : Math.Abs(_start.X - _initial.Right) <= edge ? 1 : 0;
        _verticalEdge = Math.Abs(_start.Y - _initial.Y) <= edge ? -1 : Math.Abs(_start.Y - _initial.Bottom) <= edge ? 1 : 0;
        _dragging = CaptureMouse();
        if (!_adjusting) _selection.Set(default);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var point = CursorPosition();
        if (_mode == CaptureMode.Window) _selection.Set(TargetAt(point));
        else if (_dragging) UpdateRegion(point);
    }

    private void UpdateRegion(PointF point)
    {
        if (!_adjusting)
        {
            _selection.Set(RectI.FromRectFRound(RectF.FromPoints(_start, point)).Intersect(_desktop));
            return;
        }

        int dx = (int)(point.X - _start.X), dy = (int)(point.Y - _start.Y);
        if (_horizontalEdge == 0 && _verticalEdge == 0)
        {
            int x = Math.Clamp(_initial.X + dx, _desktop.X, _desktop.Right - _initial.Width);
            int y = Math.Clamp(_initial.Y + dy, _desktop.Y, _desktop.Bottom - _initial.Height);
            _selection.Set(new RectI(x, y, _initial.Width, _initial.Height));
            return;
        }

        var resized = RectI.FromEdges(
            _horizontalEdge < 0 ? Math.Clamp(_initial.X + dx, _desktop.X, _initial.Right - 4) : _initial.X,
            _verticalEdge < 0 ? Math.Clamp(_initial.Y + dy, _desktop.Y, _initial.Bottom - 4) : _initial.Y,
            _horizontalEdge > 0 ? Math.Clamp(_initial.Right + dx, _initial.X + 4, _desktop.Right) : _initial.Right,
            _verticalEdge > 0 ? Math.Clamp(_initial.Bottom + dy, _initial.Y + 4, _desktop.Bottom) : _initial.Bottom);
        _selection.Set(resized);
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        if (_mode == CaptureMode.Window)
        {
            var target = TargetAt(CursorPosition());
            if (!target.IsEmpty) _finish(target);
            return;
        }

        if (!_dragging) return;
        UpdateRegion(CursorPosition());
        _dragging = false;
        ReleaseMouseCapture();
        if (_selection.Bounds.Width < 4 || _selection.Bounds.Height < 4) _selection.Set(default);
        InvalidateVisual();
    }

    protected override void OnLostMouseCapture(MouseEventArgs e)
    {
        if (!_dragging) return;
        _dragging = false;
        _selection.Set(_initial);
    }

    protected override void OnMouseRightButtonUp(MouseButtonEventArgs e) => _finish(null);

    public void ConfirmRegion()
    {
        var bounds = _selection.Bounds;
        if (!_dragging && bounds.Width >= 4 && bounds.Height >= 4) _finish(bounds);
    }
}
