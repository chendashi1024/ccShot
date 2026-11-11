using System;
using System.Collections.Generic;
using System.Linq;
using CcShot.Core.Geometry;

namespace CcShot.Core.Annotate;

/// <summary>
/// Ordered annotation list with per-tool styles and gesture-level undo/redo. One committed gesture
/// (a stroke, a drag, a resize) is exactly one undo step; a slider drag is one step as well.
/// </summary>
public sealed class AnnotationDocument
{
    private readonly List<AnnotationItem> _items = new();
    private readonly Dictionary<AnnotationKind, AnnotationStyle> _styles = new();
    private readonly List<(List<AnnotationItem> Before, List<AnnotationItem> After)> _history = new();
    private int _historyIndex;
    private List<AnnotationItem>? _pendingBefore;
    private int _revision;
    private int _nextNumber = 1;

    public event EventHandler? Changed;

    public AnnotationDocument()
    {
        foreach (AnnotationKind kind in Enum.GetValues<AnnotationKind>())
            _styles[kind] = AnnotationStyle.Default(kind);
    }

    internal AnnotationDocument CreateIndependentCopy()
    {
        var copy = new AnnotationDocument();
        copy._items.AddRange(Snapshot());
        foreach (var (kind, style) in _styles) copy._styles[kind] = style;
        copy._nextNumber = _nextNumber;
        return copy;
    }

    public IReadOnlyList<AnnotationItem> Items => _items;
    public int Revision => _revision;
    public int NextNumber => _nextNumber;
    public bool CanUndo => _historyIndex > 0;
    public bool CanRedo => _historyIndex < _history.Count;

    public AnnotationStyle StyleFor(AnnotationKind kind) => _styles[kind];

    public void SetStyle(AnnotationKind kind, AnnotationStyle style) => _styles[kind] = style;

    public T Add<T>(T item) where T : AnnotationItem
    {
        BeginTransaction($"add:{item.Kind}");
        _items.Add(item);
        if (item is NumberItem number)
        {
            number.Number = _nextNumber;
            _nextNumber++;
        }

        CommitTransaction();
        return item;
    }

    public bool Remove(AnnotationItem item)
    {
        if (!_items.Contains(item)) return false;
        BeginTransaction("remove");
        _items.Remove(item);
        CommitTransaction();
        return true;
    }

    public AnnotationItem? HitTest(PointF point, float tolerance = 4f)
    {
        for (int i = _items.Count - 1; i >= 0; i--)
        {
            if (_items[i].HitTest(point, tolerance)) return _items[i];
        }

        return null;
    }

    public void Clear()
    {
        if (_items.Count == 0) return;
        BeginTransaction("clear");
        _items.Clear();
        CommitTransaction();
    }

    /// <summary>
    /// Starts a gesture. Calling it twice without committing keeps the first snapshot, so nested calls
    /// from slider handling cannot split one gesture into several undo steps.
    /// </summary>
    public void BeginTransaction(string name)
    {
        _pendingBefore ??= Snapshot();
    }

    public void MarkChanged()
    {
        _revision++;
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void CommitTransaction()
    {
        if (_pendingBefore == null) return;
        var after = Snapshot();
        if (!SameContent(_pendingBefore, after))
        {
            _history.RemoveRange(_historyIndex, _history.Count - _historyIndex);
            _history.Add((_pendingBefore, after));
            _historyIndex = _history.Count;
        }

        _pendingBefore = null;
        MarkChanged();
    }

    public void CancelTransaction()
    {
        if (_pendingBefore == null) return;
        Restore(_pendingBefore);
        _pendingBefore = null;
        MarkChanged();
    }

    public void Undo()
    {
        if (!CanUndo) return;
        _historyIndex--;
        Restore(_history[_historyIndex].Before);
        MarkChanged();
    }

    public void Redo()
    {
        if (!CanRedo) return;
        Restore(_history[_historyIndex].After);
        _historyIndex++;
        MarkChanged();
    }

    private List<AnnotationItem> Snapshot() => _items.Select(i => i.Clone()).ToList();

    private void Restore(List<AnnotationItem> snapshot)
    {
        _items.Clear();
        _items.AddRange(snapshot.Select(i => i.Clone()));
        _nextNumber = _items.OfType<NumberItem>().Select(n => n.Number).DefaultIfEmpty(0).Max() + 1;
    }

    private static bool SameContent(List<AnnotationItem> a, List<AnnotationItem> b)
    {
        if (a.Count != b.Count) return false;
        for (int i = 0; i < a.Count; i++)
        {
            if (a[i].Id != b[i].Id) return false;
            if (a[i].Kind != b[i].Kind) return false;
            if (a[i].Bounds != b[i].Bounds) return false;
            if (a[i].Style != b[i].Style) return false;
            if (a[i] is TextItem ta && b[i] is TextItem tb && ta.Text != tb.Text) return false;
            if (a[i] is MaskItem ma && b[i] is MaskItem mb && ma.Effect != mb.Effect) return false;
            if (a[i] is ArrowItem aa && b[i] is ArrowItem ab && aa.Curve != ab.Curve) return false;
            if (a[i] is PenItem pa && b[i] is PenItem pb && pa.Points.Count != pb.Points.Count) return false;
        }

        return true;
    }

    /// <summary>Masks that truly replace the pixels underneath; only these may invalidate recognized text.</summary>
    public IReadOnlyList<RectF> OpaqueMaskRects() =>
        _items.OfType<MaskItem>().Where(m => m.IsOpaqueRedaction).Select(m => m.EffectiveBounds).ToList();

    /// <summary>Union of all annotation bounds, used to decide whether a crop clipped any annotation.</summary>
    public RectF ContentBounds()
    {
        var box = new RectF(0, 0, 0, 0);
        foreach (var item in _items) box = box.Union(item.EffectiveBounds);
        return box;
    }

    /// <summary>Drops annotations and points that fall outside a crop and shifts the rest into the new origin.</summary>
    public void ApplyCrop(RectI crop, int offsetX, int offsetY)
    {
        BeginTransaction("crop");
        var kept = new List<AnnotationItem>();
        foreach (var item in _items)
        {
            var shifted = item.Clone();
            shifted.Move(-offsetX, -offsetY);
            if (!shifted.EffectiveBounds.IntersectsWith(crop.ToRectF())) continue;
            kept.Add(shifted);
        }

        _items.Clear();
        _items.AddRange(kept);
        CommitTransaction();
    }
}
