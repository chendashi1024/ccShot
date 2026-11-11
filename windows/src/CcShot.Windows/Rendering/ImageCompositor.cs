using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CcShot.Core.Annotate;
using CcShot.Core.Imaging;

namespace CcShot.Windows.Rendering;

/// <summary>
/// Flattens the current image plus committed annotations into one bitmap. Copy, save, pin and the
/// second recognition pass all use this output, which is what keeps the visible content and the exported
/// content identical (no annotations, no selection highlight, no toolbar in the pixels).
/// </summary>
internal static class ImageCompositor
{
    public static PixelImage Compose(PixelImage source, AnnotationDocument document)
    {
        if (source.IsEmpty) return source;
        if (document.Items.Count == 0) return source;

        var bitmap = BitmapInterop.ToBitmapSource(source);
        var visual = new DrawingVisual();
        var imageRect = new Rect(0, 0, source.Width, source.Height);
        using (var dc = visual.RenderOpen())
        {
            dc.DrawImage(bitmap, imageRect);
            var masks = document.Items.OfType<MaskItem>().Any(mask => mask.Effect != MaskEffect.Solid)
                ? BuildMaskImages(source) : null;
            foreach (var item in document.Items) AnnotationRenderer.Draw(dc, item, 1.0, masks);
        }

        var target = new RenderTargetBitmap(source.Width, source.Height, 96, 96, PixelFormats.Pbgra32);
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        target.Render(visual);
        return BitmapInterop.ToPixelImage(target);
    }

    /// <summary>Preview bitmap of the composed result for pinning without making the pin re-render annotations.</summary>
    public static BitmapSource ComposeBitmap(PixelImage source, AnnotationDocument document) =>
        BitmapInterop.ToBitmapSource(Compose(source, document));

    public static MaskImages BuildMaskImages(PixelImage source)
    {
        var bitmap = BitmapInterop.ToBitmapSource(source);
        return new MaskImages(bitmap,
            BitmapInterop.ToBitmapSource(ImageEffects.Pixelate(source, Math.Max(8, source.Width / 90))),
            BitmapInterop.ToBitmapSource(ImageEffects.BoxBlur(source, Math.Max(3, source.Width / 300))),
            new Rect(0, 0, source.Width, source.Height));
    }
}
