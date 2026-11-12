using System.Linq;
using ccShot.Core.Annotate;
using ccShot.Core.Geometry;
using Xunit;

namespace ccShot.Core.Tests;

public class AnnotationDocumentTests
{
    private static AnnotationDocument NewDocument() => new();

    [Fact]
    public void AddAndUndoRestoreTheDocument()
    {
        var doc = NewDocument();
        doc.Add(new RectItem(new RectF(10, 10, 100, 50), AnnotationStyle.Default(AnnotationKind.Rect)));
        Assert.Single(doc.Items);
        Assert.True(doc.CanUndo);

        doc.Undo();
        Assert.Empty(doc.Items);
        Assert.True(doc.CanRedo);

        doc.Redo();
        Assert.Single(doc.Items);
    }

    [Fact]
    public void OneGestureIsOneUndoStep()
    {
        var doc = NewDocument();
        var arrow = doc.Add(new ArrowItem(new PointF(0, 0), new PointF(50, 50), AnnotationStyle.Default(AnnotationKind.Arrow)));
        int undoDepth = 0;

        doc.BeginTransaction("drag");
        doc.BeginTransaction("drag");
        arrow.Move(10, 5);
        arrow.Move(10, 5);
        doc.CommitTransaction();
        undoDepth++;

        doc.Undo();
        var restored = Assert.IsType<ArrowItem>(doc.Items.Single());
        Assert.Equal(new PointF(0, 0), restored.Start);
        Assert.Equal(1, undoDepth);
    }

    [Fact]
    public void CancelTransactionRestoresTheStartingGeometry()
    {
        var doc = NewDocument();
        var rect = doc.Add(new RectItem(new RectF(0, 0, 40, 40), AnnotationStyle.Default(AnnotationKind.Rect)));
        doc.BeginTransaction("resize");
        rect.SetBounds(new RectF(0, 0, 400, 400));
        Assert.Equal(400f, doc.Items.Single().Bounds.Width);
        doc.CancelTransaction();
        Assert.Equal(40f, doc.Items.Single().Bounds.Width);
    }

    [Fact]
    public void TopmostItemWinsHitTesting()
    {
        var doc = NewDocument();
        doc.Add(new RectItem(new RectF(0, 0, 100, 100), AnnotationStyle.Default(AnnotationKind.Rect), ellipse: false));
        var arrow = doc.Add(new ArrowItem(new PointF(50, 0), new PointF(50, 100), AnnotationStyle.Default(AnnotationKind.Arrow)));
        // A point on the arrow shaft inside the rectangle must select the arrow, which is on top.
        Assert.Same(arrow, doc.HitTest(new PointF(50, 50)));
        Assert.Null(doc.HitTest(new PointF(500, 500)));
    }

    [Fact]
    public void RemovingAnItemCanBeUndone()
    {
        var doc = NewDocument();
        var item = doc.Add(new RectItem(new RectF(0, 0, 10, 10), AnnotationStyle.Default(AnnotationKind.Rect)));
        Assert.True(doc.Remove(item));
        Assert.Empty(doc.Items);
        doc.Undo();
        Assert.Single(doc.Items);
    }

    [Fact]
    public void NumbersIncreaseAndUndoRestoresTheCounter()
    {
        var doc = NewDocument();
        var first = doc.Add(new NumberItem(0, new PointF(10, 10), AnnotationStyle.Default(AnnotationKind.Number)));
        var second = doc.Add(new NumberItem(0, new PointF(40, 10), AnnotationStyle.Default(AnnotationKind.Number)));
        Assert.Equal(1, first.Number);
        Assert.Equal(2, second.Number);
        Assert.Equal(3, doc.NextNumber);

        doc.Undo();
        Assert.Equal(2, doc.NextNumber);
    }

    [Fact]
    public void OnlySolidMasksAreTreatedAsRedaction()
    {
        var doc = NewDocument();
        doc.Add(new MaskItem(new[] { new PointF(10, 10) }, AnnotationStyle.Default(AnnotationKind.Mask), MaskEffect.Solid,
            new RectF(5, 5, 50, 20)));
        doc.Add(new MaskItem(new[] { new PointF(10, 80) }, AnnotationStyle.Default(AnnotationKind.Mask), MaskEffect.Blur,
            new RectF(5, 75, 50, 20)));

        var rects = doc.OpaqueMaskRects();
        Assert.Single(rects);
        Assert.Equal(4f, rects[0].X);
    }

    [Fact]
    public void CropDropsOutsideAnnotationsAndShiftsTheRest()
    {
        var doc = NewDocument();
        doc.Add(new RectItem(new RectF(100, 100, 50, 50), AnnotationStyle.Default(AnnotationKind.Rect)));
        doc.Add(new RectItem(new RectF(500, 500, 50, 50), AnnotationStyle.Default(AnnotationKind.Rect)));

        doc.ApplyCrop(new RectI(0, 0, 300, 300), offsetX: 50, offsetY: 60);

        var remaining = Assert.Single(doc.Items);
        Assert.Equal(50f, remaining.Bounds.X, 2);
        Assert.Equal(40f, remaining.Bounds.Y, 2);
    }

    [Fact]
    public void StylesAreKeptPerTool()
    {
        var doc = NewDocument();
        var arrowStyle = doc.StyleFor(AnnotationKind.Arrow) with { Thickness = 9f };
        doc.SetStyle(AnnotationKind.Arrow, arrowStyle);
        Assert.Equal(9f, doc.StyleFor(AnnotationKind.Arrow).Thickness);
        Assert.NotEqual(9f, doc.StyleFor(AnnotationKind.Highlight).Thickness);
    }

    [Fact]
    public void ArrowCurveMovesTheControlPointAndIsClonedWithTheItem()
    {
        var arrow = new ArrowItem(new PointF(0, 0), new PointF(100, 0), AnnotationStyle.Default(AnnotationKind.Arrow), curve: 20f);
        Assert.Equal(50f, arrow.ControlPoint.X, 2);
        Assert.Equal(20f, arrow.ControlPoint.Y, 2);
        var clone = Assert.IsType<ArrowItem>(arrow.Clone());
        Assert.Equal(20f, clone.Curve);
        Assert.Equal(arrow.Id, clone.Id);
    }
}
