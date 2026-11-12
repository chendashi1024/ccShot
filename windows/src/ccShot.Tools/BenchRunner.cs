using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ccShot.Tools;

internal sealed class TruthGlyph
{
    public string Char { get; set; } = string.Empty;
    public double X { get; set; }
    public double Y { get; set; }
    public double W { get; set; }
    public double H { get; set; }
}

internal sealed class Fixture
{
    public string Id { get; set; } = string.Empty;
    public string File { get; set; } = string.Empty;
    public string Text { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Condition { get; set; } = string.Empty;
    public int Width { get; set; }
    public int Height { get; set; }
    public string? Font { get; set; }
    public double FontSize { get; set; }
    public double Scale { get; set; } = 1;

    /// <summary>Optional per-character ground truth boxes used by the selection checks.</summary>
    public List<TruthGlyph>? Glyphs { get; set; }

    /// <summary>Optional ground-truth lines, used to score reading order independently of the text.</summary>
    public List<string>? TruthLines { get; set; }
}

internal sealed class ModelSpec
{
    public string Label { get; set; } = string.Empty;
    public string Directory { get; set; } = string.Empty;
}

internal sealed class BenchOptions
{
    public string ManifestPath { get; set; } = string.Empty;
    public string FixturesDirectory { get; set; } = string.Empty;
    public string OutputPath { get; set; } = string.Empty;
    public List<ModelSpec> Models { get; } = new();
    public int Repeat { get; set; } = 3;
    public int Threads { get; set; }
    public int Limit { get; set; }
    public bool SkipSelectionChecks { get; set; }
}

internal static class BenchRunner
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static async Task<int> RunAsync(BenchOptions options)
    {
        var manifestBytes = await File.ReadAllBytesAsync(options.ManifestPath);
        var fixtures = JsonSerializer.Deserialize<List<Fixture>>(manifestBytes, JsonOptions)
                       ?? throw new InvalidOperationException("Manifest could not be parsed.");

        string manifestSha = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(manifestBytes)).ToLowerInvariant();
        if (options.Limit > 0) fixtures = fixtures.Take(options.Limit).ToList();
        Console.WriteLine($"fixtures: {fixtures.Count} (manifest sha256 {manifestSha[..12]})");

        var report = new BenchReport
        {
            GeneratedAt = DateTimeOffset.Now.ToString("yyyy-MM-dd HH:mm:ss zzz"),
            Manifest = Path.GetRelativePath(Directory.GetCurrentDirectory(), options.ManifestPath),
            ManifestSha256 = manifestSha,
            FixtureCount = fixtures.Count,
            Repeat = options.Repeat,
            Environment = EnvironmentInfo.Describe(),
        };

