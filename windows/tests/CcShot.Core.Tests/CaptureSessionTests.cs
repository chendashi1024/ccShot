using System.Linq;
using CcShot.Core.Annotate;
using CcShot.Core.Geometry;
using CcShot.Core.Imaging;
using CcShot.Core.Ocr;
using CcShot.Core.Session;
using Xunit;

namespace CcShot.Core.Tests;

public class CaptureSessionTests
{
    private static CaptureSession NewSession() => new(PixelImage.Create(200, 100, 200, 200, 200));

    [Fact]
    public void ResultForAnOlderRevisionIsRejected()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        int revision = session.Revision;

        session.ApplyCrop(new RectI(0, 0, 100, 100));
        Assert.True(session.Revision > revision);

        var page = FakeOcr.Line("文字", 0, 0, 20, 30);
        Assert.False(session.TryCompleteOcr(request, revision, page));
        Assert.NotEqual(TextOutput.Allowed, session.CheckTextOutput());
    }

    [Fact]
    public void LateResultAfterCancelIsIgnored()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        int revision = session.Revision;

        session.Invalidate(OcrState.Invalidated, "用户取消");
        Assert.False(session.TryCompleteOcr(request, revision, FakeOcr.Line("文字", 0, 0, 20, 30)));
        Assert.Equal(TextOutput.Stale, session.CheckTextOutput());
    }

    [Fact]
    public void FreshResultIsAllowed()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        int revision = session.Revision;
        Assert.True(session.TryCompleteOcr(request, revision, FakeOcr.Line("文字", 0, 0, 20, 30)));
        Assert.Equal(TextOutput.Allowed, session.CheckTextOutput());
    }

    [Fact]
    public void EmptyRecognitionIsReportedAsNoTextNotSuccess()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        Assert.True(session.TryCompleteOcr(request, session.Revision, OcrPage.Empty));
        Assert.Equal(TextOutput.NoText, session.CheckTextOutput());
    }

    [Fact]
    public void AddingAnAnnotationInvalidatesRecognizedText()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        Assert.True(session.TryCompleteOcr(request, session.Revision, FakeOcr.Line("文字", 0, 0, 20, 30)));
        Assert.Equal(TextOutput.Allowed, session.CheckTextOutput());

        session.Annotations.Add(new MaskItem(new[] { new PointF(5, 5) }, AnnotationStyle.Default(AnnotationKind.Mask),
            MaskEffect.Solid, new RectF(0, 0, 30, 30)));

        Assert.Equal(TextOutput.Stale, session.CheckTextOutput());
        Assert.Single(session.OpaqueMasks);
    }

    [Fact]
    public void CropShrinksTheImageAndKeepsCoordinatesConsistent()
    {
        var session = NewSession();
        session.Annotations.Add(new RectItem(new RectF(120, 20, 30, 30), AnnotationStyle.Default(AnnotationKind.Rect)));
        session.ApplyCrop(new RectI(100, 10, 80, 60));

        Assert.Equal(80, session.Image.Width);
        Assert.Equal(60, session.Image.Height);
        var item = Assert.Single(session.Annotations.Items);
        Assert.Equal(20f, item.Bounds.X, 2);
        Assert.Equal(10f, item.Bounds.Y, 2);
    }

    [Fact]
    public void FailureIsReportedInsteadOfFallingBackToOldText()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        session.FailOcr(request, "模型缺失");
        Assert.Equal(TextOutput.Failed, session.CheckTextOutput());
        Assert.Equal("模型缺失", session.FailureReason);
    }

    [Fact]
    public void MaskFilterRemovesOnlyCoveredGlyphs()
    {
        var page = FakeOcr.Line("一行六个字", 0, 0, 20, 30);
        var (filtered, removed) = OcrPrivacyFilter.RemoveGlyphsUnder(page, new[] { new RectF(40, 0, 25, 30) });

        Assert.Equal(2, removed);
        Assert.Equal("一行字", filtered.ToPlainText());
        Assert.Single(filtered.Lines);
    }

    [Fact]
    public void MaskFilterWithoutMasksReturnsInput()
    {
        var page = FakeOcr.Line("文字", 0, 0, 20, 30);
        var (filtered, removed) = OcrPrivacyFilter.RemoveGlyphsUnder(page, Array.Empty<RectF>());
        Assert.Equal(0, removed);
        Assert.Same(page, filtered);
    }
}
