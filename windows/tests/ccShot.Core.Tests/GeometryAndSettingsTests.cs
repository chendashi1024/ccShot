using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ccShot.Core.Capture;
using ccShot.Core.Geometry;
using ccShot.Core.Imaging;
using ccShot.Core.Ocr;
using ccShot.Core.Ocr.Selection;
using ccShot.Core.Settings;
using Xunit;

namespace ccShot.Core.Tests;

public class MonitorLayoutTests
{
    private static MonitorLayout Mixed()
    {
        // Primary 1920x1080 at 100%, a 2560x1440 secondary at 150% placed to the left and above,
        // which is the case that produces negative virtual-desktop coordinates.
        return new MonitorLayout(new[]
        {
            new MonitorInfo(@"\\.\DISPLAY1", new RectI(0, 0, 1920, 1080), 1.0, true),
            new MonitorInfo(@"\\.\DISPLAY2", new RectI(-2560, -360, 2560, 1440), 1.5, false),
        });
    }

    [Fact]
    public void VirtualDesktopIncludesNegativeOrigins()
    {
        var layout = Mixed();
        Assert.Equal(new RectI(-2560, -360, 4480, 1440), layout.VirtualDesktopPx);
    }

    [Fact]
    public void PointHitsTheCorrectMonitorAcrossTheOrigin()
    {
        var layout = Mixed();
        Assert.Equal(@"\\.\DISPLAY1", layout.MonitorAt(new PointF(100, 100))!.DeviceName);
        Assert.Equal(@"\\.\DISPLAY2", layout.MonitorAt(new PointF(-100, -100))!.DeviceName);
        Assert.Null(layout.MonitorAt(new PointF(5000, 5000)));
        Assert.Equal(@"\\.\DISPLAY2", layout.NearestMonitor(new PointF(-4000, 0)).DeviceName);
    }

    [Fact]
    public void ScreenPointMapsToCaptureLocalPixels()
    {
        var layout = Mixed();
        var secondary = layout.Monitors[1];
        var local = MonitorLayout.ScreenToLocal(secondary, new PointF(-2560, -360));
        Assert.Equal(new PointF(0, 0), local);
        Assert.Equal(new PointF(-2560, -360), MonitorLayout.LocalToScreen(secondary, new PointF(0, 0)));

        var rect = MonitorLayout.ScreenRectToLocal(secondary, new RectI(-2460, -260, 200, 100));
        Assert.Equal(new RectI(100, 100, 200, 100), rect);
    }

    [Fact]
    public void SelectionAcrossTheSeamIsClippedPerMonitor()
    {
        var layout = Mixed();
        var selection = new ScreenRectSelection(new RectI(-200, 0, 400, 200));
        var parts = layout.Split(selection);

        Assert.Equal(2, parts.Count);
        Assert.Equal(new RectI(0, 0, 200, 200), parts[0].Local);
        Assert.Equal(new RectI(2360, 360, 200, 200), parts[1].Local);
        Assert.Equal(400 * 200, parts.Sum(p => p.Local.Width * p.Local.Height));
    }

    [Fact]
    public void ScaleChangeIsAppliedWithoutTouchingGeometry()
    {
        var layout = Mixed();
        var changed = layout.WithScales(new Dictionary<string, double> { [@"\\.\DISPLAY1"] = 2.0 });
        Assert.Equal(2.0, changed.Monitors[0].Scale);
        Assert.Equal(1.5, changed.Monitors[1].Scale);
        Assert.Equal(layout.VirtualDesktopPx, changed.VirtualDesktopPx);
    }
}

public class TextMetricsTests
{
    [Fact]
    public void WhitespaceIsIgnoredByDefault()
    {
        Assert.Equal(0d, TextMetrics.Cer("今天 下午\n三点", "今天下午三点"));
        Assert.True(TextMetrics.ExactMatch("第一行\n第二行", "第一行 第二行"));
        Assert.False(TextMetrics.ExactMatch("第一行\n第二行", "第一行 第二行", keepWhitespace: true));
    }

    [Fact]
    public void StrictModeKeepsWhitespaceDifferences()
    {
        double cer = TextMetrics.Cer("a b", "ab", keepWhitespace: true);
        Assert.True(cer > 0);
        Assert.False(TextMetrics.ExactMatch("a b", "ab", keepWhitespace: true));
    }

