using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CcShot.Core.Annotate;
using CcShot.Core.Capture;
using CcShot.Core.Geometry;
using CcShot.Core.Imaging;
using CcShot.Core.Ocr.Selection;
using CcShot.Core.Session;
using CcShot.Core.Settings;
using CcShot.Windows.Interop;
using CcShot.Windows.Ocr;
using CcShot.Windows.Rendering;
using CcShot.Windows.Theme;

namespace CcShot.Windows.Editor;

/// <summary>
/// In-place editor for one capture: the window sits exactly on the captured screen rectangle, with the
/// toolbar attached to the image edge. Text selection, annotation tools and the three outputs live here.
/// </summary>
internal sealed class EditorWindow : Window
{
    private const double ToolbarHeightDip = 74;

    private readonly CaptureSession _session;
    private readonly AppSettings _settings;
    private readonly OcrService _ocr;
    private readonly MonitorInfo _monitor;
    private readonly RectI _screenRect;
    private readonly EditorCanvas _canvas;
    private readonly TextBox _textEditor;
    private readonly TextBlock _status;
    private readonly Border _statusPanel;
    private readonly StackPanel _toolRow;
    private readonly StackPanel _actionRow;
    private readonly StackPanel _styleRow;
    private readonly Slider _thickness;
    private CancellationTokenSource? _ocrCts;
    private readonly double _scale;
    private bool _ocrRunning;

