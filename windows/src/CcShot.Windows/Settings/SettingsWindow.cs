using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using CcShot.Core.Settings;
using CcShot.Windows.Interop;
using CcShot.Windows.Theme;

namespace CcShot.Windows.Settings;

/// <summary>
/// Two settings only, as the product scope requires: the capture shortcut and where files go.
/// Conflicts and invalid folders are explained next to the field instead of in a dialog.
/// </summary>
internal sealed class SettingsWindow : Window
{
    private readonly AppSettings _settings;
    private readonly GlobalHotkey _hotkey;
    private readonly Action<HotkeyBinding> _apply;
    private readonly TextBox _hotkeyBox;
    private readonly TextBox _directoryBox;
    private readonly TextBlock _hotkeyError;
    private readonly TextBlock _directoryError;

    public SettingsWindow(AppSettings settings, GlobalHotkey hotkey, Action<HotkeyBinding> apply)
    {
        _settings = settings;
        _hotkey = hotkey;
        _apply = apply;

        Title = "ccShot 设置";
        Width = 520;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Palette.SurfaceBrush;
        FontFamily = new FontFamily("Microsoft YaHei UI");
        FontSize = 13;

        _hotkeyBox = new TextBox { Text = settings.CaptureHotkey, Padding = new Thickness(6, 4, 6, 4), Margin = new Thickness(0, 4, 0, 2) };
        _hotkeyError = new TextBlock { Foreground = Palette.ErrorBrush, FontSize = 12, TextWrapping = TextWrapping.Wrap };
        _directoryBox = new TextBox { Text = settings.ResolvedSaveDirectory, Padding = new Thickness(6, 4, 6, 4), Margin = new Thickness(0, 4, 0, 2) };
        _directoryError = new TextBlock { Foreground = Palette.ErrorBrush, FontSize = 12, TextWrapping = TextWrapping.Wrap };

        var browse = new Button { Content = "选择…", Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(6, 4, 0, 0) };
        browse.Click += (_, _) => BrowseDirectory();

        var directoryRow = new Grid();
        directoryRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        directoryRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        directoryRow.Children.Add(_directoryBox);
        Grid.SetColumn(_directoryBox, 0);
        directoryRow.Children.Add(browse);
        Grid.SetColumn(browse, 1);

        var save = new Button { Content = "保存", Padding = new Thickness(18, 5, 18, 5), IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        save.Click += (_, _) => Commit();
        var cancel = new Button { Content = "取消", Padding = new Thickness(18, 5, 18, 5), IsCancel = true };
        cancel.Click += (_, _) => Close();

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
        buttons.Children.Add(save);
        buttons.Children.Add(cancel);

        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(Header("截图快捷键"));
        panel.Children.Add(_hotkeyBox);
        panel.Children.Add(new TextBlock { Text = "例如 Ctrl+Alt+X、F1、Shift+PrintScreen。F1 需按 Fn 或开启标准功能键。", FontSize = 12, Foreground = Palette.InkSoftBrush });
        panel.Children.Add(_hotkeyError);
        panel.Children.Add(Header("默认保存位置", top: 14));
        panel.Children.Add(directoryRow);
        panel.Children.Add(_directoryError);
        panel.Children.Add(buttons);
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };

        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) Close();
        };
    }

    private static TextBlock Header(string text, double top = 0) => new()
    {
        Text = text,
        FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, top, 0, 0),
        Foreground = Palette.InkBrush,
    };

    private void BrowseDirectory()
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { Title = "选择截图保存位置" };
        if (Directory.Exists(_directoryBox.Text)) dialog.InitialDirectory = _directoryBox.Text;
        if (dialog.ShowDialog(this) == true) _directoryBox.Text = dialog.FolderName;
    }

    private void Commit()
    {
        bool valid = true;
        _hotkeyError.Text = string.Empty;
        _directoryError.Text = string.Empty;

        if (!HotkeyParser.TryParse(_hotkeyBox.Text, out var binding, out string parseError))
        {
            _hotkeyError.Text = parseError;
            valid = false;
        }
        string directory = _directoryBox.Text.Trim();
        if (directory.Length == 0)
        {
            _directoryError.Text = "请填写保存位置";
            valid = false;
        }
        else
        {
            try
            {
                Directory.CreateDirectory(directory);
                var probe = Path.Combine(directory, $".ccshot-write-test-{Guid.NewGuid():N}");
                using var stream = new FileStream(probe, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1, FileOptions.DeleteOnClose);
            }
            catch (Exception ex)
            {
                _directoryError.Text = "这个位置不能写入：" + ex.Message;
                valid = false;
            }
        }

        if (!valid) return;
        var previousBinding = _hotkey.Current;
        if (!_hotkey.Register(binding))
        {
            _hotkeyError.Text = _hotkey.LastError;
            return;
        }

        string previousShortcut = _settings.CaptureHotkey;
        string? previousDirectory = _settings.SaveDirectory;
        try
        {
            _settings.CaptureHotkey = binding.ToString();
            _settings.SaveDirectory = directory;
            _settings.Save();
        }
        catch (Exception ex)
        {
            _settings.CaptureHotkey = previousShortcut;
            _settings.SaveDirectory = previousDirectory;
            if (previousBinding != null && previousBinding != binding) _hotkey.Register(previousBinding);
            else if (previousBinding == null) _hotkey.Unregister();
            _directoryError.Text = "无法保存设置：" + ex.Message;
            return;
        }
        _apply(binding);
        Close();
    }
}
