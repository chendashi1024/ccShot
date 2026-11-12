using System;
using System.Collections.Generic;
using System.Linq;
using ccShot.Core.Annotate;
using ccShot.Core.Geometry;
using ccShot.Core.Imaging;
using ccShot.Core.Ocr;

namespace ccShot.Core.Session;

public enum OcrState
{
    None,
    Pending,
    Ready,
    Failed,
    Invalidated,
}

public enum TextOutput
{
    /// <summary>Recognized text matches the current image revision and can be copied.</summary>
    Allowed,

    /// <summary>Recognition still running; the caller should wait or offer the image instead.</summary>
    Pending,

    /// <summary>No text was found. Copy must not clear the clipboard silently.</summary>
    NoText,

    /// <summary>Recognition failed; only the image may be exported.</summary>
    Failed,

    /// <summary>The image changed (crop, mask, new image) and the old text must not be exposed.</summary>
    Stale,
}

/// <summary>
/// One capture session: the current (possibly cropped) image, its annotations and its recognition state.
/// Everything asynchronous is bound to <see cref="Revision"/>; a result computed for an older revision is
/// rejected instead of being shown on the new image.
/// </summary>
public sealed class CaptureSession
{
    private readonly object _gate = new();
    private OcrPage? _ocr;
    private int _ocrRevision = -1;
    private int _pendingRequest = -1;
    private int _lastRequest;
    private OcrState _state = OcrState.None;
    private string? _failureReason;
    private string _redactionSignature = string.Empty;

    public CaptureSession(PixelImage image) : this(image, new AnnotationDocument()) { }

    private CaptureSession(PixelImage image, AnnotationDocument annotations)
    {
        Id = Guid.NewGuid();
        Image = image;
        Annotations = annotations;
        _redactionSignature = RedactionSignature();
        Annotations.Changed += (_, _) => OnImageChanged();
    }

    public Guid Id { get; }
    public PixelImage Image { get; private set; }
    public AnnotationDocument Annotations { get; }

    public CaptureSession CreateIndependentCopy() => new(Image, Annotations.CreateIndependentCopy());

    /// <summary>Any committed change (annotation, crop, image swap). Used for UI refreshes.</summary>
    public int Revision { get; private set; }

    /// <summary>裁剪、换图和遮挡使用独立版本，普通标注不打断识字。</summary>
    public int ImageRevision { get; private set; }

    public OcrState OcrState
    {
        get { lock (_gate) return _state; }
    }

    public string? FailureReason
    {
        get { lock (_gate) return _failureReason; }
    }

    public OcrPage? OcrPage
    {
        get { lock (_gate) return _ocr; }
    }

    /// <summary>遮挡变化立即丢弃旧文字和识别请求。</summary>
    private void OnImageChanged()
    {
        Revision++;
        string signature = RedactionSignature();
        if (signature == _redactionSignature) return;
        _redactionSignature = signature;
        ImageRevision++;
        Invalidate(OcrState.Invalidated, "遮挡后需要重新识别");
    }

    private string RedactionSignature()
    {
        var parts = new List<string>();
        foreach (var item in Annotations.Items)
        {
            if (item is MaskItem mask)
                parts.Add($"mask:{mask.Effect}:{mask.EffectiveBounds}:{mask.Style}:{string.Join(",", mask.Points)}");
            else if (item is TextItem text && text.HasBackground)
                parts.Add($"textbg:{text.Bounds}");
        }

        return string.Join("|", parts);
    }

    /// <summary>Replaces the visible image after a crop and discards every result bound to the old pixels.</summary>
    public void ApplyCrop(RectI crop)
    {
        var clipped = crop.Intersect(Image.BoundsRect);
        if (clipped.IsEmpty || clipped == Image.BoundsRect) return;
        Image = Image.Crop(clipped);
        Annotations.ApplyCrop(new RectI(0, 0, Image.Width, Image.Height), clipped.X, clipped.Y);
        Revision++;
        ImageRevision++;
        Invalidate(OcrState.Invalidated, "裁剪后需要重新识别");
    }

    public void ReplaceImage(PixelImage image)
    {
        Image = image;
        Annotations.Clear();
        Revision++;
        ImageRevision++;
        Invalidate(OcrState.Invalidated, "已更换图片");
    }

    public void Invalidate(OcrState state, string reason)
    {
        lock (_gate)
        {
            _state = state;
            _failureReason = reason;
            _ocr = null;
            _ocrRevision = -1;
            _pendingRequest = -1;
        }
    }

    public int BeginOcr()
    {
        lock (_gate)
        {
            _lastRequest++;
            _pendingRequest = _lastRequest;
            _state = OcrState.Pending;
            _failureReason = null;
            return _lastRequest;
        }
    }

    /// <summary>Accepts a result only when both the request and the image revision still match.</summary>
    public bool TryCompleteOcr(int requestId, int imageRevision, OcrPage page)
    {
        lock (_gate)
        {
            if (requestId != _pendingRequest || imageRevision != ImageRevision) return false;
            _ocr = page;
            _ocrRevision = imageRevision;
            _pendingRequest = -1;
            _state = OcrState.Ready;
            return true;
        }
    }

    public void FailOcr(int requestId, string reason)
    {
        lock (_gate)
        {
            if (requestId != _pendingRequest) return;
            _pendingRequest = -1;
            _state = OcrState.Failed;
            _failureReason = reason;
        }
    }

    public TextOutput CheckTextOutput()
    {
        lock (_gate)
        {
            if (_state == OcrState.Pending) return TextOutput.Pending;
            if (_state == OcrState.Failed) return TextOutput.Failed;
            if (_ocr == null || _ocrRevision != ImageRevision || _state != OcrState.Ready) return TextOutput.Stale;
            if (!_ocr.HasText) return TextOutput.NoText;
            return TextOutput.Allowed;
        }
    }

    /// <summary>所有遮挡都阻止对应原文复制，笔刷使用保守的外接边界。</summary>
    public IReadOnlyList<RectF> ObscuredTextRects => Annotations.Items
        .Where(item => item is MaskItem or TextItem { HasBackground: true })
        .Select(item => item is MaskItem ? item.EffectiveBounds : item.Bounds.Inflate(4f))
        .ToList();
}

/// <summary>
/// Removes recognized characters whose box lies under an opaque mask. Used when a mask is added and the
/// platform re-runs recognition on the composite image; also the last line of defence if a stale page
/// somehow reaches the clipboard.
/// </summary>
public static class OcrPrivacyFilter
{
    public static (OcrPage Page, int RemovedGlyphs) RemoveGlyphsUnder(OcrPage page, IReadOnlyList<RectF> opaqueRects)
    {
        if (opaqueRects.Count == 0 || page.Lines.Count == 0) return (page, 0);
        int removed = 0;
        var lines = new List<OcrLine>(page.Lines.Count);
        foreach (var line in page.Lines)
        {
            var kept = new List<OcrGlyph>(line.Glyphs.Count);
            foreach (var glyph in line.Glyphs)
            {
                bool hidden = opaqueRects.Any(r => r.IntersectsWith(glyph.Box));
                if (hidden) removed++;
                else kept.Add(glyph);
            }

            if (kept.Count == 0) continue;
            var box = kept.Aggregate(kept[0].Box, (acc, g) => acc.Union(g.Box));
            lines.Add(new OcrLine(string.Concat(kept.Select(g => g.Text)), box, kept, line.Score));
        }

        return (new OcrPage(lines, page.ImageWidth, page.ImageHeight, page.Engine, page.Timing), removed);
    }
}
