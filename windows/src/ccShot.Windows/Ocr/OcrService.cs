using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using ccShot.Core.Imaging;
using ccShot.Core.Ocr;
using ccShot.Core.Ocr.Paddle;
using ccShot.Core.Settings;

namespace ccShot.Windows.Ocr;

/// <summary>
/// Owns the local OCR engine: resolves the model directory, loads the models once and runs recognition
/// off the UI thread. Nothing is downloaded automatically; a missing or broken model produces a message
/// the user can act on (WIN-06).
/// </summary>
internal sealed class OcrService : IDisposable
{
    private readonly object _gate = new();
    private PaddleOcrEngine? _engine;
    private string? _loadedFrom;
    private bool _disposed;

    public string? LastError { get; private set; }
    public string? LoadedFrom => _loadedFrom;
    public bool IsReady => _engine != null;

    /// <summary>
    /// Looks for models in this order: an explicit override, <c>models/mobile</c> next to the executable,
    /// the same folder a few levels up (source tree layout) and finally <c>models</c> next to the executable.
    /// </summary>
    public static string? ResolveModelDirectory(string? overrideDirectory)
    {
        if (!string.IsNullOrWhiteSpace(overrideDirectory) && HasModels(overrideDirectory)) return overrideDirectory;

        var baseDir = AppContext.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(baseDir, "models", "mobile"),
            Path.Combine(baseDir, "models"),
        };
        foreach (var candidate in candidates)
        {
            if (HasModels(candidate)) return candidate;
        }

        var dir = new DirectoryInfo(baseDir);
        for (int depth = 0; depth < 5 && dir != null; depth++, dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "models", "mobile");
            if (HasModels(candidate)) return candidate;
        }

        return null;
    }

    private static bool HasModels(string directory) =>
        Directory.Exists(directory) &&
        File.Exists(Path.Combine(directory, "det.onnx")) &&
        File.Exists(Path.Combine(directory, "rec.onnx")) &&
        File.Exists(Path.Combine(directory, "dict.txt"));

    public bool TryPrepare(AppSettings settings, out string error)
    {
        error = string.Empty;
        lock (_gate)
        {
            if (_disposed)
            {
                error = "文字识别已关闭";
                return false;
            }
            if (_engine != null) return true;
            var directory = ResolveModelDirectory(settings.OcrModelDirectory);
            if (directory == null)
            {
                error = "未找到本地文字识别模型。请把 models/mobile（det.onnx、rec.onnx、dict.txt）放到程序目录下，" +
                        "或运行 windows/tools/fetch-models.sh 后复制过来。图片仍然可以标注、复制和保存。";
                LastError = error;
                return false;
            }

            try
            {
                _engine = PaddleOcrEngine.Create(directory, new PaddleOcrOptions());
                _loadedFrom = directory;
                LastError = null;
                return true;
            }
            catch (Exception ex)
            {
                error = $"文字识别模型加载失败：{ex.Message}。可重新运行 tools/fetch-models.sh 校验文件完整性。";
                LastError = error;
                _engine = null;
                return false;
            }
        }
    }

    public Task<(OcrPage? Page, string? Error)> RecognizeAsync(PixelImage image, AppSettings settings, CancellationToken token) =>
        Task.Run(() =>
        {
            try
            {
                lock (_gate)
                {
                    token.ThrowIfCancellationRequested();
                    if (!TryPrepare(settings, out string error)) return ((OcrPage?)null, error);
                    var page = _engine!.Recognize(image, token);
                    return ((OcrPage?)page, (string?)null);
                }
            }
            catch (OperationCanceledException)
            {
                return ((OcrPage?)null, "已取消");
            }
            catch (Exception ex)
            {
                return ((OcrPage?)null, "识别失败：" + ex.Message);
            }
        });

    public void Dispose()
    {
        lock (_gate)
        {
            _disposed = true;
            _engine?.Dispose();
            _engine = null;
        }
    }
}
