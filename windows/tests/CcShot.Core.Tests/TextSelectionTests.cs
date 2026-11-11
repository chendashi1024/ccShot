using System;
using System.Linq;
using CcShot.Core.Geometry;
using CcShot.Core.Ocr.Selection;
using Xunit;

namespace CcShot.Core.Tests;

public class TextSelectionTests
{
    private const string Sentence = "今天下午三点半";

    private static TextSelectionModel Model() =>
        new(FakeOcr.Line(Sentence, originX: 100, originY: 50, advance: 20, height: 30));

    [Fact]
    public void SingleCharacterCanBeSelectedOnItsOwn()
    {
        var model = Model();
        // Glyph index 4 is '三': box x = 100 + 4*20 = 180 .. 200.
        var selection = model.Select(new PointF(182, 60), new PointF(198, 62));

        Assert.Equal("三", model.Text(selection));
        Assert.Single(selection.Ranges);
        Assert.Equal(1, selection.GlyphCount);
        var rect = Assert.Single(model.HighlightRects(selection));
        Assert.Equal(180f, rect.Box.X, 1);
        Assert.Equal(20f, rect.Box.Width, 1);
    }

    [Fact]
    public void ReverseDragSelectsTheSameCharacters()
    {
        var model = Model();
        var forward = model.Select(new PointF(102, 60), new PointF(155, 60));
        var reverse = model.Select(new PointF(155, 60), new PointF(102, 60));

        Assert.Equal(model.Text(forward), model.Text(reverse));
        Assert.True(forward.Forward);
        Assert.False(reverse.Forward);
        Assert.Equal(3, reverse.GlyphCount);
    }

    [Fact]
    public void FirstAndLastCharacterAreReachable()
    {
        var model = Model();
        var first = model.Select(new PointF(-50, 60), new PointF(115, 60));
        var last = model.Select(new PointF(225, 60), new PointF(400, 60));

        Assert.Equal("今", model.Text(first));
        Assert.Equal("半", model.Text(last));
    }

    [Fact]
    public void PunctuationIsSelectableAlone()
    {
        var model = new TextSelectionModel(FakeOcr.Line("好的，谢谢。", 10, 10, 18, 28));
        // '，' is at index 2 -> x 46..64.
        var selection = model.Select(new PointF(48, 20), new PointF(62, 20));
        Assert.Equal("，", model.Text(selection));
    }

    [Fact]
    public void MixedChineseAndLatinKeepsSpacesFromTheRecognizer()
    {
        var page = FakeOcr.Line("用 ccShot 截图", 0, 0, 16, 26);
        var model = new TextSelectionModel(page);
        var all = model.SelectAll();
        Assert.Equal("用 ccShot 截图", model.Text(all));
    }

    [Fact]
    public void CrossLineSelectionProducesNewlinesAndPerLineRects()
    {
        var page = FakeOcr.Lines(("第一行文字", 50, 40), ("第二行文字", 50, 100));
        var model = new TextSelectionModel(page);
        // Start in the middle of line 1, end after the second character of line 2.
        var selection = model.Select(new PointF(135, 50), new PointF(95, 110));

        Assert.Equal(2, selection.Ranges.Count);
        var text = model.Text(selection);
        var parts = text.Split('\n');
        Assert.Equal(2, parts.Length);
        Assert.StartsWith("第二", parts[1]);
        Assert.Equal(2, model.HighlightRects(selection).Count);
        Assert.Equal(2, model.HighlightRects(selection).Select(r => r.LineIndex).Distinct().Count());
    }

    [Fact]
    public void ClickWithoutDragSelectsNothing()
    {
        var model = Model();
        var selection = model.Select(new PointF(150, 60), new PointF(150, 60));
        Assert.True(selection.IsEmpty);
        Assert.Equal(string.Empty, model.Text(selection));
        Assert.Empty(model.HighlightRects(selection));
    }

    [Fact]
    public void DoubleClickSelectsAWholeLatinWord()
    {
        var page = FakeOcr.Line("open source tool", 0, 0, 12, 24);
        var model = new TextSelectionModel(page);
        // 'source' starts at character 5 -> x 60.
        var word = model.SelectWordAt(new PointF(72, 10));
        Assert.Equal("source", model.Text(word));
    }

    [Fact]
    public void DoubleClickOnCjkSelectsOneCharacter()
    {
        var model = Model();
        var word = model.SelectWordAt(new PointF(190, 60));
        Assert.Equal("三", model.Text(word));
    }

    [Fact]
    public void WideAndNarrowGlyphsUseTheirOwnBoxes()
    {
        var page = FakeOcr.VaryingWidths(new[]
        {
            ("i", 0f, 6f), ("l", 6f, 6f), ("宽", 12f, 22f), ("字", 34f, 22f),
        }, 10);
        var model = new TextSelectionModel(page);
        var narrow = model.Select(new PointF(1, 20), new PointF(10, 20));
        var wide = model.Select(new PointF(20, 20), new PointF(30, 20));

        Assert.Equal("il", model.Text(narrow));
        Assert.Equal("宽", model.Text(wide));
        var wideRect = model.HighlightRects(wide).Single();
        Assert.Equal(22f, wideRect.Box.Width, 1);
    }

    [Fact]
    public void SelectionBoundsCoverAllSelectedLines()
    {
        var page = FakeOcr.Lines(("第一行文字", 50, 40), ("第二行文字", 50, 100));
        var model = new TextSelectionModel(page);
        var selection = model.SelectAll();
        var bounds = model.SelectionBounds(selection);
        Assert.Equal(40f, bounds.Y, 1);
        Assert.Equal(130f, bounds.Bottom, 1);
    }
}
