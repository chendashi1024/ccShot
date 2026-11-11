using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CcShot.Core.Annotate;
using CcShot.Core.Geometry;
using CcShot.Windows;
using CcShot.Windows.Capture;
using CcShot.Windows.Editor;
using CcShot.Windows.Interop;
using CcShot.Windows.Pin;

internal static class Program
{
    private const uint KeyUp = 0x0002;
    private const uint LeftDown = 0x0002;
    private const uint LeftUp = 0x0004;

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length != 1) return 2;
        if (!Environment.UserInteractive)
        {
            Console.Error.WriteLine("缺少交互式 Windows 桌面，无法执行截图与热键检查。");
            return 3;
        }

        Console.WriteLine($"系统 {RuntimeInformation.OSDescription}，架构 {RuntimeInformation.OSArchitecture}");
        var app = new App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            try
            {
                await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
                await Verify(app, Path.GetFullPath(args[0]));
                app.Shutdown(0);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                app.Shutdown(1);
            }
        };
        return app.Run();
    }

    private static async Task Verify(App app, string path)
    {
        var image = new BitmapImage(new Uri(path));
        var monitor = MonitorService.Enumerate().Primary;
        var fixture = new Window
        {
            Title = "ccShot 自制验收样本",
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false,
            Topmost = true,
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
            Width = image.PixelWidth / monitor.EffectiveScale,
            Height = image.PixelHeight / monitor.EffectiveScale,
            Content = new Image { Source = image, Stretch = System.Windows.Media.Stretch.Fill },
        };
        fixture.Show();
        await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
        if (!NativeMethods.GetWindowRect(new WindowInteropHelper(fixture).Handle, out var rect))
            throw new InvalidOperationException("无法读取验收窗口位置。");

        // 只读取自制样本窗口的像素，不存桌面截图。
        var bounds = new RectI(rect.Left, rect.Top, rect.Width, rect.Height);
        await WaitUntil(() =>
        {
            var capture = ScreenCaptureService.Capture(bounds);
            var (b, g, r, a) = capture.GetPixel(2, 2);
            return a == 255 && b > 210 && g > 210 && r > 210;
        }, "验收窗口的屏幕像素");

        string clipboardMarker = Guid.NewGuid().ToString("N");
        Clipboard.SetText(clipboardMarker);
        SetCursorPos(rect.Left + 1, rect.Top + 1);
        Press(0x11, 0x12, 0x58);
        await WaitUntil(() => app.Windows.OfType<CaptureOverlayWindow>().Any(w => w.IsVisible), "全局快捷键与框选遮罩");
        await Drag(rect.Left, rect.Top, rect.Right, rect.Bottom);
        Press(0x0D);
        await WaitUntil(() => app.Windows.OfType<EditorWindow>().Any(w => w.IsVisible), "框选确认与编辑窗");

        var editor = app.Windows.OfType<EditorWindow>().Single(w => w.IsVisible);
        await WaitUntil(() => editor.HasRecognizedText, "本地识字");
        await VerifySelectedLetter(editor.SelectionSurface, "图上单字拖选与 Ctrl+C");
        Console.WriteLine("通过：全局热键、框选截图、CPU 识字、单字拖选和剪贴板回读。");

        Press(0x11, 0x12, 0x58);
        await WaitUntil(() => app.Windows.OfType<CaptureOverlayWindow>().Any(w => w.IsVisible), "第二次唤起");
        Press(0x1B);
        await WaitUntil(() => !app.Windows.OfType<CaptureOverlayWindow>().Any(w => w.IsVisible), "Esc 取消");
        Console.WriteLine("通过：连续唤起与 Esc 清除遮罩。");

        editor.Activate();
        var doc = editor.SelectionSurface.Document;
        var mark = doc.Add(new RectItem(new RectF(4, 5, 7, 7), AnnotationStyle.Default(AnnotationKind.Rect)));
        var pinButton = FindButton(editor, "钉住") ?? throw new InvalidOperationException("没有找到钉住按钮。");
        pinButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        await WaitUntil(() => app.Windows.OfType<PinWindow>().Any(pin => pin.HasRecognizedText), "钉图识字");
        var pinned = app.Windows.OfType<PinWindow>().Single();
        pinned.Activate();
        Clipboard.SetText(clipboardMarker);
        await VerifySelectedLetter(pinned.SelectionSurface!, "钉图拖选与 Ctrl+C");
        pinned.EditPin();
        var reopened = app.Windows.OfType<EditorWindow>().Single(window => window != editor);
        if (!reopened.SelectionSurface.Document.Items.Any(item => item.Id == mark.Id))
            throw new InvalidOperationException("继续编辑没有保留原标注。");
        reopened.Close();
        pinned.Close();
        Console.WriteLine("通过：钉图拖选与继续编辑原标注。");

        editor.Activate();
        foreach (var effect in Enum.GetValues<MaskEffect>())
        {
            var mask = doc.Add(new MaskItem(Array.Empty<PointF>(), AnnotationStyle.Default(AnnotationKind.Mask),
                effect, new RectF(0, 15, image.PixelWidth, 27)));
            await WaitUntil(() => editor.HasRecognizedText, $"{effect} 遮挡后重新识字");
            Clipboard.SetText(clipboardMarker);
            Press(0x11, 0x10, 0x43);
            await WaitUntil(() => Clipboard.ContainsText() && Clipboard.GetText() != clipboardMarker, $"{effect} 遮挡后复制全部文字");
            string copied = Clipboard.GetText();
            if (copied.Contains("quick brown fox", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException($"{effect} 遮挡后复制出了原文。");
            doc.Remove(mask);
        }
        editor.Close();
        Console.WriteLine("通过：实心、马赛克、模糊后的剪贴板均不含被遮挡原文。");

        fixture.Activate();
        var windowCapture = app.StartCaptureAsync(CaptureMode.Window);
        await WaitUntil(() => app.Windows.OfType<CaptureOverlayWindow>().Any(w => w.IsVisible), "窗口截图遮罩");
        SetCursorPos(rect.Left + rect.Width / 2, rect.Top + rect.Height / 2);
        await Task.Delay(100);
        mouse_event(LeftDown, 0, 0, 0, UIntPtr.Zero);
        mouse_event(LeftUp, 0, 0, 0, UIntPtr.Zero);
        await windowCapture.WaitAsync(TimeSpan.FromSeconds(15));
        var windowEditor = app.Windows.OfType<EditorWindow>().Single(w => w.IsVisible);
        var windowImage = windowEditor.SelectionSurface.Session.Image;
        if (windowImage.Width != rect.Width || windowImage.Height != rect.Height || windowImage.GetPixel(2, 2).R <= 210)
            throw new InvalidOperationException("窗口截图的范围或像素与样本不一致。");
        Console.WriteLine("通过：窗口点选取到了自制窗口，画面未包含选区遮罩。");
    }

    private static async Task VerifySelectedLetter(EditorCanvas canvas, string label)
    {
        var start = canvas.PointToScreen(new Point(23 * canvas.DipPerPixel, 29 * canvas.DipPerPixel));
        var end = canvas.PointToScreen(new Point(28 * canvas.DipPerPixel, 29 * canvas.DipPerPixel));
        await Drag((int)start.X, (int)start.Y, (int)end.X, (int)end.Y);
        Press(0x11, 0x43);
        await WaitUntil(() => Clipboard.ContainsText() && Clipboard.GetText() == "T", label);
    }

    private static Button? FindButton(DependencyObject element, string label)
    {
        if (element is Button { Content: string text } button && text == label) return button;
        return LogicalTreeHelper.GetChildren(element).OfType<DependencyObject>()
            .Select(child => FindButton(child, label)).FirstOrDefault(match => match != null);
    }

    private static async Task WaitUntil(Func<bool> ready, string label)
    {
        var elapsed = Stopwatch.StartNew();
        while (!ready())
        {
            if (elapsed.Elapsed > TimeSpan.FromSeconds(15))
                throw new InvalidOperationException($"等待超时：{label}");
            await Task.Delay(100);
        }
    }

    private static void Press(params byte[] keys)
    {
        foreach (byte key in keys) keybd_event(key, 0, 0, UIntPtr.Zero);
        foreach (byte key in keys.Reverse()) keybd_event(key, 0, KeyUp, UIntPtr.Zero);
    }

    private static async Task Drag(int x0, int y0, int x1, int y1)
    {
        SetCursorPos(x0, y0);
        await Task.Delay(80);
        mouse_event(LeftDown, 0, 0, 0, UIntPtr.Zero);
        await Task.Delay(80);
        SetCursorPos(x1, y1);
        await Task.Delay(80);
        mouse_event(LeftUp, 0, 0, 0, UIntPtr.Zero);
        await Task.Delay(120);
    }
}
