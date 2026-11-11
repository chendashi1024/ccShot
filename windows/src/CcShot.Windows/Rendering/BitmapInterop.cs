using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CcShot.Core.Imaging;

namespace CcShot.Windows.Rendering;

/// <summary>Conversions between the capture buffer (BGRA) and WPF <see cref="BitmapSource"/> instances.</summary>
internal static class BitmapInterop
{
    public static BitmapSource ToBitmapSource(PixelImage image)
    {
        if (image.IsEmpty) return BitmapSource.Create(1, 1, 96, 96, PixelFormats.Bgra32, null, new byte[4], 4);
        var bitmap = BitmapSource.Create(image.Width, image.Height, 96, 96, PixelFormats.Bgra32, null, image.Bgra, image.Stride);
        bitmap.Freeze();
        return bitmap;
    }

    public static PixelImage ToPixelImage(BitmapSource source)
    {
        BitmapSource bgra = source.Format == PixelFormats.Bgra32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        int width = bgra.PixelWidth, height = bgra.PixelHeight;
        var buffer = new byte[width * height * 4];
        bgra.CopyPixels(buffer, width * 4, 0);
        return new PixelImage(width, height, buffer);
    }

    public static PixelImage FromRenderTarget(RenderTargetBitmap target)
    {
        int width = target.PixelWidth, height = target.PixelHeight;
        var buffer = new byte[width * height * 4];
        target.CopyPixels(buffer, width * 4, 0);
        return new PixelImage(width, height, buffer);
    }

    /// <summary>Encodes to PNG or JPEG. JPEG has no alpha, so transparent areas become white like the macOS build.</summary>
    public static void Save(PixelImage image, string path)
    {
        var encoder = path.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase) ||
                      path.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase)
            ? (BitmapEncoder)new JpegBitmapEncoder { QualityLevel = 92 }
            : new PngBitmapEncoder();

        BitmapSource source = ToBitmapSource(image);
        if (encoder is JpegBitmapEncoder)
        {
            var visual = new DrawingVisual();
            using (var dc = visual.RenderOpen())
            {
                dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, image.Width, image.Height));
                dc.DrawImage(source, new Rect(0, 0, image.Width, image.Height));
            }

            var target = new RenderTargetBitmap(image.Width, image.Height, 96, 96, PixelFormats.Pbgra32);
            target.Render(visual);
            source = target;
        }

        encoder.Frames.Add(BitmapFrame.Create(source));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }
}
