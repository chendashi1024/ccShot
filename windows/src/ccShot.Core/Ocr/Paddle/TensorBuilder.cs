using System;
using ccShot.Core.Geometry;
using ccShot.Core.Imaging;

namespace ccShot.Core.Ocr.Paddle;

/// <summary>Bilinear resize + channel-planar float tensor construction shared by detection and recognition.</summary>
internal static class TensorBuilder
{
    /// <summary>
    /// Resizes the BGRA image to <paramref name="dstW"/>x<paramref name="dstH"/> and writes a planar RGB
    /// float array (channel order R,G,B as PaddleOCR expects), scaled with <c>(v/255 - mean) / std</c>.
    /// </summary>
    public static float[] ToPlanarRgb(PixelImage image, RectI source, int dstW, int dstH, float[] mean, float[] std)
    {
        var buffer = new float[3 * dstW * dstH];
        int planeSize = dstW * dstH;
        var src = image.Bgra;
        int srcW = image.Width;
        float scaleX = source.Width / (float)dstW;
        float scaleY = source.Height / (float)dstH;

        for (int y = 0; y < dstH; y++)
        {
            float sy = source.Y + (y + 0.5f) * scaleY - 0.5f;
            if (sy < source.Y) sy = source.Y;
            if (sy > source.Bottom - 1) sy = source.Bottom - 1;
            int y0 = (int)sy;
            int y1 = Math.Min(y0 + 1, source.Bottom - 1);
            float fy = sy - y0;

            for (int x = 0; x < dstW; x++)
            {
                float sx = source.X + (x + 0.5f) * scaleX - 0.5f;
                if (sx < source.X) sx = source.X;
                if (sx > source.Right - 1) sx = source.Right - 1;
                int x0 = (int)sx;
                int x1 = Math.Min(x0 + 1, source.Right - 1);
                float fx = sx - x0;

                int i00 = (y0 * srcW + x0) * 4;
                int i01 = (y0 * srcW + x1) * 4;
                int i10 = (y1 * srcW + x0) * 4;
                int i11 = (y1 * srcW + x1) * 4;

                for (int c = 0; c < 3; c++)
                {
                    // BGRA -> RGB: c=0 (R) is byte offset 2, c=1 (G) offset 1, c=2 (B) offset 0.
                    int offset = c switch { 0 => 2, 1 => 1, _ => 0 };
                    float top = src[i00 + offset] * (1 - fx) + src[i01 + offset] * fx;
                    float bottom = src[i10 + offset] * (1 - fx) + src[i11 + offset] * fx;
                    float value = (top * (1 - fy) + bottom * fy) / 255f;
                    buffer[c * planeSize + y * dstW + x] = (value - mean[c]) / std[c];
                }
            }
        }

        return buffer;
    }

    /// <summary>Recognition normalization in PaddleOCR: <c>(v/255 - 0.5) / 0.5</c>, giving [-1, 1].</summary>
    public static float[] ToPlanarRgbNormalized(PixelImage image, RectI source, int dstW, int dstH) =>
        ToPlanarRgb(image, source, dstW, dstH, new[] { 0.5f, 0.5f, 0.5f }, new[] { 0.5f, 0.5f, 0.5f });
}
