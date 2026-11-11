using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using CcShot.Core.Capture;
using CcShot.Core.Geometry;
using CcShot.Core.Imaging;
using CcShot.Core.Ocr.Selection;
using CcShot.Core.Session;
using CcShot.Core.Settings;
using CcShot.Windows.Capture;
using CcShot.Windows.Editor;
using CcShot.Windows.Interop;
using CcShot.Windows.Ocr;
using CcShot.Windows.Rendering;
using CcShot.Windows.Theme;

namespace CcShot.Windows.Pin;

internal sealed class PinWindow : Window
{
    private readonly CaptureSession _document;
    private readonly AppSettings _settings;
    private readonly OcrService _ocr;
    private readonly Border _frame;
    private PixelImage _image = PixelImage.Empty;
    private EditorCanvas? _canvas;
    private CancellationTokenSource? _recognition;
    private string? _allText;
    private string? _recognitionError;
    private double _zoom;
    private bool _closed;

    internal bool HasRecognizedText => !string.IsNullOrEmpty(_allText);
    internal EditorCanvas? SelectionSurface => _canvas;

    public PinWindow(CaptureSession document, MonitorInfo monitor, AppSettings settings, OcrService ocr)
    {
        _document = document;
        _settings = settings;
        _ocr = ocr;
        _zoom = Math.Min(1.0 / monitor.EffectiveScale,
            Math.Min((monitor.BoundsPx.Width / monitor.EffectiveScale - 24) / document.Image.Width,
                (monitor.BoundsPx.Height / monitor.EffectiveScale - 24) / document.Image.Height));

        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        Title = "ccShot 钉图";

        _frame = new Border { BorderBrush = Palette.AccentBrush, BorderThickness = new Thickness(1) };
        Content = _frame;
        SourceInitialized += (_, _) =>
        {
            var bounds = monitor.BoundsPx;
            int width = (int)Math.Ceiling(Width * monitor.EffectiveScale);
            int height = (int)Math.Ceiling(Height * monitor.EffectiveScale);
            NativeMethods.SetWindowPos(new WindowInteropHelper(this).Handle, IntPtr.Zero,
                bounds.X + (bounds.Width - width) / 2, bounds.Y + (bounds.Height - height) / 2, width, height,
                NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
        };
        Loaded += (_, _) => Rebuild();
        Closed += (_, _) =>
        {
            _closed = true;
            _recognition?.Cancel();
            _canvas?.Detach();
        };
        MouseWheel += (_, e) =>
        {
            if (_canvas == null || _canvas.IsMouseCaptured) return;
            _zoom = Math.Clamp(_zoom * (e.Delta > 0 ? 1.1 : 1 / 1.1), 0.05, 4.0);
            ResizeImage();
            e.Handled = true;
        };
        MouseRightButtonUp += (_, _) => ShowMenu();
        PreviewKeyDown += HandleKey;
        ResizeImage();
    }

    private void ResizeImage()
    {
        if (_canvas != null)
        {
            _canvas.DipPerPixel = _zoom;
            _canvas.InvalidateVisual();
        }
        Width = Math.Max(1, _document.Image.Width * _zoom) + 2;
        Height = Math.Max(1, _document.Image.Height * _zoom) + 2;
    }

    private async void Rebuild()
    {
        _recognition?.Cancel();
        _canvas?.Detach();
        _allText = null;
        _recognitionError = null;
        _image = ImageCompositor.Compose(_document.Image, _document.Annotations);
        var canvas = new EditorCanvas(new CaptureSession(_image), readOnly: true) { DipPerPixel = _zoom };
        canvas.PanRequested += () =>
        {
            if (Mouse.LeftButton == MouseButtonState.Pressed)
            {
                try { DragMove(); }
                catch (InvalidOperationException) { }
            }
        };
        _canvas = canvas;
        _frame.Child = canvas;
        ResizeImage();

        using var request = new CancellationTokenSource();
        _recognition = request;
        try
        {
            var (page, error) = await _ocr.RecognizeAsync(_image, _settings, request.Token);
            if (request.IsCancellationRequested) return;
            if (page == null)
            {
                _recognitionError = error;
                return;
            }

            var (visible, _) = OcrPrivacyFilter.RemoveGlyphsUnder(page, _document.ObscuredTextRects);
            _allText = visible.ToPlainText();
            canvas.SetTextModel(new TextSelectionModel(visible));
        }
        finally
        {
            if (ReferenceEquals(_recognition, request)) _recognition = null;
        }
    }

    private void HandleKey(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            if (_canvas?.HasTextSelection == true) _canvas.ClearTextSelection();
            else Close();
        }
        else if (e.Key == Key.C && Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) CopyText(all: true);
            else if (_canvas?.HasTextSelection == true) CopyText(all: false);
            else RunOutput(() => Clipboard.SetImage(BitmapInterop.ToBitmapSource(_image)));
        }
        else return;
        e.Handled = true;
    }

    private void CopyText(bool all)
    {
        string? text = all ? _allText : _canvas?.SelectedText;
        if (string.IsNullOrEmpty(text))
        {
            string message = _recognitionError ?? (_recognition != null ? "正在识别文字，请稍候。" : "没有可复制的文字。");
            MessageBox.Show(this, message, "ccShot");
            return;
        }
        RunOutput(() => Clipboard.SetText(text));
    }

    internal void EditPin()
    {
        var layout = MonitorService.Enumerate();
        NativeMethods.GetWindowRect(new WindowInteropHelper(this).Handle, out var current);
        var monitor = layout.MonitorAt(new PointF(current.Left, current.Top)) ?? layout.Primary;
        var bounds = new RectI(current.Left, current.Top, _image.Width, _image.Height);
        var editor = new EditorWindow(_document, monitor, bounds, _settings, _ocr);
        IsEnabled = false;
        Topmost = false;
        editor.Closed += (_, _) =>
        {
            if (_closed) return;
            Topmost = true;
            Rebuild();
            IsEnabled = true;
            Activate();
        };
        editor.Show();
        editor.Activate();
    }

    private void ShowMenu()
    {
        var menu = new ContextMenu { PlacementTarget = _frame };
        void Add(string label, Action action)
        {
            var item = new MenuItem { Header = label };
            item.Click += (_, _) => action();
            menu.Items.Add(item);
        }
        Add("继续编辑", EditPin);
        Add("复制全部文字", () => CopyText(all: true));
        Add("复制图片", () => RunOutput(() => Clipboard.SetImage(BitmapInterop.ToBitmapSource(_image))));
        Add("保存…", Save);
        menu.Items.Add(new Separator());
        Add("关闭", Close);
        menu.IsOpen = true;
    }

    private void Save()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Filter = "PNG 图片|*.png|JPG 图片|*.jpg",
            FileName = $"ccShot-{DateTime.Now:yyyyMMdd-HHmmss}",
            InitialDirectory = _settings.ResolvedSaveDirectory,
        };
        if (dialog.ShowDialog(this) == true) RunOutput(() => BitmapInterop.Save(_image, dialog.FileName));
    }

    private void RunOutput(Action action)
    {
        try { action(); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "输出失败"); }
    }
}
