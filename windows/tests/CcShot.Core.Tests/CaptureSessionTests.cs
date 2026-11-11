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
        int revision = session.ImageRevision;

        session.ApplyCrop(new RectI(0, 0, 100, 100));
        Assert.True(session.ImageRevision > revision);

        var page = FakeOcr.Line("文字", 0, 0, 20, 30);
        Assert.False(session.TryCompleteOcr(request, revision, page));
        Assert.NotEqual(TextOutput.Allowed, session.CheckTextOutput());
    }

    [Fact]
    public void LateResultAfterCancelIsIgnored()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        int revision = session.ImageRevision;

        session.Invalidate(OcrState.Invalidated, "用户取消");
        Assert.False(session.TryCompleteOcr(request, revision, FakeOcr.Line("文字", 0, 0, 20, 30)));
        Assert.Equal(TextOutput.Stale, session.CheckTextOutput());
    }

    [Fact]
    public void FreshResultIsAllowed()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        int revision = session.ImageRevision;
        Assert.True(session.TryCompleteOcr(request, revision, FakeOcr.Line("文字", 0, 0, 20, 30)));
        Assert.Equal(TextOutput.Allowed, session.CheckTextOutput());
    }

    [Fact]
    public void EmptyRecognitionIsReportedAsNoTextNotSuccess()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        Assert.True(session.TryCompleteOcr(request, session.ImageRevision, OcrPage.Empty));
        Assert.Equal(TextOutput.NoText, session.CheckTextOutput());
    }

    [Theory]
    [InlineData(MaskEffect.Solid)]
    [InlineData(MaskEffect.Mosaic)]
    [InlineData(MaskEffect.Blur)]
    public void AddingAnyMaskInvalidatesRecognizedText(MaskEffect effect)
    {
        var session = NewSession();
        int request = session.BeginOcr();
        Assert.True(session.TryCompleteOcr(request, session.ImageRevision, FakeOcr.Line("文字", 0, 0, 20, 30)));
        Assert.Equal(TextOutput.Allowed, session.CheckTextOutput());

        session.Annotations.Add(new MaskItem(new[] { new PointF(5, 5) }, AnnotationStyle.Default(AnnotationKind.Mask),
            effect, new RectF(0, 0, 30, 30)));

        Assert.Equal(TextOutput.Stale, session.CheckTextOutput());
        Assert.Null(session.OcrPage);
    }

    [Fact]
    public void AResultInFlightCannotBeCopiedAfterMasking()
    {
        var session = NewSession();
        int revision = session.ImageRevision;
        int request = session.BeginOcr();

        session.Annotations.Add(new MaskItem(new[] { new PointF(5, 5) }, AnnotationStyle.Default(AnnotationKind.Mask),
            MaskEffect.Blur, new RectF(0, 0, 30, 30)));

        Assert.Equal(TextOutput.Stale, session.CheckTextOutput());
        Assert.False(session.TryCompleteOcr(request, revision, FakeOcr.Line("文字", 0, 0, 20, 30)));
    }

    [Fact]
    public void DrawingAnArrowKeepsRecognizedTextUsable()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        Assert.True(session.TryCompleteOcr(request, session.ImageRevision, FakeOcr.Line("文字", 0, 0, 20, 30)));

        session.Annotations.Add(new ArrowItem(new PointF(5, 5), new PointF(40, 40), AnnotationStyle.Default(AnnotationKind.Arrow)));

        Assert.Equal(TextOutput.Allowed, session.CheckTextOutput());
        Assert.Empty(session.ObscuredTextRects);
    }

    [Fact]
    public void PinCopyKeepsEditableAnnotationsWithoutSharingOcrOrEdits()
    {
        var session = NewSession();
        var original = session.Annotations.Add(new RectItem(new RectF(5, 5, 20, 20), AnnotationStyle.Default(AnnotationKind.Rect)));
        int request = session.BeginOcr();
        Assert.True(session.TryCompleteOcr(request, session.ImageRevision, FakeOcr.Line("文字", 0, 0, 20, 30)));

        var pin = session.CreateIndependentCopy();
        var copied = Assert.Single(pin.Annotations.Items);
        copied.Move(10, 0);

        Assert.Equal(5, original.Bounds.X);
        Assert.Equal(15, copied.Bounds.X);
        Assert.Null(pin.OcrPage);
    }

    [Fact]
    public void RemovingTheMaskDoesNotReviveOldText()
    {
        var session = NewSession();
        int request = session.BeginOcr();
        Assert.True(session.TryCompleteOcr(request, session.ImageRevision, FakeOcr.Line("文字", 0, 0, 20, 30)));

        var mask = session.Annotations.Add(new MaskItem(new[] { new PointF(5, 5) }, AnnotationStyle.Default(AnnotationKind.Mask),
            MaskEffect.Solid, new RectF(0, 0, 30, 30)));
        Assert.Equal(TextOutput.Stale, session.CheckTextOutput());

        session.Annotations.Remove(mask);
        // Removing the mask changes the picture again; the old page must stay retired until re-recognition.
        Assert.Equal(TextOutput.Stale, session.CheckTextOutput());
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