    public EditorWindow(CaptureSession session, MonitorInfo monitor, RectI screenRect, AppSettings settings, OcrService ocr)
    {
        _session = session;
        _settings = settings;
        _ocr = ocr;
        _monitor = monitor;
        _screenRect = screenRect;
        _scale = monitor.EffectiveScale;

        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        SnapsToDevicePixels = true;
        UseLayoutRounding = true;
        Title = "ccShot";

        double imageWidthDip = session.Image.Width / _scale;
        double imageHeightDip = session.Image.Height / _scale;

        _canvas = new EditorCanvas(session) { DipPerPixel = 1 / _scale };
        _canvas.DocumentChanged += (_, _) => { UpdateButtons(); RefreshSafeText(); };
        _canvas.SelectionChanged += (_, _) => UpdateButtons();
        _canvas.ToolChanged += (_, _) => UpdateButtons();
        _canvas.TextEditRequested += (_, point) => ShowTextEditor(point);

        _textEditor = new TextBox
        {
            Visibility = Visibility.Collapsed,
            AcceptsReturn = true,
            FontFamily = new FontFamily("Microsoft YaHei UI"),
            FontSize = 14,
            MinWidth = 80,
            Padding = new Thickness(2),
            Background = Palette.SurfaceBrush,
            BorderBrush = Palette.AccentBrush,
            BorderThickness = new Thickness(1),
        };
        _textEditor.KeyDown += TextEditorKeyDown;
        _textEditor.LostFocus += (_, _) => CommitTextEditor();

        _status = new TextBlock
        {
            Foreground = Palette.WhiteBrush,
            FontSize = 12,
            FontFamily = new FontFamily("Microsoft YaHei UI"),
            TextWrapping = TextWrapping.NoWrap,
        };
        _statusPanel = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0xD0, 0x1F, 0x25, 0x2B)),
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(8, 4, 8, 4),
            Margin = new Thickness(10),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Bottom,
            Child = _status,
            Visibility = Visibility.Collapsed,
        };

        _toolRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 4) };
        _actionRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 4) };
        _styleRow = new StackPanel { Orientation = Orientation.Horizontal };
        _thickness = new Slider { Minimum = 1, Maximum = 12, Value = 3, Width = 80, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 8, 0) };
        _thickness.ValueChanged += (_, e) =>
        {
            var style = _canvas.ActiveStyle with { Thickness = (float)e.NewValue };
            _canvas.SetStyle(style);
        };

        BuildToolRows();

        var toolbar = new Border
        {
            Background = Palette.PanelBrush,
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x30, 0, 0, 0)),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Padding = new Thickness(8, 6, 8, 6),
            Child = new StackPanel { Children = { _toolRow, _actionRow, _styleRow } },
        };

        bool toolbarBelow = screenRect.Bottom + ToolbarHeightDip * _scale < monitor.BoundsPx.Bottom;
        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var canvasHost = new Grid();
        canvasHost.Children.Add(_canvas);
        canvasHost.Children.Add(_textEditor);
        canvasHost.Children.Add(_statusPanel);

        if (toolbarBelow)
        {
            Grid.SetRow(canvasHost, 0);
            Grid.SetRow(toolbar, 1);
        }
        else
        {
            Grid.SetRow(toolbar, 0);
            Grid.SetRow(canvasHost, 1);
        }

        grid.Children.Add(toolbar);
        grid.Children.Add(canvasHost);
        Content = grid;

        Width = Math.Max(320, imageWidthDip);
        Height = Math.Max(200, imageHeightDip + ToolbarHeightDip);

        SourceInitialized += (_, _) => PlaceWindow(toolbarBelow);
        Loaded += (_, _) =>
        {
            _canvas.Focus();
            PlaceWindow(toolbarBelow);
            RunOcr();
        };
        PreviewKeyDown += OnPreviewKeyDown;
        Closed += (_, _) => _ocrCts?.Cancel();
    }

    private void PlaceWindow(bool toolbarBelow)
    {
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero) return;
        int toolbarPx = (int)Math.Round(ToolbarHeightDip * _scale);
        int width = _session.Image.Width;
        int height = _session.Image.Height + toolbarPx;
        int x = _screenRect.X;
        int y = toolbarBelow ? _screenRect.Y : _screenRect.Y - toolbarPx;
        NativeMethods.SetWindowPos(handle, IntPtr.Zero, x, y, width, height,
            NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);
    }

    private Button MakeButton(string text, Action onClick, string tooltip, double minWidth = 0)
    {
        var button = new Button
        {
            Content = text,
            Margin = new Thickness(0, 0, 4, 0),
            Padding = new Thickness(8, 4, 8, 4),
            MinWidth = minWidth,
            FontFamily = new FontFamily("Microsoft YaHei UI"),
            FontSize = 12,
            ToolTip = tooltip,
            Background = Palette.SurfaceBrush,
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x28, 0, 0, 0)),
            Cursor = Cursors.Hand,
        };
        button.Click += (_, _) => onClick();
        return button;
    }

    private ToggleButton MakeToolButton(string text, EditorTool tool, string tooltip)
    {
        var button = new ToggleButton
        {
            Content = text,
            Tag = tool,
            Margin = new Thickness(0, 0, 4, 0),
            Padding = new Thickness(8, 4, 8, 4),
            FontFamily = new FontFamily("Microsoft YaHei UI"),
            FontSize = 12,
            ToolTip = tooltip,
            Background = Palette.SurfaceBrush,
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x28, 0, 0, 0)),
            Cursor = Cursors.Hand,
        };
        button.Checked += (_, _) =>
        {
            foreach (var other in _toolRow.Children.OfType<ToggleButton>())
                if (!ReferenceEquals(other, button)) other.IsChecked = false;
            _canvas.Tool = tool;
            _canvas.Focus();
        };
        return button;
    }

    private void BuildToolRows()
    {
        var select = MakeToolButton("选择", EditorTool.Select, "选择 / 拖选文字（V）");
        select.IsChecked = true;
        _toolRow.Children.Add(select);
        _toolRow.Children.Add(MakeToolButton("箭头", EditorTool.Arrow, "箭头（A）"));
        _toolRow.Children.Add(MakeToolButton("方框", EditorTool.Rect, "画框（R）"));
        _toolRow.Children.Add(MakeToolButton("椭圆", EditorTool.Ellipse, "椭圆（E）"));
        _toolRow.Children.Add(MakeToolButton("文字", EditorTool.Text, "文字（T）"));
        _toolRow.Children.Add(MakeToolButton("画笔", EditorTool.Pen, "画笔（P）"));
        _toolRow.Children.Add(MakeToolButton("遮挡", EditorTool.MaskRect, "实心遮挡（M），再点一次切换画笔遮挡"));
        _toolRow.Children.Add(MakeToolButton("高亮", EditorTool.Highlight, "高亮（H）"));
        _toolRow.Children.Add(MakeToolButton("序号", EditorTool.Number, "序号（N）"));

        _actionRow.Children.Add(MakeButton("撤销", () => _canvas.Undo(), "撤销（Ctrl+Z）"));
        _actionRow.Children.Add(MakeButton("重做", () => _canvas.Redo(), "重做（Ctrl+Y）"));
        _actionRow.Children.Add(new Border { Width = 8 });
        _actionRow.Children.Add(MakeButton("复制图片", CopyImage, "复制当前图片（没有文字选择时 Ctrl+C）"));
        _actionRow.Children.Add(MakeButton("复制文字", () => CopyText(false), "复制选中的文字（Ctrl+Shift+C 复制全部）"));
        _actionRow.Children.Add(MakeButton("保存", SaveImage, "保存 PNG/JPG（Ctrl+S）"));
        _actionRow.Children.Add(MakeButton("钉住", PinImage, "钉在屏幕最上层"));
        _actionRow.Children.Add(MakeButton("关闭", Close, "关闭（Esc）"));

        foreach (var color in Palette.AnnotationColors)
        {
            var swatch = new Button
            {
                Width = 18,
                Height = 18,
                Margin = new Thickness(0, 2, 4, 0),
                Background = new SolidColorBrush(color),
                BorderBrush = new SolidColorBrush(Color.FromArgb(0x40, 0, 0, 0)),
                BorderThickness = new Thickness(1),
                Cursor = Cursors.Hand,
                ToolTip = "颜色",
            };
            var captured = color;
            swatch.Click += (_, _) =>
            {
                var style = _canvas.ActiveStyle with { ColorArgb = Palette.ToArgb(captured) };
                _canvas.SetStyle(style);
            };
            _styleRow.Children.Add(swatch);
        }

        _styleRow.Children.Add(new Border { Width = 8 });
        _styleRow.Children.Add(new TextBlock { Text = "粗细", VerticalAlignment = VerticalAlignment.Center, FontSize = 12, Margin = new Thickness(0, 0, 4, 0) });
        _styleRow.Children.Add(_thickness);
        _styleRow.Children.Add(MakeButton("实心", () => SetMaskEffect(MaskEffect.Solid), "不透明覆盖：真正隐藏原文"));
        _styleRow.Children.Add(MakeButton("马赛克", () => SetMaskEffect(MaskEffect.Mosaic), "马赛克，不视为安全脱敏"));
        _styleRow.Children.Add(MakeButton("模糊", () => SetMaskEffect(MaskEffect.Blur), "模糊，不视为安全脱敏"));
    }

    private void SetMaskEffect(MaskEffect effect)
    {
        _canvas.SetMaskEffect(effect);
        ShowStatus(effect switch
        {
            MaskEffect.Solid => "实心遮挡：可用于隐藏原文",
            MaskEffect.Mosaic => "马赛克：查看效果会暴露轮廓，不作为安全脱敏",
            _ => "模糊：不作为安全脱敏",
        });
    }

    private void UpdateButtons()
    {
        foreach (var button in _toolRow.Children.OfType<ToggleButton>())
            button.IsChecked = button.Tag is EditorTool tool && tool == _canvas.Tool;
        _thickness.Value = Math.Clamp(_canvas.ActiveStyle.Thickness, 1, 12);
    }

    private void ShowStatus(string message, bool isError = false)
    {
        _status.Text = message;
        _status.Foreground = isError ? Palette.ErrorBrush : Palette.WhiteBrush;
        _statusPanel.Visibility = Visibility.Visible;
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            _statusPanel.Visibility = Visibility.Collapsed;
        };
        timer.Start();
    }

    private async void RunOcr()
    {
        if (_ocrRunning) return;
        _ocrRunning = true;
        int request = _session.BeginOcr();
        int revision = _session.Revision;
        _ocrCts?.Cancel();
        _ocrCts = new CancellationTokenSource();
        var token = _ocrCts.Token;

        if (!_ocr.TryPrepare(_settings, out string error))
        {
            _session.FailOcr(request, error);
            ShowStatus(error, isError: true);
            _ocrRunning = false;
            return;
        }

        var (page, failure) = await _ocr.RecognizeAsync(_session.Image, token);
        _ocrRunning = false;
        if (token.IsCancellationRequested) return;
        if (failure != null || page == null)
        {
            _session.FailOcr(request, failure ?? "识别失败");
            ShowStatus(failure ?? "识别失败", isError: true);
            return;
        }

        if (!_session.TryCompleteOcr(request, revision, page))
        {
            // The image changed while recognition was running; the result is dropped on purpose.
            ShowStatus("图片已修改，旧识别结果已丢弃", isError: true);
            return;
        }

        _canvas.SetTextModel(new TextSelectionModel(page));
        ShowStatus(page.HasText ? "可以直接在文字上拖选，Ctrl+Shift+C 复制全部" : "没有识别到文字，仍可标注和输出图片");
    }

    /// <summary>
    /// After a mask or crop the recognized text no longer matches the visible pixels. Text output stays
    /// blocked until recognition runs again on the composed image (never on the cached original).
    /// </summary>
    private void RefreshSafeText()
    {
        var state = _session.CheckTextOutput();
        if (state is TextOutput.Stale && !_ocrRunning) RunOcr();
    }

    private string ComposePath(string extension)
    {
        var dir = _settings.ResolvedSaveDirectory;
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, $"ccShot-{DateTime.Now:yyyyMMdd-HHmmss}.{extension}");
    }

    private (PixelImage Image, BitmapSource Bitmap) Compose()
    {
        var composed = ImageCompositor.Compose(_session.Image, _session.Annotations);
        return (composed, BitmapInterop.ToBitmapSource(composed));
    }

    private void CopyImage()
    {
        var (_, bitmap) = Compose();
        try
        {
            Clipboard.SetImage(bitmap);
            ShowStatus($"已复制图片 {bitmap.PixelWidth}×{bitmap.PixelHeight}");
        }
        catch (Exception ex)
        {
            ShowStatus("复制图片失败：" + ex.Message, isError: true);
        }
    }

    private void CopyText(bool all)
    {
        switch (_session.CheckTextOutput())
        {
            case TextOutput.Allowed:
                string text = all ? _session.OcrPage?.ToPlainText() ?? string.Empty : _canvas.SelectedText;
                if (string.IsNullOrEmpty(text))
                {
                    ShowStatus("先在图片上拖选要复制的文字", isError: false);
                    return;
                }

                try
                {
                    Clipboard.SetText(text);
                    ShowStatus($"已复制 {text.Length} 个字符");
                }
                catch (Exception ex)
                {
                    ShowStatus("复制文字失败：" + ex.Message, isError: true);
                }

                break;
            case TextOutput.Pending:
                ShowStatus("正在识别文字，请稍候");
                break;
            case TextOutput.NoText:
                ShowStatus("这张图没有识别到文字，剪贴板保持原内容", isError: true);
                break;
            case TextOutput.Failed:
                ShowStatus("文字识别失败：" + (_session.FailureReason ?? "未知原因"), isError: true);
                break;
            default:
                ShowStatus("图片已修改，正在重新识别后再复制", isError: true);
                RunOcr();
                break;
        }
    }

    private void SaveImage()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Title = "保存截图",
            Filter = "PNG 图片|*.png|JPG 图片|*.jpg",
            FileName = $"ccShot-{DateTime.Now:yyyyMMdd-HHmmss}.png",
            InitialDirectory = _settings.ResolvedSaveDirectory,
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var (image, _) = Compose();
            BitmapInterop.Save(image, dialog.FileName);
            ShowStatus("已保存：" + Path.GetFileName(dialog.FileName));
        }
        catch (Exception ex)
        {
            ShowStatus("保存失败：" + ex.Message, isError: true);
        }
    }

    private void PinImage()
    {
        var (image, _) = Compose();
        new Pin.PinWindow(image, _monitor).Show();
        ShowStatus("已钉图：拖动移动，滚轮缩放，Esc 关闭");
    }

    private void ShowTextEditor(PointF origin)
    {
        _textEditor.Text = string.Empty;
        _textEditor.Visibility = Visibility.Visible;
        _textEditor.Width = Math.Max(120, _session.Image.Width / _scale * 0.5);
        var position = new Point(origin.X / _scale, origin.Y / _scale);
        _textEditor.Margin = new Thickness(Math.Max(0, position.X), Math.Max(0, position.Y), 0, 0);
        _textEditor.HorizontalAlignment = HorizontalAlignment.Left;
        _textEditor.VerticalAlignment = VerticalAlignment.Top;
        _textEditor.Focus();
        _textEditor.Tag = origin;
    }

    private void TextEditorKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            _textEditor.Visibility = Visibility.Collapsed;
            _canvas.Focus();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Enter && Keyboard.Modifiers != ModifierKeys.Shift)
        {
            CommitTextEditor();
            e.Handled = true;
        }
    }

    private void CommitTextEditor()
    {
        if (_textEditor.Visibility != Visibility.Visible) return;
        var text = _textEditor.Text;
        _textEditor.Visibility = Visibility.Collapsed;
        if (_textEditor.Tag is PointF origin && !string.IsNullOrWhiteSpace(text)) _canvas.CommitText(text, origin);
        _canvas.Focus();
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.FocusedElement is TextBox tb && !ReferenceEquals(tb, _textEditor))
        {
            // A real input control owns its keys; do not hijack typing.
            return;
        }

        bool control = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        bool shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        if (control)
        {
            switch (e.Key)
            {
                case Key.C when shift:
                    CopyText(true);
                    e.Handled = true;
                    return;
                case Key.C:
                    if (_canvas.HasTextSelection) CopyText(false);
                    else CopyImage();
                    e.Handled = true;
                    return;
                case Key.S:
                    SaveImage();
                    e.Handled = true;
                    return;
                case Key.Z:
                    _canvas.Undo();
                    e.Handled = true;
                    return;
                case Key.Y:
                    _canvas.Redo();
                    e.Handled = true;
                    return;
                case Key.A:
                    _canvas.SelectAllText();
                    e.Handled = true;
                    return;
            }

            return;
        }

        switch (e.Key)
        {
            case Key.Escape:
                if (_canvas.HasTextSelection)
                {
                    _canvas.ClearTextSelection();
                }
                else if (_canvas.Tool != EditorTool.Select)
                {
                    SetTool(EditorTool.Select);
                }
                else
                {
                    Close();
                }

                e.Handled = true;
                break;
            case Key.Delete:
            case Key.Back:
                _canvas.DeleteSelected();
                e.Handled = true;
                break;
            case Key.V: SetTool(EditorTool.Select); break;
            case Key.A: SetTool(EditorTool.Arrow); break;
            case Key.R: SetTool(EditorTool.Rect); break;
            case Key.E: SetTool(EditorTool.Ellipse); break;
            case Key.T: SetTool(EditorTool.Text); break;
            case Key.P: SetTool(EditorTool.Pen); break;
            case Key.M: SetTool(EditorTool.MaskRect); break;
            case Key.H: SetTool(EditorTool.Highlight); break;
            case Key.N: SetTool(EditorTool.Number); break;
            case Key.D1: ApplyColor(0); break;
            case Key.D2: ApplyColor(1); break;
            case Key.D3: ApplyColor(2); break;
            case Key.D4: ApplyColor(3); break;
            case Key.D5: ApplyColor(4); break;
            case Key.D6: ApplyColor(5); break;
            case Key.D7: ApplyColor(6); break;
        }
    }

    private void SetTool(EditorTool tool)
    {
        _canvas.Tool = tool;
        UpdateButtons();
        _canvas.Focus();
    }

    private void ApplyColor(int index)
    {
        if (index < 0 || index >= Palette.AnnotationColors.Length) return;
        _canvas.SetStyle(_canvas.ActiveStyle with { ColorArgb = Palette.ToArgb(Palette.AnnotationColors[index]) });
    }
}
