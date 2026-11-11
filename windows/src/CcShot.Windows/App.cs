using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using CcShot.Core.Capture;
using CcShot.Core.Geometry;
using CcShot.Core.Imaging;
using CcShot.Core.Session;
using CcShot.Core.Settings;
using CcShot.Windows.Capture;
using CcShot.Windows.Editor;
using CcShot.Windows.Interop;
using CcShot.Windows.Ocr;
using CcShot.Windows.Pin;
using CcShot.Windows.Rendering;
using Microsoft.Win32;
using CcShot.Windows.Settings;
using CcShot.Windows.Shell;

namespace CcShot.Windows;

/// <summary>
/// Application shell: tray icon, global shortcut and the capture pipeline. The screenshot is taken
/// before the selection overlay is shown, so the overlay never appears in the captured pixels.
/// </summary>
internal sealed class App : Application
{
    private Mutex? _instanceMutex;
    private TrayIcon? _tray;
    private GlobalHotkey? _hotkey;
    private AppSettings _settings = new();
    private readonly OcrService _ocr = new();
    private bool _capturing;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        _instanceMutex = new Mutex(true, "ccShot.SingleInstance.v1", out bool created);
        if (!created)
        {
            MessageBox.Show("ccShot 已经在运行，请从托盘图标使用。", "ccShot", MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        _settings = AppSettings.Load();
        _tray = new TrayIcon();
        _tray.CaptureRequested += (_, _) => _ = StartCaptureAsync(CaptureMode.Region);
        _tray.ScreenCaptureRequested += (_, _) => _ = CaptureCurrentScreenAsync();
        _tray.WindowCaptureRequested += (_, _) => _ = StartCaptureAsync(CaptureMode.Window);
        _tray.SettingsRequested += (_, _) => ShowSettings();
        _tray.ExitRequested += (_, _) => Shutdown();
        _tray.PinClipboardRequested += (_, _) => PinClipboard();

        _hotkey = new GlobalHotkey();
        _hotkey.Pressed += (_, _) => _ = StartCaptureAsync(CaptureMode.Region);
        ApplyHotkey(announce: true);

        // Warm the OCR engine up in the background so the first capture does not pay the load cost.
        Task.Run(() => _ocr.TryPrepare(_settings, out _));
    }

    private void ApplyHotkey(bool announce = false)
    {
        if (_hotkey == null || _tray == null) return;
        if (!_settings.TryGetBinding(out var binding, out string error))
        {
            _tray.Update(null, error);
            if (announce) _tray.Notify("快捷键不可用", error + " 请到设置里改一个。", System.Windows.Forms.ToolTipIcon.Warning);
            return;
        }

        if (!_hotkey.Register(binding))
        {
            _tray.Update(null, _hotkey.LastError);
            if (announce) _tray.Notify("快捷键被占用", _hotkey.LastError + " 可以右击托盘图标进设置换一个。", System.Windows.Forms.ToolTipIcon.Warning);
            return;
        }

        _tray.Update(binding);
        if (announce) _tray.Notify("ccShot 已就绪", $"按 {binding} 截图；右击托盘图标可以设置或退出。");
    }

    private void ShowSettings()
    {
        var window = new SettingsWindow(_settings, _hotkey!, binding => _tray!.Update(binding));
        window.ShowDialog();
    }

    private Task CaptureCurrentScreenAsync() => StartCaptureAsync(null);

    private async Task StartCaptureAsync(CaptureMode? mode)
    {
        if (_capturing) return;
        _capturing = true;
        try
        {
            var layout = MonitorService.Enumerate();
            var bounds = layout.VirtualDesktopPx;
            NativeMethods.GetCursorPos(out var cursor);
            var monitor = layout.MonitorAt(new PointF(cursor.X, cursor.Y)) ?? layout.Primary;
            var targets = mode == CaptureMode.Window ? ScreenCaptureService.SnapshotWindowBounds(bounds) : Array.Empty<RectI>();
            var snapshotBounds = mode.HasValue ? bounds : monitor.BoundsPx;
            var desktop = await Task.Run(() => ScreenCaptureService.Capture(snapshotBounds));
            if (!layout.Monitors.SequenceEqual(MonitorService.Enumerate().Monitors)) return;

            RectI? picked = mode.HasValue
                ? await PickAsync(layout, mode.Value, desktop, targets, monitor)
                : monitor.BoundsPx;
            if (picked is not RectI selected || !layout.Monitors.SequenceEqual(MonitorService.Enumerate().Monitors)) return;
            var clamped = selected.Intersect(snapshotBounds);
            if (clamped.Width < 4 || clamped.Height < 4) return;

            var image = desktop.Crop(clamped.Offset(-snapshotBounds.X, -snapshotBounds.Y));
            var center = clamped.ToRectF().Center;
            OpenEditor(new CaptureSession(image), layout.MonitorAt(center) ?? layout.NearestMonitor(center), clamped);
        }
        catch (Exception ex)
        {
            _tray?.Notify("截图失败", ex.Message, System.Windows.Forms.ToolTipIcon.Error);
        }
        finally
        {
            _capturing = false;
        }
    }

    private async Task<RectI?> PickAsync(MonitorLayout layout, CaptureMode mode, PixelImage snapshot,
        IReadOnlyList<RectI> targets, MonitorInfo focusedMonitor)
    {
        var completion = new TaskCompletionSource<RectI?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var selection = new CaptureSelection();
        var windows = new List<CaptureOverlayWindow>();

        void Finish(RectI? result) => completion.TrySetResult(result);
        void CancelForDisplayChange(object? sender, EventArgs e) => Finish(null);

        SystemEvents.DisplaySettingsChanged += CancelForDisplayChange;
        try
        {
            foreach (var monitor in layout.Monitors)
            {
                var local = monitor.BoundsPx.Offset(-layout.VirtualDesktopPx.X, -layout.VirtualDesktopPx.Y);
                var background = BitmapInterop.ToBitmapSource(snapshot.Crop(local));
                var overlay = new CaptureOverlayWindow(monitor, layout.VirtualDesktopPx, mode,
                    background, targets, selection, Finish);
                windows.Add(overlay);
            }

            foreach (var window in windows) window.Show();
            int focusedIndex = layout.Monitors.ToList().IndexOf(focusedMonitor);
            windows[Math.Max(0, focusedIndex)].Activate();
            return await completion.Task;
        }
        finally
        {
            SystemEvents.DisplaySettingsChanged -= CancelForDisplayChange;
            foreach (var window in windows)
                if (window.IsVisible) window.Close();
        }
    }

    private void OpenEditor(CaptureSession session, MonitorInfo monitor, RectI bounds)
    {
        var editor = new EditorWindow(session, monitor, bounds, _settings, _ocr);
        editor.Show();
        editor.Activate();
    }

    private void PinClipboard()
    {
        try
        {
            var bitmap = Clipboard.GetImage();
            if (bitmap == null)
            {
                _tray?.Notify("剪贴板里没有图片", "先复制一张图片，再选择钉住剪贴板。");
                return;
            }

            var layout = MonitorService.Enumerate();
            NativeMethods.GetCursorPos(out var cursor);
            var monitor = layout.MonitorAt(new PointF(cursor.X, cursor.Y)) ?? layout.Primary;
            var session = new CaptureSession(BitmapInterop.ToPixelImage(bitmap));
            new PinWindow(session, monitor, _settings, _ocr).Show();
        }
        catch (Exception ex)
        {
            _tray?.Notify("钉住剪贴板失败", ex.Message, System.Windows.Forms.ToolTipIcon.Error);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkey?.Dispose();
        _tray?.Dispose();
        _ocr.Dispose();
        _instanceMutex?.Dispose();
        base.OnExit(e);
    }
}
