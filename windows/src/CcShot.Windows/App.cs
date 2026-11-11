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
        _tray.ExitRequested += (_, _) => ExitApplication();

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
        var window = new SettingsWindow(_settings, _ocr, _ => ApplyHotkey());
        window.ShowDialog();
    }

    private async Task CaptureCurrentScreenAsync()
    {
        var layout = MonitorService.Enumerate();
        NativeMethods.GetCursorPos(out var cursor);
        var monitor = layout.MonitorAt(new PointF(cursor.X, cursor.Y)) ?? layout.Primary;
        await CaptureAsync(layout, monitor.BoundsPx);
    }

    private async Task StartCaptureAsync(CaptureMode mode)
    {
        if (_capturing) return;
        var layout = MonitorService.Enumerate();
        RectI? picked = await PickAsync(layout, mode);
        if (picked == null) return;
        await CaptureAsync(layout, picked.Value);
    }

    /// <summary>Shows the selection overlay on every monitor and waits for a rectangle.</summary>
    private Task<RectI?> PickAsync(MonitorLayout layout, CaptureMode mode)
    {
        var completion = new TaskCompletionSource<RectI?>();
        var windows = new List<CaptureOverlayWindow>();

        void CloseAll()
        {
            foreach (var window in windows)
            {
                try { window.Close(); }
                catch (InvalidOperationException) { /* already closed */ }
            }
        }

        foreach (var monitor in layout.Monitors)
            windows.Add(new CaptureOverlayWindow(monitor, mode, completion, CloseAll));

        foreach (var window in windows) window.Show();
        if (windows.Count > 0)
        {
            windows[0].Activate();
            windows[0].Focus();
        }

        return completion.Task;
    }

    private async Task CaptureAsync(MonitorLayout layout, RectI selection)
    {
        if (_capturing) return;
        _capturing = true;
        try
        {
            var clamped = selection.Intersect(layout.VirtualDesktopPx);
            if (clamped.Width < 4 || clamped.Height < 4) return;

            PixelImage desktop;
            try
            {
                desktop = await Task.Run(() => ScreenCaptureService.Capture(layout.VirtualDesktopPx));
            }
            catch (Exception ex)
            {
                _tray?.Notify("截图失败", ex.Message, System.Windows.Forms.ToolTipIcon.Error);
                return;
            }

            var localRect = clamped.Offset(-layout.VirtualDesktopPx.X, -layout.VirtualDesktopPx.Y);
            var image = desktop.Crop(localRect);
            if (image.IsEmpty) return;

            var center = new PointF(clamped.X + clamped.Width / 2f, clamped.Y + clamped.Height / 2f);
            var monitor = layout.MonitorAt(center) ?? layout.NearestMonitor(center);
            var session = new CaptureSession(image);
            var editor = new EditorWindow(session, monitor, clamped, _settings, _ocr);
            editor.Show();
            editor.Activate();
        }
        finally
        {
            _capturing = false;
        }
    }

    private void ExitApplication()
    {
        _hotkey?.Dispose();
        _tray?.Dispose();
        _ocr.Dispose();
        Shutdown();
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
