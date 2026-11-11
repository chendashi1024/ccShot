using System.Linq;
using CcShot.Core.Geometry;
using CcShot.Core.Imaging;
using CcShot.Core.Ocr;
using Xunit;

namespace CcShot.Core.Tests;

public class InkProfileTests
{
    /// <summary>White canvas with dark blocks standing in for glyphs.</summary>
    private static PixelImage Strip(params (int From, int To)[] blocks)
    {
        const int width = 120, height = 20;
        var image = PixelImage.Create(width, height, 255, 255, 255);
        foreach (var (from, to) in blocks)
        {
            for (int y = 2; y < height - 2; y++)
            {
                for (int x = from; x < to && x < width; x++)
                {
                    int i = (y * width + x) * 4;
                    image.Bgra[i] = 20;
                    image.Bgra[i + 1] = 20;
                    image.Bgra[i + 2] = 20;
                }
            }
        }

        return image;
    }

    private static OcrGlyph Glyph(string text, float x, float width) =>
        new(text, new RectF(x, 2, width, 16));

    [Fact]
    public void BlankColumnsAreDetectedBetweenWords()
    {
        var image = Strip((0, 20), (40, 60));
        var ink = InkProfile.ColumnsWithInk(image, new RectI(0, 0, 120, 20));

        Assert.True(ink[10]);
        Assert.False(ink[30]);
        var (start, length) = InkProfile.LongestBlankRun(ink, 20, 40);
        Assert.Equal(20, start);
        Assert.Equal(20, length);
    }

    [Fact]
    public void SpaceIsInsertedAtTheBlankBand()
    {
        var image = Strip((0, 20), (40, 60));
        var ink = InkProfile.ColumnsWithInk(image, new RectI(0, 0, 120, 20));
        var glyphs = new[] { Glyph("a", 2, 16), Glyph("b", 42, 16) };

        var result = InkProfile.InsertWordSpaces(glyphs, ink, new RectI(0, 0, 120, 20));
        Assert.Equal("a b", string.Concat(result.Select(g => g.Text)));
        var space = result.Single(g => g.Text == " ");
        Assert.InRange(space.Box.X, 25f, 40f);
    }

    [Fact]
    public void NoSpaceIsInsertedWhenGlyphsTouch()
    {
        var image = Strip((0, 60));
        var ink = InkProfile.ColumnsWithInk(image, new RectI(0, 0, 120, 20));
        var glyphs = new[] { Glyph("a", 2, 16), Glyph("b", 20, 16) };
        var result = InkProfile.InsertWordSpaces(glyphs, ink, new RectI(0, 0, 120, 20));
        Assert.Equal("ab", string.Concat(result.Select(g => g.Text)));
    }

    [Fact]
    public void ChineseNeverReceivesAnInsertedSpace()
    {
        var image = Strip((0, 20), (40, 60));
        var ink = InkProfile.ColumnsWithInk(image, new RectI(0, 0, 120, 20));
        var glyphs = new[] { Glyph("中", 2, 16), Glyph("文", 42, 16) };
        var result = InkProfile.InsertWordSpaces(glyphs, ink, new RectI(0, 0, 120, 20));
        Assert.Equal("中文", string.Concat(result.Select(g => g.Text)));
    }

    [Fact]
    public void DarkThemeBackgroundIsRecognised()
    {
        var image = PixelImage.Create(100, 20, 20, 20, 20);
        for (int y = 4; y < 16; y++)
        {
            for (int x = 10; x < 20; x++)
            {
                int i = (y * 100 + x) * 4;
                image.Bgra[i] = 240;
                image.Bgra[i + 1] = 240;
                image.Bgra[i + 2] = 240;
            }
        }

        var ink = InkProfile.ColumnsWithInk(image, new RectI(0, 0, 100, 20));
        Assert.True(ink[15]);
        Assert.False(ink[50]);
    }
}
