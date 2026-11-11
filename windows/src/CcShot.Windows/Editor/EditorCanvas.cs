using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CcShot.Core.Annotate;
using CcShot.Core.Geometry;
using CcShot.Core.Imaging;
using CcShot.Core.Ocr.Selection;
using CcShot.Core.Session;
using CcShot.Windows.Rendering;
using CcShot.Windows.Theme;

namespace CcShot.Windows.Editor;

internal enum EditorTool
{
    Select,
    Arrow,
    Rect,
    Ellipse,
    Pen,
    Highlight,
    MaskRect,
    MaskBrush,
    Text,
    Number,
}

/// <summary>
/// The image surface: draws the screenshot, the annotations and the recognized text, and turns pointer
/// input into either a text selection or an annotation gesture. Priority is explicit: when a tool is
/// active the text layer does not take the pointer, and in select mode a pointer over recognized text
/// selects text instead of starting a drawing gesture.
/// </summary>
internal sealed class EditorCanvas : FrameworkElement
{
    private enum Gesture
    {
        None,
        TextDrag,
        Draw,
        Move,
        Resize,
    }

    private readonly CaptureSession _session;
    private readonly BitmapSource _bitmap;
    private readonly MaskImages _masks;

    private TextSelectionModel? _textModel;
    private TextSelection _selection = TextSelection.Empty;
    private Caret _caretAnchor;
    private AnnotationItem? _selectedItem;
    private EditorTool _tool = EditorTool.Select;

    private Gesture _gesture;
    private PointF _gestureStart;
    private PointF _gestureCurrent;
    private readonly List<PointF> _points = new();
    private AnnotationItem? _pendingItem;
    private int _handleIndex = -1;
    private float _arrowCurve;

    public EditorCanvas(CaptureSession session)
    {
        _session = session;
        _bitmap = BitmapInterop.ToBitmapSource(session.Image);
        _masks = ImageCompositor.BuildMaskImages(session.Image);
        Focusable = true;
        ClipToBounds = true;
        SnapsToDevicePixels = true;
        Cursor = Cursors.Cross;
        session.Annotations.Changed += (_, _) =>
        {
            if (!ReferenceEquals(_selectedItem, null) && !session.Annotations.Items.Contains(_selectedItem)) _selectedItem = null;
            InvalidateVisual();
            DocumentChanged?.Invoke(this, EventArgs.Empty);
        };
    }

    public CaptureSession Session => _session;
    public AnnotationDocument Document => _session.Annotations;

    /// <summary>Device-independent units per image pixel, taken from the monitor DPI.</summary>
    public double DipPerPixel { get; set; } = 1.0;

