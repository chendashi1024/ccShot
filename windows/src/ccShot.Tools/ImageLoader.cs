using System.Diagnostics;
using ccShot.Core.Imaging;
using StbImageSharp;

namespace ccShot.Tools;

internal static class ImageLoader
{
    /// <summary>
    /// Loads a PNG/JPG into the tightly packed BGRA layout the OCR engine consumes.
    /// StbImageSharp is used instead of a heavier imaging library: public domain, no licence key,
    /// and this tool only ever reads our own fixture images.
    /// </summary>
    public static PixelImage Load(string path)
    {
        var bytes = File.ReadAllBytes(path);
        var image = StbImageSharp.ImageResult.FromMemory(bytes, StbImageSharp.ColorComponents.RedGreenBlueAlpha);
        int width = image.Width, height = image.Height;
        var source = image.Data;
        var buffer = new byte[width * height * 4];
        for (int i = 0; i < buffer.Length; i += 4)
        {
            buffer[i] = source[i + 2];     // B
            buffer[i + 1] = source[i + 1]; // G
            buffer[i + 2] = source[i];     // R
            buffer[i + 3] = source[i + 3]; // A
        }

        return new PixelImage(width, height, buffer);
    }
}

/// <summary>Single-precision timer that keeps every measurement so P50/P95 are computed from raw values.</summary>
internal sealed class TimingBag
{
    private readonly List<double> _values = new();

    public IDisposable Measure(out Func<double> elapsed)
    {
        var sw = Stopwatch.StartNew();
        elapsed = () => sw.Elapsed.TotalMilliseconds;
        return new Stopper(sw);
    }

    public void Add(double ms) => _values.Add(ms);

    public IReadOnlyList<double> Values => _values;

    public double Median => Percentile(0.5);
    public double P95 => Percentile(0.95);
    public double Mean => _values.Count == 0 ? 0 : _values.Average();
    public double Max => _values.Count == 0 ? 0 : _values.Max();
    public double Min => _values.Count == 0 ? 0 : _values.Min();

    public double Percentile(double p)
    {
        if (_values.Count == 0) return 0;
        var sorted = _values.OrderBy(v => v).ToArray();
        double rank = p * (sorted.Length - 1);
        int low = (int)Math.Floor(rank);
        int high = (int)Math.Ceiling(rank);
        if (low == high) return sorted[low];
        double weight = rank - low;
        return sorted[low] * (1 - weight) + sorted[high] * weight;
    }

    private sealed class Stopper : IDisposable
    {
        private readonly Stopwatch _sw;
        public Stopper(Stopwatch sw) => _sw = sw;
        public void Dispose() => _sw.Stop();
    }
}
