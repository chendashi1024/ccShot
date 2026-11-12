using ccShot.Core.Imaging;
using Xunit;

namespace ccShot.Core.Tests;

public class ImageEffectsTests
{
    [Fact]
    public void PixelateAveragesEachBlock()
    {
        // 2x2 blocks: black, white, white, black.
        var image = PixelImage.Create(4, 4, 0, 0, 0);
        for (int y = 0; y < 2; y++)
        {
            for (int x = 2; x < 4; x++) image.Bgra[(y * 4 + x) * 4] = 255;
        }

        var mosaic = ImageEffects.Pixelate(image, 2);
        Assert.Equal(4, mosaic.Width);
        var topLeft = mosaic.GetPixel(0, 0);
        var topRight = mosaic.GetPixel(2, 0);
        var bottomLeft = mosaic.GetPixel(0, 2);
        Assert.Equal(topLeft, bottomLeft);
        Assert.NotEqual(topLeft.B, topRight.B);
    }

    [Fact]
    public void BoxBlurSpreadsAColourIntoNeighbours()
    {
        var image = PixelImage.Create(5, 1, 0, 0, 0);
        image.Bgra[(0 * 5 + 2) * 4] = 200; // one bright blue pixel in the middle
        var blurred = ImageEffects.BoxBlur(image, 1);

        Assert.Equal(5, blurred.Width);
        Assert.True(blurred.GetPixel(1, 0).B > 0);
        Assert.True(blurred.GetPixel(2, 0).B < 200);
        Assert.Equal(0, blurred.GetPixel(0, 0).B); // radius 1 does not reach the far edge
    }

    [Fact]
    public void EffectsKeepImageSizeAndAlpha()
    {
        var image = PixelImage.Create(7, 3, 10, 20, 30, 128);
        Assert.Equal(image.Width, ImageEffects.BoxBlur(image, 2).Width);
        Assert.Equal(image.Height, ImageEffects.Pixelate(image, 3).Height);
        Assert.Equal(128, ImageEffects.BoxBlur(image, 2).GetPixel(3, 1).A);
    }
}
