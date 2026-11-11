using System;
using CcShot.Core.Geometry;

namespace CcShot.Core.Imaging;

/// <summary>
/// Tightly packed 32-bit BGRA image (stride = Width * 4). This is the exact layout of a GDI
/// <c>DIB</c> capture and of a WPF <c>Bgra32</c> bitmap, so no conversion is needed in either direction.
/// </summary>
public sealed class PixelImage
{
    public static readonly PixelImage Empty = new(0, 0, Array.Empty<byte>());

    public PixelImage(int width, int height, byte[] bgra)
    {
        if (width < 0 || height < 0) throw new ArgumentOutOfRangeException(nameof(width));
        if (bgra.Length != width * height * 4) throw new ArgumentException("BGRA buffer size does not match width*height*4.", nameof(bgra));
        Width = width;
        Height = height;
        Bgra = bgra;
    }

    public int Width { get; }
    public int Height { get; }
    public int Stride => Width * 4;
    public byte[] Bgra { get; }
    public bool IsEmpty => Width <= 0 || Height <= 0;
    public int PixelCount => Width * Height;
    public RectI BoundsRect => new(0, 0, Width, Height);

    public static PixelImage Create(int width, int height, byte b = 0, byte g = 0, byte r = 0, byte a = 255)
    {
        var buf = new byte[width * height * 4];
        for (int i = 0; i < buf.Length; i += 4)
        {
            buf[i] = b;
            buf[i + 1] = g;
            buf[i + 2] = r;
            buf[i + 3] = a;
        }

        return new PixelImage(width, height, buf);
    }

    public (byte B, byte G, byte R, byte A) GetPixel(int x, int y)
    {
        if (x < 0 || y < 0 || x >= Width || y >= Height) return (0, 0, 0, 0);
        int i = (y * Width + x) * 4;
        return (Bgra[i], Bgra[i + 1], Bgra[i + 2], Bgra[i + 3]);
    }

    /// <summary>Copies a whole-pixel region. The rectangle is clipped to the image and never returns out-of-range data.</summary>
    public PixelImage Crop(RectI rect)
    {
        var clipped = rect.Intersect(BoundsRect);
        if (clipped.IsEmpty) return Empty;
        var dst = new byte[clipped.Width * clipped.Height * 4];
        for (int row = 0; row < clipped.Height; row++)
        {
            int srcOffset = ((clipped.Y + row) * Width + clipped.X) * 4;
            Buffer.BlockCopy(Bgra, srcOffset, dst, row * clipped.Width * 4, clipped.Width * 4);
        }

        return new PixelImage(clipped.Width, clipped.Height, dst);
    }

    public PixelImage Clone() => new(Width, Height, (byte[])Bgra.Clone());

    /// <summary>Copies <paramref name="source"/> onto this image at the given offset (non-premultiplied alpha blend).</summary>
    public void BlendOnto(PixelImage source, int destX, int destY, byte opacity = 255)
    {
        for (int y = 0; y < source.Height; y++)
        {
            int ty = destY + y;
            if (ty < 0 || ty >= Height) continue;
            for (int x = 0; x < source.Width; x++)
            {
                int tx = destX + x;
                if (tx < 0 || tx >= Width) continue;
                int si = (y * source.Width + x) * 4;
                int di = (ty * Width + tx) * 4;
                int sa = source.Bgra[si + 3] * opacity / 255;
                if (sa == 0) continue;
                if (sa == 255)
                {
                    Bgra[di] = source.Bgra[si];
                    Bgra[di + 1] = source.Bgra[si + 1];
                    Bgra[di + 2] = source.Bgra[si + 2];
                    Bgra[di + 3] = 255;
                    continue;
                }

                int dstA = Bgra[di + 3];
                int outA = sa + dstA * (255 - sa) / 255;
                if (outA <= 0) { Bgra[di + 3] = 0; continue; }
                for (int c = 0; c < 3; c++)
                {
                    int sc = source.Bgra[si + c];
                    int dc = Bgra[di + c];
                    Bgra[di + c] = (byte)((sc * sa + dc * dstA * (255 - sa) / 255) / outA);
                }

                Bgra[di + 3] = (byte)outA;
            }
        }
    }
}
