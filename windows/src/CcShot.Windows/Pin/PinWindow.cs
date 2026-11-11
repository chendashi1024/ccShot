using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CcShot.Core.Capture;
using CcShot.Core.Imaging;
using CcShot.Windows.Rendering;
using CcShot.Windows.Theme;

namespace CcShot.Windows.Pin;

/// <summary>
/// Pins the current result on top of other windows. Dragging moves it, the wheel zooms, Esc closes it,
/// and the right-click menu offers copy and save without leaving the pin.
/// </summary>
internal sealed class PinWindow : Window
{
    private readonly PixelImage _image;
    private readonly Image _view;
    private double _zoom = 1.0;

    public PinWindow(PixelImage image, MonitorInfo monitor)
    {
        _image = image;
        double scale = monitor.EffectiveScale <= 0 ? 1.0 : monitor.EffectiveScale;

        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        Title = "ccShot 钉图";
        Cursor = Cursors.SizeAll;

        _view = new Image
        {
            Source = BitmapInterop.ToBitmapSource(image),
            Stretch = Stretch.Fill,
            SnapsToDevicePixels = true,
        };
        RenderOptions.SetBitmapScalingMode(_view, BitmapScalingMode.HighQuality);

        var frame = new Border
        {
            BorderBrush = Palette.AccentBrush,
            BorderThickness = new Thickness(1),
            Background = Brushes.Black,
            Child = _view,
        };
        Content = frame;

        Width = Math.Max(40, image.Width / scale);
        Height = Math.Max(30, image.Height / scale);

        MouseLeftButtonDown += (_, e) =>
        {
            if (e.ButtonState == MouseButtonState.Pressed)
            {
                try { DragMove(); } catch (InvalidOperationException) { /* drag cancelled */ }
            }
        };
        MouseWheel += (_, e) =>
        {
            double factor = e.Delta > 0 ? 1.1 : 1 / 1.1;
            _zoom = Math.Clamp(_zoom * factor, 0.2, 4.0);
            Width = Math.Max(40, image.Width / scale * _zoom);
            Height = Math.Max(30, image.Height / scale * _zoom);
        };
        MouseRightButtonUp += (_, _) => ShowMenu();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) Close();
        };
    }

    private void ShowMenu()
    {
        var menu = new ContextMenu();
        var copy = new MenuItem { Header = "复制图片" };
        copy.Click += (_, _) =>
        {
            try { Clipboard.SetImage(BitmapInterop.ToBitmapSource(_image)); }
            catch (Exception) { /* clipboard busy: keep the pin, user can retry */ }
        };
        var save = new MenuItem { Header = "保存…" };
        save.Click += (_, _) =>
        {
            var dialog = new Microsoft.Win32.SaveFileDialog
            {
                Filter = "PNG 图片|*.png|JPG 图片|*.jpg",
                FileName = $"ccShot-{DateTime.Now:yyyyMMdd-HHmmss}.png",
            };
            if (dialog.ShowDialog(this) == true) BitmapInterop.Save(_image, dialog.FileName);
        };
        var close = new MenuItem { Header = "关闭" };
        close.Click += (_, _) => Close();
        menu.Items.Add(copy);
        menu.Items.Add(save);
        menu.Items.Add(new Separator());
        menu.Items.Add(close);
        menu.IsOpen = true;
    }
}
