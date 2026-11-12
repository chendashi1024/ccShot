using System;
using System.Globalization;
using System.Linq;
using ccShot.Core.Ocr.Paddle;

namespace ccShot.Tools;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        if (args.Length == 0 || args[0] is "-h" or "--help" or "help")
        {
            PrintHelp();
            return 0;
        }

        try
        {
            switch (args[0])
            {
                case "bench":
                    return await BenchAsync(args.Skip(1).ToArray());
                case "dump":
                    return Dump(args.Skip(1).ToArray());
                case "info":
                    foreach (var pair in EnvironmentInfo.Describe()) Console.WriteLine($"{pair.Key,-12} {pair.Value}");
                    return 0;
                default:
                    Console.Error.WriteLine($"未知命令: {args[0]}");
                    PrintHelp();
                    return 2;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            return 1;
        }
    }

    private static void PrintHelp()
    {
        Console.WriteLine("""
        ccShot.Tools —— Windows OCR 候选对比与证据工具

        用法:
          info
          bench --manifest <manifest.json> --fixtures <dir> --out <report.json>
                [--model label=<dir>]... [--repeat N] [--threads N] [--limit N] [--no-selection]
          dump  --model <dir> --image <png> [--json]

        说明:
          bench 用固定原图和真值比较检测/识别组合，输出 CER、整图一致、逐字框与拖选检查原始数据。
          dump  打印单张图的每行文本、置信度和逐字框，用于核对坐标问题。
        """);
    }

    private static async Task<int> BenchAsync(string[] args)
    {
        var options = new BenchOptions();
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--manifest":
                    options.ManifestPath = args[++i];
                    break;
                case "--fixtures":
                    options.FixturesDirectory = args[++i];
                    break;
                case "--out":
                    options.OutputPath = args[++i];
                    break;
                case "--model":
                    var spec = args[++i];
                    int eq = spec.IndexOf('=');
                    options.Models.Add(eq > 0
                        ? new ModelSpec { Label = spec[..eq], Directory = spec[(eq + 1)..] }
                        : new ModelSpec { Label = spec, Directory = spec });
                    break;
                case "--repeat":
                    options.Repeat = int.Parse(args[++i], CultureInfo.InvariantCulture);
                    break;
                case "--threads":
                    options.Threads = int.Parse(args[++i], CultureInfo.InvariantCulture);
                    break;
                case "--limit":
                    options.Limit = int.Parse(args[++i], CultureInfo.InvariantCulture);
                    break;
                case "--no-selection":
                    options.SkipSelectionChecks = true;
                    break;
                default:
                    throw new ArgumentException($"未知参数: {args[i]}");
            }
        }

        if (options.ManifestPath.Length == 0 || options.OutputPath.Length == 0 || options.Models.Count == 0)
            throw new ArgumentException("需要 --manifest、--out 和至少一个 --model。");
        if (options.FixturesDirectory.Length == 0)
            options.FixturesDirectory = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(options.ManifestPath))!;

        return await BenchRunner.RunAsync(options);
    }

    private static int Dump(string[] args)
    {
        string? model = null, imagePath = null;
        bool json = false, showInk = false;
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--model": model = args[++i]; break;
                case "--image": imagePath = args[++i]; break;
                case "--json": json = true; break;
                case "--ink": showInk = true; break;
                default: throw new ArgumentException($"未知参数: {args[i]}");
            }
        }

        if (model == null || imagePath == null) throw new ArgumentException("需要 --model 和 --image。");
        using var engine = PaddleOcrEngine.Create(model);
        var image = ImageLoader.Load(imagePath);
        var page = engine.Recognize(image);
        Console.WriteLine($"# {System.IO.Path.GetFileName(imagePath)} {image.Width}x{image.Height}");
        Console.WriteLine($"# {page.Engine?.Describe()}");
        Console.WriteLine($"# lines={page.Lines.Count} det={page.Timing.DetectMs:0.0}ms rec={page.Timing.RecognizeMs:0.0}ms total={page.Timing.TotalMs:0.0}ms");
        foreach (var line in page.Lines)
        {
            Console.WriteLine($"[{line.Box.X:0},{line.Box.Y:0} {line.Box.Width:0}x{line.Box.Height:0}] score={line.Score:0.000} {line.Text}");
            if (json) continue;
            foreach (var glyph in line.Glyphs)
                Console.WriteLine($"    '{glyph.Text}' x={glyph.Box.X:0.0}..{glyph.Box.Right:0.0} t={glyph.TimeStart}-{glyph.TimeEnd}");

            if (showInk)
            {
                var crop = ccShot.Core.Geometry.RectI.FromRectFRoundOut(line.Box);
                var ink = ccShot.Core.Ocr.InkProfile.ColumnsWithInk(image, crop);
                int blank = 0;
                for (int i = 0; i < ink.Length; i++)
                {
                    if (!ink[i]) { blank++; continue; }
                    if (blank >= 3) Console.WriteLine($"    blank run x={crop.X + i - blank}..{crop.X + i} ({blank}px)");
                    blank = 0;
                }
                Console.WriteLine($"    crop={crop} height={crop.Height}");
            }
        }

        return 0;
    }
}
