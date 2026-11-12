using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using ccShot.Core.Geometry;
using ccShot.Core.Imaging;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace ccShot.Core.Ocr.Paddle;

public sealed class PaddleOcrOptions
{
    /// <summary>Longest side fed to the detector; the image is scaled down to this before detection.</summary>
    public int DetLimitSide { get; set; } = 960;

    public float DetBitmapThreshold { get; set; } = 0.3f;
    public float DetBoxThreshold { get; set; } = 0.6f;
    public float UnclipRatio { get; set; } = 1.6f;
    public int MinBoxSize { get; set; } = 3;

    public int RecHeight { get; set; } = 48;
    public int RecMaxWidth { get; set; } = 1280;
    public int RecMinWidth { get; set; } = 16;

    /// <summary>0 keeps the ONNX Runtime default (one thread per physical core).</summary>
    public int Threads { get; set; }

    /// <summary>Re-inserts spaces between Latin words that the recognizer dropped.</summary>
    public bool RestoreWordSpaces { get; set; } = true;

    public float SpaceGapRatio { get; set; } = 0.3f;

    public string DetFileName { get; set; } = "det.onnx";
    public string RecFileName { get; set; } = "rec.onnx";
    public string DictFileName { get; set; } = "dict.txt";

    public string Describe() =>
        $"limit={DetLimitSide}; det_thresh={DetBitmapThreshold:0.##}/{DetBoxThreshold:0.##}; unclip={UnclipRatio:0.##}; " +
        $"rec_h={RecHeight}; rec_max_w={RecMaxWidth}; min_box={MinBoxSize}; threads={(Threads == 0 ? "auto" : Threads.ToString())}; " +
        $"restore_spaces={(RestoreWordSpaces ? SpaceGapRatio.ToString("0.##") : "off")}";
}

/// <summary>
/// PaddleOCR (PP-OCR) detection + recognition executed by ONNX Runtime on the local CPU.
/// No network, no account, no key. Models are loaded from a local directory and never downloaded implicitly.
/// </summary>
public sealed class PaddleOcrEngine : IDisposable
{
    private static readonly float[] Mean = { 0.485f, 0.456f, 0.406f };
    private static readonly float[] Std = { 0.229f, 0.224f, 0.225f };

    private readonly InferenceSession _detSession;
    private readonly InferenceSession _recSession;
    private readonly string _detInput;
    private readonly string _recInput;
    private readonly string[] _dictionary;
    private readonly PaddleOcrOptions _options;
    private readonly object _gate = new();
    private bool _disposed;

    private PaddleOcrEngine(
        InferenceSession detSession,
        InferenceSession recSession,
        string[] dictionary,
        PaddleOcrOptions options,
        OcrEngineInfo info)
    {
        _detSession = detSession;
        _recSession = recSession;
        _detInput = detSession.InputMetadata.Keys.First();
        _recInput = recSession.InputMetadata.Keys.First();
        _dictionary = dictionary;
        _options = options;
        Info = info;
    }

    public OcrEngineInfo Info { get; }

    public static PaddleOcrEngine Create(string modelDirectory, PaddleOcrOptions? options = null)
    {
        options ??= new PaddleOcrOptions();
        string detPath = Path.Combine(modelDirectory, options.DetFileName);
        string recPath = Path.Combine(modelDirectory, options.RecFileName);
        string dictPath = Path.Combine(modelDirectory, options.DictFileName);
        foreach (var path in new[] { detPath, recPath, dictPath })
        {
            if (!File.Exists(path)) throw new FileNotFoundException($"OCR model asset missing: {path}", path);
        }

        var dictionary = File.ReadAllLines(dictPath)
            .Select(l => l.TrimEnd('\r'))
            .Where(l => l.Length > 0)
            .ToArray();

        var sessionOptions = new SessionOptions
        {
            GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
            ExecutionMode = ExecutionMode.ORT_SEQUENTIAL,
        };
        if (options.Threads > 0)
        {
            sessionOptions.IntraOpNumThreads = options.Threads;
            sessionOptions.InterOpNumThreads = 1;
        }

        var det = new InferenceSession(detPath, sessionOptions);
        var rec = new InferenceSession(recPath, sessionOptions);
        var runtimeVersion = typeof(InferenceSession).Assembly.GetName().Version?.ToString() ?? "unknown";
        var info = new OcrEngineInfo(
            $"{options.DetFileName} ({Hash(detPath)})",
            $"{options.RecFileName} ({Hash(recPath)})",
            $"{options.DictFileName} ({dictionary.Length} entries)",
            $"Microsoft.ML.OnnxRuntime {runtimeVersion} (CPU)",
            options.Describe(),
            runtimeVersion);
        return new PaddleOcrEngine(det, rec, dictionary, options, info);
    }

    private static string Hash(string path)
    {
        using var sha = SHA256.Create();
        using var stream = File.OpenRead(path);
        var hash = sha.ComputeHash(stream);
        var sb = new StringBuilder(12);
        for (int i = 0; i < 6; i++) sb.Append(hash[i].ToString("x2"));
        return $"{sb}, {new FileInfo(path).Length} bytes";
    }

