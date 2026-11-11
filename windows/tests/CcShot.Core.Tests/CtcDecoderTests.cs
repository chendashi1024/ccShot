using System.Collections.Generic;
using CcShot.Core.Ocr.Paddle;
using Xunit;

namespace CcShot.Core.Tests;

public class CtcDecoderTests
{
    private static readonly string[] Dictionary = { "a", "b" };

    private static float[] Build(int timeSteps, int classes, params int[] winners)
    {
        var logits = new float[timeSteps * classes];
        for (int t = 0; t < timeSteps; t++)
        {
            int winner = t < winners.Length ? winners[t] : 0;
            for (int c = 0; c < classes; c++) logits[t * classes + c] = c == winner ? 8f : 0f;
        }

        return logits;
    }

    [Fact]
    public void DecodesCharactersWithTheirTimeRanges()
    {
        const int classes = 4; // blank, a, b, space
        var logits = Build(6, classes, 0, 1, 1, 0, 2, 0);
        var chars = CtcDecoder.Decode(logits, 6, classes, Dictionary);

        Assert.Equal(2, chars.Count);
        Assert.Equal("a", chars[0].Text);
        Assert.Equal(1, chars[0].TimeStart);
        Assert.Equal(2, chars[0].TimeEnd);
        Assert.Equal("b", chars[1].Text);
        Assert.Equal(4, chars[1].TimeStart);
        Assert.Equal(4, chars[1].TimeEnd);
    }

    [Fact]
    public void RepeatedCharacterWithoutBlankCollapsesToSingleGlyph()
    {
        const int classes = 4;
        var logits = Build(4, classes, 1, 1, 1, 0);
        var chars = CtcDecoder.Decode(logits, 4, classes, Dictionary);
        Assert.Single(chars);
        Assert.Equal("a", chars[0].Text);
    }

    [Fact]
    public void RepeatedCharacterSeparatedByBlankIsKeptTwice()
    {
        const int classes = 4;
        var logits = Build(5, classes, 1, 0, 1, 0, 0);
        var chars = CtcDecoder.Decode(logits, 5, classes, Dictionary);
        Assert.Equal(2, chars.Count);
        Assert.All(chars, c => Assert.Equal("a", c.Text));
    }

    [Fact]
    public void SpaceUsesTheExtraClassAfterTheDictionary()
    {
        const int classes = 4;
        var logits = Build(4, classes, 1, 3, 2, 0);
        var chars = CtcDecoder.Decode(logits, 4, classes, Dictionary);
        Assert.Equal("a b", string.Concat(System.Linq.Enumerable.Select(chars, c => c.Text)));
    }

    [Fact]
    public void AllBlankProducesNoCharacters()
    {
        const int classes = 4;
        var logits = Build(5, classes);
        Assert.Empty(CtcDecoder.Decode(logits, 5, classes, Dictionary));
    }
}