    public EditorTool Tool
    {
        get => _tool;
        set
        {
            _tool = value;
            if (value != EditorTool.Select) ClearTextSelection();
            Cursor = value == EditorTool.Select ? Cursors.IBeam : Cursors.Cross;
            InvalidateVisual();
            ToolChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public AnnotationStyle ActiveStyle => Document.StyleFor(KindOf(_tool));

    public event EventHandler? DocumentChanged;
    public event EventHandler? ToolChanged;
    public event EventHandler? SelectionChanged;
    public event EventHandler<PointF>? TextEditRequested;

    public bool HasTextSelection => !_selection.IsEmpty;
    public string SelectedText => _textModel == null ? string.Empty : _textModel.Text(_selection);
    public AnnotationItem? SelectedItem => _selectedItem;

    public static AnnotationKind KindOf(EditorTool tool) => tool switch
    {
        EditorTool.Arrow => AnnotationKind.Arrow,
        EditorTool.Rect => AnnotationKind.Rect,
        EditorTool.Ellipse => AnnotationKind.Ellipse,
        EditorTool.Pen => AnnotationKind.Pen,
        EditorTool.Highlight => AnnotationKind.Highlight,
        EditorTool.MaskRect or EditorTool.MaskBrush => AnnotationKind.Mask,
        EditorTool.Text => AnnotationKind.Text,
        EditorTool.Number => AnnotationKind.Number,
        _ => AnnotationKind.Rect,
    };

    public void SetTextModel(TextSelectionModel? model)
    {
        _textModel = model;
        _selection = TextSelection.Empty;
        InvalidateVisual();
        SelectionChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ClearTextSelection()
    {
        if (_selection.IsEmpty) return;
        _selection = TextSelection.Empty;
        InvalidateVisual();
        SelectionChanged?.Invoke(this, EventArgs.Empty);
    }

    public void SelectAllText()
    {
        if (_textModel == null) return;
        _selection = _textModel.SelectAll();
        InvalidateVisual();
        SelectionChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Undo()
    {
        Document.Undo();
        InvalidateVisual();
    }

    public void Redo()
    {
        Document.Redo();
        InvalidateVisual();
    }

    public void DeleteSelected()
    {
        if (_selectedItem == null) return;
        Document.Remove(_selectedItem);
        _selectedItem = null;
        InvalidateVisual();
    }

    public void SetStyle(AnnotationStyle style)
    {
        var kind = _selectedItem?.Kind ?? KindOf(_tool);
        Document.SetStyle(kind, style);
        if (_selectedItem != null)
        {
            // Style changes are not undo steps; they only affect the selected object and future draws.
            _selectedItem.Style = style;
            Document.MarkChanged();
        }

        InvalidateVisual();
    }

    public void CommitText(string text, PointF origin)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        var style = Document.StyleFor(AnnotationKind.Text);
        var size = AnnotationRenderer.MeasureText(text, style, 1.0);
        var item = new TextItem(text, origin, style, new RectF(origin.X, origin.Y, (float)size.Width, (float)size.Height));
        Document.Add(item);
        _selectedItem = item;
        InvalidateVisual();
    }

    private PointF ToImage(Point point) => new((float)(point.X / DipPerPixel), (float)(point.Y / DipPerPixel));
    private Point ToDip(PointF point) => new(point.X * DipPerPixel, point.Y * DipPerPixel);
    private Rect ToDip(RectF rect) => new(rect.X * DipPerPixel, rect.Y * DipPerPixel, Math.Max(1, rect.Width * DipPerPixel), Math.Max(1, rect.Height * DipPerPixel));

    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawImage(_bitmap, new Rect(0, 0, ActualWidth, ActualHeight));

        foreach (var item in Document.Items) AnnotationRenderer.Draw(dc, item, DipPerPixel, _masks);
        if (_pendingItem != null) AnnotationRenderer.Draw(dc, _pendingItem, DipPerPixel, _masks);

        if (!_selection.IsEmpty && _textModel != null)
        {
            foreach (var (box, _) in _textModel.HighlightRects(_selection))
                dc.DrawRectangle(Palette.SelectionBrush, null, ToDip(box));
        }

        if (_selectedItem != null)
        {
            var bounds = ToDip(_selectedItem.EffectiveBounds);
            var pen = new Pen(Palette.AccentSoftBrush, 1.2) { DashStyle = new DashStyle(new double[] { 4, 3 }, 0) };
            pen.Freeze();
            dc.DrawRectangle(null, pen, bounds);
            foreach (var handle in HandleRects(_selectedItem.EffectiveBounds))
            {
                var rect = new Rect(handle.X - 4, handle.Y - 4, 8, 8);
                dc.DrawRectangle(Palette.WhiteBrush, new Pen(Palette.AccentBrush, 1.2), rect);
            }
        }
    }

    private IEnumerable<Point> HandleRects(RectF bounds)
    {
        yield return ToDip(new PointF(bounds.X, bounds.Y));
        yield return ToDip(new PointF(bounds.Right, bounds.Y));
        yield return ToDip(new PointF(bounds.X, bounds.Bottom));
        yield return ToDip(new PointF(bounds.Right, bounds.Bottom));
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        Focus();
        var point = ToImage(e.GetPosition(this));
        _gestureStart = _gestureCurrent = point;
        _points.Clear();

        if (_tool == EditorTool.Select)
        {
            if (_textModel != null && (_selection.IsEmpty || !_selection.IsEmpty) && PointOnText(point))
            {
                _gesture = Gesture.TextDrag;
                _caretAnchor = _textModel.CaretAt(point);
                _selection = TextSelection.Empty;
                CaptureMouse();
                InvalidateVisual();
                return;
            }

            if (_selectedItem != null)
            {
                int handle = HitHandle(point);
                if (handle >= 0)
                {
                    _gesture = Gesture.Resize;
                    _handleIndex = handle;
                    Document.BeginTransaction("resize");
                    CaptureMouse();
                    return;
                }
            }

            var hit = Document.HitTest(point, (float)(6 / DipPerPixel));
            _selectedItem = hit;
            if (hit != null)
            {
                _gesture = Gesture.Move;
                Document.BeginTransaction("move");
                CaptureMouse();
            }
            else
            {
                ClearTextSelection();
            }

            InvalidateVisual();
            return;
        }

        if (_tool == EditorTool.Text)
        {
            TextEditRequested?.Invoke(this, point);
            return;
        }

        if (_tool == EditorTool.Number)
        {
            var number = new NumberItem(0, point, Document.StyleFor(AnnotationKind.Number));
            Document.Add(number);
            _selectedItem = number;
            InvalidateVisual();
            return;
        }

        _gesture = Gesture.Draw;
        _pendingItem = CreatePendingItem(point);
        CaptureMouse();
    }

    private bool PointOnText(PointF point)
    {
        if (_textModel == null || _textModel.Page.Lines.Count == 0) return false;
        foreach (var line in _textModel.Page.Lines)
        {
            if (line.Box.Inflate(2).Contains(point)) return true;
        }

        return false;
    }

    private AnnotationItem? CreatePendingItem(PointF point)
    {
        var style = Document.StyleFor(KindOf(_tool));
        return _tool switch
        {
            EditorTool.Arrow => new ArrowItem(point, point, style),
            EditorTool.Rect => new RectItem(new RectF(point.X, point.Y, 0, 0), style),
            EditorTool.Ellipse => new RectItem(new RectF(point.X, point.Y, 0, 0), style, ellipse: true),
            EditorTool.Pen => new PenItem(new List<PointF> { point }, style),
            EditorTool.Highlight => new PenItem(new List<PointF> { point }, style, highlight: true),
            EditorTool.MaskRect => new MaskItem(new List<PointF>(), style, _activeMaskEffect, new RectF(point.X, point.Y, 0, 0)),
            EditorTool.MaskBrush => new MaskItem(new List<PointF> { point }, style, _activeMaskEffect),
            _ => null,
        };
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var point = ToImage(e.GetPosition(this));
        if (_gesture == Gesture.None) return;
        _gestureCurrent = point;

        switch (_gesture)
        {
            case Gesture.TextDrag:
                if (_textModel != null) _selection = _textModel.Select(_gestureStart, point);
                SelectionChanged?.Invoke(this, EventArgs.Empty);
                InvalidateVisual();
                break;
            case Gesture.Draw when _pendingItem != null:
                UpdatePending(point);
                InvalidateVisual();
                break;
            case Gesture.Move when _selectedItem != null:
                float dx = point.X - _gestureStart.X, dy = point.Y - _gestureStart.Y;
                if (MathF.Abs(dx) + MathF.Abs(dy) > 0)
                {
                    _selectedItem.Move(dx, dy);
                    _gestureStart = point;
                    Document.MarkChanged();
                    InvalidateVisual();
                }

                break;
            case Gesture.Resize when _selectedItem != null:
                ResizeSelected(point);
                InvalidateVisual();
                break;
        }
    }

    private void UpdatePending(PointF point)
    {
        switch (_pendingItem)
        {
            case ArrowItem arrow:
                arrow.SetEndpoints(_gestureStart, point);
                break;
            case RectItem rect:
                rect.SetBounds(RectF.FromPoints(_gestureStart, point));
                break;
            case PenItem pen:
                pen.Points.Add(point);
                break;
            case MaskItem mask when mask.FillRect.HasValue:
                mask.SetBounds(RectF.FromPoints(_gestureStart, point));
                break;
            case MaskItem mask:
                mask.Points.Add(point);
                break;
        }
    }

    private void ResizeSelected(PointF point)
    {
        if (_selectedItem == null) return;
        var bounds = _selectedItem.EffectiveBounds;
        float left = bounds.X, top = bounds.Y, right = bounds.Right, bottom = bounds.Bottom;
        switch (_handleIndex)
        {
            case 0: left = point.X; top = point.Y; break;
            case 1: right = point.X; top = point.Y; break;
            case 2: left = point.X; bottom = point.Y; break;
            case 3: right = point.X; bottom = point.Y; break;
        }

        var target = RectF.FromEdges(MathF.Min(left, right), MathF.Min(top, bottom), MathF.Max(left, right), MathF.Max(top, bottom));
        if (target.Width < 2 || target.Height < 2) return;
        _selectedItem.SetBounds(target);
        Document.MarkChanged();
    }

    private int HitHandle(PointF point)
    {
        if (_selectedItem == null) return -1;
        var bounds = _selectedItem.EffectiveBounds;
        var corners = new[]
        {
            new PointF(bounds.X, bounds.Y), new PointF(bounds.Right, bounds.Y),
            new PointF(bounds.X, bounds.Bottom), new PointF(bounds.Right, bounds.Bottom),
        };
        float radius = (float)(8 / DipPerPixel);
        for (int i = 0; i < corners.Length; i++)
        {
            if (MathF.Abs(corners[i].X - point.X) <= radius && MathF.Abs(corners[i].Y - point.Y) <= radius) return i;
        }

        return -1;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        if (_gesture == Gesture.None) return;

        switch (_gesture)
        {
            case Gesture.Draw:
                if (_pendingItem != null && IsMeaningful(_pendingItem))
                {
                    var item = _pendingItem;
                    _pendingItem = null;
                    Document.Add(item);
                    _selectedItem = item;
                }
                else
                {
                    _pendingItem = null;
                }

                break;
            case Gesture.Move:
            case Gesture.Resize:
                Document.CommitTransaction();
                break;
            case Gesture.TextDrag:
                if (_selection.IsEmpty) ClearTextSelection();
                break;
        }

        _gesture = Gesture.None;
        _handleIndex = -1;
        ReleaseMouseCapture();
        InvalidateVisual();
        DocumentChanged?.Invoke(this, EventArgs.Empty);
    }

    private static bool IsMeaningful(AnnotationItem item) => item switch
    {
        ArrowItem arrow => Math.Abs(arrow.End.X - arrow.Start.X) + Math.Abs(arrow.End.Y - arrow.Start.Y) > 3,
        RectItem rect => rect.Rect.Width > 2 && rect.Rect.Height > 2,
        PenItem pen => pen.Points.Count > 1,
        MaskItem mask => mask.FillRect?.Width > 2 || mask.Points.Count > 1,
        _ => true,
    };

    /// <summary>Arrow bend: dragging the middle control point while an arrow is selected.</summary>
    public bool TryBendArrow(PointF point)
    {
        if (_selectedItem is not ArrowItem arrow) return false;
        var control = arrow.ControlPoint;
        if (MathF.Abs(control.X - point.X) > 12 / DipPerPixel || MathF.Abs(control.Y - point.Y) > 12 / DipPerPixel) return false;
        Document.BeginTransaction("bend");
        var mid = new PointF((arrow.Start.X + arrow.End.X) / 2, (arrow.Start.Y + arrow.End.Y) / 2);
        float dx = arrow.End.X - arrow.Start.X, dy = arrow.End.Y - arrow.Start.Y;
        float length = MathF.Sqrt(dx * dx + dy * dy);
        if (length < 0.01f) return false;
        // Project the pointer onto the shaft normal to obtain the curve amount.
        float nx = -dy / length, ny = dx / length;
        _arrowCurve = (point.X - mid.X) * nx + (point.Y - mid.Y) * ny;
        arrow.Curve = _arrowCurve;
        Document.CommitTransaction();
        InvalidateVisual();
        return true;
    }

    public void SetMaskEffect(MaskEffect effect)
    {
        var style = Document.StyleFor(AnnotationKind.Mask);
        Document.SetStyle(AnnotationKind.Mask, style);
        if (_selectedItem is MaskItem mask)
        {
            Document.BeginTransaction("mask-effect");
            mask.Effect = effect;
            Document.CommitTransaction();
        }

        _activeMaskEffect = effect;
        InvalidateVisual();
    }

    private MaskEffect _activeMaskEffect = MaskEffect.Solid;
    public MaskEffect ActiveMaskEffect => _activeMaskEffect;

    public PixelImage CurrentImage => _session.Image;
}