    public OcrPage Recognize(PixelImage image, CancellationToken cancellationToken = default)
    {
        if (image.IsEmpty) return OcrPage.Empty;
        lock (_gate)
        {
            var total = Stopwatch.StartNew();
            var preprocess = Stopwatch.StartNew();

            float scale = 1f;
            int detW, detH;
            int longSide = Math.Max(image.Width, image.Height);
            if (_options.DetLimitSide > 0 && longSide > _options.DetLimitSide)
                scale = _options.DetLimitSide / (float)longSide;

            detW = Math.Max(32, RoundTo32((int)Math.Round(image.Width * scale)));
            detH = Math.Max(32, RoundTo32((int)Math.Round(image.Height * scale)));

            var detInput = TensorBuilder.ToPlanarRgb(image, image.BoundsRect, detW, detH, Mean, Std);
            preprocess.Stop();

            var detect = Stopwatch.StartNew();
            float[] probability;
            int probW, probH;
            var detDense = new DenseTensor<float>(detInput, new[] { 1, 3, detH, detW });
            using (var results = _detSession.Run(new[] { NamedOnnxValue.CreateFromTensor(_detInput, detDense) }))
            {
                var value = results.First().AsTensor<float>();
                var dims = value.Dimensions;
                probH = dims[^2];
                probW = dims[^1];
                probability = value.ToArray();
            }

            var boxes = DetPostProcessor.Process(
                probability, probW, probH,
                _options.DetBitmapThreshold, _options.DetBoxThreshold, _options.UnclipRatio, _options.MinBoxSize,
                probW / (float)image.Width, probH / (float)image.Height,
                image.Width, image.Height);
            detect.Stop();

            var recognize = Stopwatch.StartNew();
            var lines = new List<OcrLine>(boxes.Count);
            foreach (var box in boxes)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var line = RecognizeLine(image, box.Box, box.Score);
                if (line != null) lines.Add(line);
            }

            recognize.Stop();
            total.Stop();
            var timing = new OcrTiming(preprocess.Elapsed.TotalMilliseconds, detect.Elapsed.TotalMilliseconds,
                recognize.Elapsed.TotalMilliseconds, total.Elapsed.TotalMilliseconds);
            var ordered = ReadingOrder.Sort(lines);
            return new OcrPage(ordered, image.Width, image.Height, Info, timing);
        }
    }

    private OcrLine? RecognizeLine(PixelImage image, RectF box, float detScore)
    {
        var crop = RectI.FromRectFRoundOut(box).Intersect(image.BoundsRect);
        if (crop.IsEmpty || crop.Height < 4) return null;

        int recH = _options.RecHeight;
        int recW = (int)Math.Round(recH * crop.Width / (double)crop.Height);
        recW = Math.Clamp(recW, _options.RecMinWidth, _options.RecMaxWidth);
        recW = Math.Max(8, RoundToMultiple(recW, 8));

        var buffer = TensorBuilder.ToPlanarRgbNormalized(image, crop, recW, recH);
        float[] logits;
        int timeSteps, classes;
        var recDense = new DenseTensor<float>(buffer, new[] { 1, 3, recH, recW });
        using (var results = _recSession.Run(new[] { NamedOnnxValue.CreateFromTensor(_recInput, recDense) }))
        {
            var value = results.First().AsTensor<float>();
            var dims = value.Dimensions;
            timeSteps = dims[^2];
            classes = dims[^1];
            logits = value.ToArray();
        }

        var chars = CtcDecoder.Decode(logits, timeSteps, classes, _dictionary);
        if (chars.Count == 0) return null;

        var glyphs = BuildGlyphs(chars, timeSteps, crop);
        if (_options.RestoreWordSpaces)
        {
            // Character boxes are contiguous, so the only reliable space evidence is in the pixels.
            var ink = InkProfile.ColumnsWithInk(image, crop);
            glyphs = InkProfile.InsertWordSpaces(glyphs, ink, crop, _options.SpaceGapRatio).ToList();
        }

        var text = string.Concat(glyphs.Select(c => c.Text));
        if (!TextMetrics.ContainsWordChar(text) && text.Trim().Length == 0) return null;

        float score = chars.Count == 0 ? detScore : chars.Average(c => c.Confidence);
        return new OcrLine(text, box, glyphs, score);
    }

    /// <summary>
    /// Converts CTC time steps into per-character boxes. A character's own steps are usually a single
    /// spike separated by blanks, so the box is the cell between the midpoints of neighbouring spikes:
    /// every character then owns a contiguous slice of the line instead of a few pixels around its spike.
    /// </summary>
    private static List<OcrGlyph> BuildGlyphs(List<CtcChar> chars, int timeSteps, RectI crop)
    {
        var centres = new double[chars.Count];
        for (int i = 0; i < chars.Count; i++) centres[i] = (chars[i].TimeStart + chars[i].TimeEnd + 1) / 2.0;

        var glyphs = new List<OcrGlyph>(chars.Count);
        for (int i = 0; i < chars.Count; i++)
        {
            double left = i == 0 ? 0 : (centres[i - 1] + centres[i]) / 2.0;
            double right = i == chars.Count - 1 ? timeSteps : (centres[i] + centres[i + 1]) / 2.0;
            float x0 = crop.X + (float)(left / timeSteps * crop.Width);
            float x1 = crop.X + (float)(right / timeSteps * crop.Width);
            if (x1 <= x0) x1 = x0 + 1f;
            glyphs.Add(new OcrGlyph(chars[i].Text, RectF.FromEdges(x0, crop.Y, x1, crop.Bottom), chars[i].TimeStart, chars[i].TimeEnd));
        }

        return glyphs;
    }

    private static int RoundTo32(int value) => Math.Max(32, (int)(Math.Ceiling(value / 32.0) * 32));
    private static int RoundToMultiple(int value, int multiple) => (int)(Math.Ceiling(value / (double)multiple) * multiple);

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _detSession.Dispose();
        _recSession.Dispose();
    }
}

