using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using CcShot.Core.Settings;

namespace CcShot.Windows.Shell;

/// <summary>Tray icon and its menu. WinForms' NotifyIcon is used only for this shell piece.</summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _captureItem;

    public TrayIcon()
    {
        var menu = new ContextMenuStrip();
        _captureItem = new ToolStripMenuItem("区域截图", null, (_, _) => CaptureRequested?.Invoke(this, EventArgs.Empty));
        menu.Items.Add(_captureItem);
        menu.Items.Add(new ToolStripMenuItem("当前屏幕", null, (_, _) => ScreenCaptureRequested?.Invoke(this, EventArgs.Empty)));
        menu.Items.Add(new ToolStripMenuItem("选择窗口", null, (_, _) => WindowCaptureRequested?.Invoke(this, EventArgs.Empty)));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("设置…", null, (_, _) => SettingsRequested?.Invoke(this, EventArgs.Empty)));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("退出", null, (_, _) => ExitRequested?.Invoke(this, EventArgs.Empty)));

        _icon = new NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "ccShot · 截图与选字",
            Visible = true,
            ContextMenuStrip = menu,
        };
        _icon.DoubleClick += (_, _) => CaptureRequested?.Invoke(this, EventArgs.Empty);
    }

    public event EventHandler? CaptureRequested;
    public event EventHandler? ScreenCaptureRequested;
    public event EventHandler? WindowCaptureRequested;
    public event EventHandler? SettingsRequested;
    public event EventHandler? ExitRequested;

    private static Icon LoadIcon()
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "ccshot.ico");
            if (File.Exists(path)) return new Icon(path);
        }
        catch (Exception)
        {
            // Fall back to the stock icon so the tray entry always exists.
        }

        return SystemIcons.Application;
    }

    public void Update(HotkeyBinding? binding, string? note = null)
    {
        string shortcut = binding?.ToString() ?? "未注册";
        _captureItem.Text = $"区域截图（{shortcut}）";
        _icon.Text = note == null ? $"ccShot · 截图与选字（{shortcut}）" : $"ccShot · {note}";
        if (_icon.Text.Length > 63) _icon.Text = _icon.Text[..63];
    }

    public void Notify(string title, string message, ToolTipIcon icon = ToolTipIcon.Info)
    {
        try
        {
            _icon.ShowBalloonTip(3000, title, message, icon);
        }
        catch (Exception)
        {
            // Balloon tips are cosmetic; never let them break the capture flow.
        }
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
