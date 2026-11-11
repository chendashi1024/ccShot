using System;

namespace CcShot.Core.Imaging;

/// <summary>
/// Pixel effects used by the redaction tools. Deliberately simple and dependency free so they run on
/// any platform and can be unit tested: mosaic averages square blocks, blur is a separable box blur.
/// </summary>
public static class ImageEffects
{
    /// <summary>Mosaic: every block becomes the average colour of that block.</summary>
    public static PixelImage Pixelate(PixelImage source, int blockSize)
    {
        if (source.IsEmpty) return source;
        blockSize = Math.Max(2, blockSize);
        var result = new PixelImage(source.Width, source.Height, new byte[source.Bgra.Length]);
        var src = source.Bgra;
        var dst = result.Bgra;
        for (int by = 0; by < source.Height; by += blockSize)
        {
            int yEnd = Math.Min(by + blockSize, source.Height);
            for (int bx = 0; bx < source.Width; bx += blockSize)
            {
                int xEnd = Math.Min(bx + blockSize, source.Width);
                long b = 0, g = 0, r = 0, a = 0;
                int count = (xEnd - bx) * (yEnd - by);
                for (int y = by; y < yEnd; y++)
                {
                    for (int x = bx; x < xEnd; x++)
                    {
                        int i = (y * source.Width + x) * 4;
                        b += src[i];
                        g += src[i + 1];
                        r += src[i + 2];
                        a += src[i + 3];
                    }
                }

                byte ab = (byte)(b / count), ag = (byte)(g / count), ar = (byte)(r / count), aa = (byte)(a / count);
                for (int y = by; y < yEnd; y++)
                {
                    for (int x = bx; x < xEnd; x++)
                    {
                        int i = (y * source.Width + x) * 4;
                        dst[i] = ab;
                        dst[i + 1] = ag;
                        dst[i + 2] = ar;
                        dst[i + 3] = aa;
                    }
                }
            }
        }

        return result;
    }

    /// <summary>Separable box blur; alpha is averaged as well so transparent screenshots stay consistent.</summary>
    public static PixelImage BoxBlur(PixelImage source, int radius)
    {
        if (source.IsEmpty) return source;
        radius = Math.Max(1, radius);
        var horizontal = new byte[source.Bgra.Length];
        var result = new byte[source.Bgra.Length];
        int width = source.Width, height = source.Height;
        var src = source.Bgra;

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int b = 0, g = 0, r = 0, a = 0, count = 0;
                int from = Math.Max(0, x - radius), to = Math.Min(width - 1, x + radius);
                for (int sx = from; sx <= to; sx++)
                {
                    int i = (y * width + sx) * 4;
                    b += src[i];
                    g += src[i + 1];
                    r += src[i + 2];
                    a += src[i + 3];
                    count++;
                }

                int o = (y * width + x) * 4;
                horizontal[o] = (byte)(b / count);
                horizontal[o + 1] = (byte)(g / count);
                horizontal[o + 2] = (byte)(r / count);
                horizontal[o + 3] = (byte)(a / count);
            }
        }

        for (int x = 0; x < width; x++)
        {
            for (int y = 0; y < height; y++)
            {
                int b = 0, g = 0, r = 0, a = 0, count = 0;
                int from = Math.Max(0, y - radius), to = Math.Min(height - 1, y + radius);
                for (int sy = from; sy <= to; sy++)
                {
                    int i = (sy * width + x) * 4;
                    b += horizontal[i];
                    g += horizontal[i + 1];
                    r += horizontal[i + 2];
                    a += horizontal[i + 3];
                    count++;
                }

                int o = (y * width + x) * 4;
                result[o] = (byte)(b / count);
                result[o + 1] = (byte)(g / count);
                result[o + 2] = (byte)(r / count);
                result[o + 3] = (byte)(a / count);
            }
        }

        return new PixelImage(width, height, result);
    }
}