    [Fact]
    public void CharacterErrorRateCountsSubstitutionsInsertionsDeletions()
    {
        Assert.Equal(0.25, TextMetrics.Cer("abcd", "abxd"), 3);
        Assert.Equal(0.5, TextMetrics.Cer("abcd", "abcddd"), 3);
        Assert.Equal(0.5, TextMetrics.Cer("abcd", "ab"), 3);
        Assert.Equal(1d, TextMetrics.Cer(string.Empty, "多出来的字"));
        Assert.Equal(0d, TextMetrics.Cer(string.Empty, string.Empty));
    }

    [Fact]
    public void PunctuationAndCaseArePreserved()
    {
        Assert.False(TextMetrics.ExactMatch("Hello, world!", "hello world"));
        Assert.False(TextMetrics.ContainsWordChar("，。"));
        Assert.True(TextMetrics.ContainsWordChar("abc。"));
    }
}

public class HotkeyAndSettingsTests
{
    [Fact]
    public void ShortcutsRoundTrip()
    {
        Assert.True(HotkeyParser.TryParse("Ctrl+Alt+X", out var binding, out _));
        Assert.Equal(HotkeyModifiers.Control | HotkeyModifiers.Alt, binding.Modifiers);
        Assert.Equal("Ctrl+Alt+X", binding.ToString());

        Assert.True(HotkeyParser.TryParse("F1", out var f1, out _));
        Assert.True(HotkeyParser.IsFunctionKey(f1.Key));
        Assert.Equal("F1", f1.ToString());

        Assert.True(HotkeyParser.TryParse("shift+printscreen", out var ps, out _));
        Assert.Equal("Shift+PrintScreen", ps.ToString());
    }

    [Fact]
    public void InvalidShortcutsAreRejectedWithAReason()
    {
        Assert.False(HotkeyParser.TryParse("X", out _, out var error));
        Assert.Contains("全局键", error);
        Assert.False(HotkeyParser.TryParse("Ctrl+Alt", out _, out _));
        Assert.False(HotkeyParser.TryParse("Ctrl+A+B", out _, out _));
        Assert.False(HotkeyParser.TryParse("  ", out _, out _));
    }

    [Fact]
    public void SettingsSurviveASaveAndLoadCycle()
    {
        string dir = Path.Combine(Path.GetTempPath(), "ccShot-settings-" + Guid.NewGuid().ToString("n"));
        string path = Path.Combine(dir, "settings.json");
        try
        {
            var settings = new AppSettings { CaptureHotkey = "Ctrl+Shift+A", SaveDirectory = "/tmp/shots", ImageFormat = "jpg" };
            settings.Save(path);
            var loaded = AppSettings.Load(path);
            Assert.Equal("Ctrl+Shift+A", loaded.CaptureHotkey);
            Assert.Equal("/tmp/shots", loaded.SaveDirectory);
            Assert.Equal("jpg", loaded.ImageFormat);
        }
        finally
        {
            if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void CorruptSettingsFallBackToDefaultsInsteadOfCrashing()
    {
        string path = Path.Combine(Path.GetTempPath(), "ccShot-broken-" + Guid.NewGuid().ToString("n") + ".json");
        File.WriteAllText(path, "{ this is not json");
        try
        {
            var loaded = AppSettings.Load(path);
            Assert.Equal(HotkeyBinding.DefaultCapture.ToString(), loaded.CaptureHotkey);
        }
        finally
        {
            File.Delete(path);
        }
    }
}

public class PixelImageTests
{
    [Fact]
    public void CropIsClippedToTheImage()
    {
        var image = PixelImage.Create(10, 10, 10, 20, 30);
        var cropped = image.Crop(new RectI(-5, -5, 8, 8));
        Assert.Equal(3, cropped.Width);
        Assert.Equal(3, cropped.Height);
        var outOfRange = image.Crop(new RectI(100, 100, 10, 10));
        Assert.True(outOfRange.IsEmpty);
    }

    [Fact]
    public void BlendKeepsUncoveredPixels()
    {
        var background = PixelImage.Create(4, 4, 0, 0, 0);
        var overlay = PixelImage.Create(2, 2, 255, 255, 255);
        background.BlendOnto(overlay, 1, 1);
        Assert.Equal((255, 255, 255, 255), background.GetPixel(1, 1));
        Assert.Equal((0, 0, 0, 255), background.GetPixel(0, 0));
    }
}