        foreach (var spec in options.Models)
        {
            Console.WriteLine();
            Console.WriteLine($"=== model '{spec.Label}' from {spec.Directory}");
            var engineStart = DateTime.Now;
            using var engine = ccShot.Core.Ocr.Paddle.PaddleOcrEngine.Create(spec.Directory,
                new ccShot.Core.Ocr.Paddle.PaddleOcrOptions { Threads = options.Threads });
            var loadMs = (DateTime.Now - engineStart).TotalMilliseconds;
            Console.WriteLine($"load: {loadMs:0.0} ms");
            Console.WriteLine($"engine: {engine.Info.Describe()}");

            var modelReport = new ModelReport
            {
                Label = spec.Label,
                Directory = Path.GetRelativePath(Directory.GetCurrentDirectory(), spec.Directory),
                LoadMs = loadMs,
                Engine = engine.Info.Describe(),
                AssetSizes = AssetSizes(spec.Directory),
            };

            long peakBefore = Environment.WorkingSet;
            var images = new List<ImageResult>();
            foreach (var fixture in fixtures)
            {
                var path = Path.Combine(options.FixturesDirectory, fixture.File);
                var image = ImageLoader.Load(path);
                var result = new ImageResult
                {
                    Id = fixture.Id,
                    File = fixture.File,
                    Category = fixture.Category,
                    Condition = fixture.Condition,
                    Truth = fixture.Text,
                    Width = image.Width,
                    Height = image.Height,
                };

                string hypothesis = string.Empty;
                for (int run = 0; run < options.Repeat; run++)
                {
                    try
                    {
                        var page = engine.Recognize(image);
                        hypothesis = page.ToPlainText();
                        if (run == 0)
                        {
                            result.Hypothesis = hypothesis;
                            result.LineCount = page.Lines.Count;
                            result.TotalMs = page.Timing.TotalMs;
                            result.PreprocessMs = page.Timing.PreprocessMs;
                            result.DetectMs = page.Timing.DetectMs;
                            result.RecognizeMs = page.Timing.RecognizeMs;
                            if (!options.SkipSelectionChecks && fixture.Glyphs is { Count: > 0 })
                                result.Selection = SelectionChecks.Evaluate(page, fixture);
                            if (fixture.TruthLines is { Count: > 0 })
                                result.LineTextAgreement = LineAgreement(fixture.TruthLines, page.Lines.Select(l => l.Text).ToList());
                        }
                    }
                    catch (Exception ex)
                    {
                        result.Failure = ex.GetType().Name + ": " + ex.Message;
                        break;
                    }
                }

                if (result.Failure != null)
                {
                    result.Cer = 1;
                    result.CerStrict = 1;
                }
                else
                {
                    result.Cer = ccShot.Core.Ocr.TextMetrics.Cer(fixture.Text, hypothesis);
                    result.CerStrict = ccShot.Core.Ocr.TextMetrics.Cer(fixture.Text, hypothesis, keepWhitespace: true);
                    result.Exact = ccShot.Core.Ocr.TextMetrics.ExactMatch(fixture.Text, hypothesis);
                    result.Empty = string.IsNullOrWhiteSpace(hypothesis);
                }

                result.MeasuredMs = result.TotalMs;
                images.Add(result);
                Console.WriteLine($"{fixture.Id,-10} cer={result.Cer:0.0000} exact={(result.Exact ? "Y" : "n")} " +
                                  $"{result.TotalMs,7:0.0}ms lines={result.LineCount} {(result.Failure is null ? "" : "FAILED " + result.Failure)}");
            }

            // On some platforms PeakWorkingSet64 reports 0; leave the field out instead of publishing a fake number.
            modelReport.PeakWorkingSetMb = 0;
            long peak = Process.GetCurrentProcess().PeakWorkingSet64;
            modelReport.ProcessPeakWorkingSetMb = peak > 0 ? peak / 1024.0 / 1024.0 : null;
            modelReport.Images = images;
            modelReport.Aggregate = Aggregate(images);
            report.Models.Add(modelReport);

            string peakText = modelReport.ProcessPeakWorkingSetMb is { } ws ? $"{ws:0}MB" : "n/a (measure externally)";
            Console.WriteLine($"micro CER loose={modelReport.Aggregate.Cer:0.0000} strict={modelReport.Aggregate.CerStrict:0.0000} " +
                              $"exact={modelReport.Aggregate.ExactMatches}/{images.Count} " +
                              $"P50={modelReport.Aggregate.TotalMsP50:0.0}ms P95={modelReport.Aggregate.TotalMsP95:0.0}ms peakWS={peakText}");
            if (modelReport.Aggregate.Selection is { } sel)
                Console.WriteLine($"selection single-char={sel.SingleCharAccuracy:P1} range={sel.RangeAccuracy:P1} " +
                                  $"glyphHit={sel.GlyphHitRate:P1} boundaryMAE={sel.BoundaryMeanAbsErrorPx:0.0}px");
            _ = peakBefore;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(options.OutputPath))!);
        await File.WriteAllTextAsync(options.OutputPath, JsonSerializer.Serialize(report, JsonOptions));
        Console.WriteLine();
        Console.WriteLine($"report: {Path.GetFullPath(options.OutputPath)}");
        return 0;
    }

    private static Dictionary<string, long> AssetSizes(string directory)
    {
        var sizes = new Dictionary<string, long>();
        foreach (var file in Directory.GetFiles(directory))
            sizes[Path.GetFileName(file)] = new FileInfo(file).Length;
        sizes["total"] = sizes.Values.Sum();
        return sizes;
    }

    private static double LineAgreement(List<string> truth, List<string> actual)
    {
        if (truth.Count == 0) return 0;
        int matched = 0;
        for (int i = 0; i < Math.Min(truth.Count, actual.Count); i++)
        {
            if (ccShot.Core.Ocr.TextMetrics.ExactMatch(truth[i], actual[i])) matched++;
        }

        return matched / (double)truth.Count;
    }

    private static AggregateResult Aggregate(List<ImageResult> images)
    {
        int truthChars = 0, edits = 0, editsStrict = 0, truthCharsStrict = 0;
        var timings = new TimingBag();
        foreach (var image in images)
        {
            var normalized = ccShot.Core.Ocr.TextMetrics.Normalize(image.Truth);
            truthChars += normalized.Length;
            edits += (int)Math.Round(image.Cer * Math.Max(1, normalized.Length));
            var strict = ccShot.Core.Ocr.TextMetrics.Normalize(image.Truth, keepWhitespace: true);
            truthCharsStrict += strict.Length;
            editsStrict += (int)Math.Round(image.CerStrict * Math.Max(1, strict.Length));
            if (image.Failure == null && image.TotalMs > 0) timings.Add(image.TotalMs);
        }

        var aggregate = new AggregateResult
        {
            TruthCharacters = truthChars,
            EditDistance = edits,
            Cer = truthChars == 0 ? 0 : edits / (double)truthChars,
            CerStrict = truthCharsStrict == 0 ? 0 : editsStrict / (double)truthCharsStrict,
            ExactMatches = images.Count(i => i.Exact),
            EmptyOutputs = images.Count(i => i.Empty),
            Failures = images.Count(i => i.Failure != null),
            TotalMsP50 = timings.Median,
            TotalMsP95 = timings.P95,
            TotalMsMean = timings.Mean,
            DetectMsP50 = Median(images.Where(i => i.Failure == null).Select(i => i.DetectMs)),
            RecognizeMsP50 = Median(images.Where(i => i.Failure == null).Select(i => i.RecognizeMs)),
        };

        var selections = images.Where(i => i.Selection != null).Select(i => i.Selection!).ToList();
        if (selections.Count > 0)
        {
            aggregate.Selection = new SelectionAggregate
            {
                Fixtures = selections.Count,
                SingleCharTotal = selections.Sum(s => s.SingleCharTotal),
                SingleCharCorrect = selections.Sum(s => s.SingleCharCorrect),
                RangeTotal = selections.Sum(s => s.RangeTotal),
                RangeCorrect = selections.Sum(s => s.RangeCorrect),
                TruthGlyphs = selections.Sum(s => s.TruthGlyphs),
                MatchedGlyphs = selections.Sum(s => s.MatchedGlyphs),
                BoundaryMeanAbsErrorPx = selections.Average(s => s.BoundaryMeanAbsErrorPx),
                BoundaryMeanNormalizedError = selections.Average(s => s.BoundaryMeanNormalizedError),
            };
        }

        return aggregate;
    }

    private static double Median(IEnumerable<double> values)
    {
        var sorted = values.Where(v => v > 0).OrderBy(v => v).ToArray();
        if (sorted.Length == 0) return 0;
        return sorted[sorted.Length / 2];
    }
}

internal sealed class BenchReport
{
    public string GeneratedAt { get; set; } = string.Empty;
    public string Manifest { get; set; } = string.Empty;
    public string ManifestSha256 { get; set; } = string.Empty;
    public int FixtureCount { get; set; }
    public int Repeat { get; set; }
    public Dictionary<string, string> Environment { get; set; } = new();
    public List<ModelReport> Models { get; set; } = new();
}

internal sealed class ModelReport
{
    public string Label { get; set; } = string.Empty;
    public string Directory { get; set; } = string.Empty;
    public double LoadMs { get; set; }
    public string Engine { get; set; } = string.Empty;
    public Dictionary<string, long> AssetSizes { get; set; } = new();
    public double PeakWorkingSetMb { get; set; }

    /// <summary>Null when the platform does not report it; memory is then measured externally.</summary>
    public double? ProcessPeakWorkingSetMb { get; set; }
    public List<ImageResult> Images { get; set; } = new();
    public AggregateResult Aggregate { get; set; } = new();
}

internal sealed class ImageResult
{
    public string Id { get; set; } = string.Empty;
    public string File { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Condition { get; set; } = string.Empty;
    public int Width { get; set; }
    public int Height { get; set; }
    public string Truth { get; set; } = string.Empty;
    public string? Hypothesis { get; set; }
    public double Cer { get; set; }
    public double CerStrict { get; set; }
    public bool Exact { get; set; }
    public bool Empty { get; set; }
    public int LineCount { get; set; }
    public double TotalMs { get; set; }
    public double PreprocessMs { get; set; }
    public double DetectMs { get; set; }
    public double RecognizeMs { get; set; }
    public double MeasuredMs { get; set; }
    public string? Failure { get; set; }
    public double? LineTextAgreement { get; set; }
    public SelectionResult? Selection { get; set; }
}

internal sealed class AggregateResult
{
    public int TruthCharacters { get; set; }
    public int EditDistance { get; set; }
    public double Cer { get; set; }
    public double CerStrict { get; set; }
    public int ExactMatches { get; set; }
    public int EmptyOutputs { get; set; }
    public int Failures { get; set; }
    public double TotalMsP50 { get; set; }
    public double TotalMsP95 { get; set; }
    public double TotalMsMean { get; set; }
    public double DetectMsP50 { get; set; }
    public double RecognizeMsP50 { get; set; }
    public SelectionAggregate? Selection { get; set; }
}

internal sealed class SelectionAggregate
{
    public int Fixtures { get; set; }
    public int SingleCharTotal { get; set; }
    public int SingleCharCorrect { get; set; }
    public int RangeTotal { get; set; }
    public int RangeCorrect { get; set; }
    public int TruthGlyphs { get; set; }
    public int MatchedGlyphs { get; set; }
    public double BoundaryMeanAbsErrorPx { get; set; }
    public double BoundaryMeanNormalizedError { get; set; }

    [JsonIgnore]
    public double SingleCharAccuracy => SingleCharTotal == 0 ? 0 : SingleCharCorrect / (double)SingleCharTotal;

    [JsonIgnore]
    public double RangeAccuracy => RangeTotal == 0 ? 0 : RangeCorrect / (double)RangeTotal;

    [JsonIgnore]
    public double GlyphHitRate => TruthGlyphs == 0 ? 0 : MatchedGlyphs / (double)TruthGlyphs;
}

internal sealed class SelectionResult
{
    public int SingleCharTotal { get; set; }
    public int SingleCharCorrect { get; set; }
    public int RangeTotal { get; set; }
    public int RangeCorrect { get; set; }
    public int TruthGlyphs { get; set; }
    public int MatchedGlyphs { get; set; }
    public double BoundaryMeanAbsErrorPx { get; set; }
    public double BoundaryMeanNormalizedError { get; set; }
    public List<string> Mismatches { get; set; } = new();
}

internal static class EnvironmentInfo
{
    public static Dictionary<string, string> Describe() => new()
    {
        ["os"] = System.Runtime.InteropServices.RuntimeInformation.OSDescription,
        ["arch"] = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),
        ["cpu"] = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString() + " / " +
                  System.Environment.ProcessorCount + " logical cores",
        ["cpuModel"] = CpuModel(),
        ["processors"] = System.Environment.ProcessorCount.ToString(),
        ["dotnet"] = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
        ["workingSetMb"] = (System.Environment.WorkingSet / 1024.0 / 1024.0).ToString("0.0"),
    };

    private static string CpuModel()
    {
        try
        {
            if (OperatingSystem.IsMacOS())
            {
                var p = Process.Start(new ProcessStartInfo("sysctl", "-n machdep.cpu.brand_string")
                { RedirectStandardOutput = true });
                if (p != null)
                {
                    string text = p.StandardOutput.ReadToEnd().Trim();
                    p.WaitForExit();
                    return text;
                }
            }

            if (OperatingSystem.IsWindows())
            {
                return System.Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER") ?? "unknown";
            }
        }
        catch
        {
            // CPU model is reporting-only; a failure must not abort the run.
        }

        return "unknown";
    }
}
