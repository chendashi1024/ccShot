using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CcShot.Core.Settings;

[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
    Windows = 8,
}

/// <summary>A global shortcut: modifiers plus one non-modifier key expressed as a virtual-key name.</summary>
public sealed record HotkeyBinding(HotkeyModifiers Modifiers, string Key)
{
    public static readonly HotkeyBinding DefaultCapture = new(HotkeyModifiers.Control | HotkeyModifiers.Alt, "X");

    public override string ToString()
    {
        var parts = new List<string>();
        if (Modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(HotkeyModifiers.Windows)) parts.Add("Win");
        parts.Add(Key);
        return string.Join("+", parts);
    }
}

/// <summary>Parser for the shortcut text shown in settings ("Ctrl+Alt+X", "F1", "Shift+PrintScreen").</summary>
public static class HotkeyParser
{
    private static readonly Dictionary<string, string> Aliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ctrl"] = "Ctrl",
        ["control"] = "Ctrl",
        ["alt"] = "Alt",
        ["option"] = "Alt",
        ["shift"] = "Shift",
        ["win"] = "Win",
        ["windows"] = "Win",
        ["cmd"] = "Win",
    };

    public static bool TryParse(string? text, out HotkeyBinding binding, out string error)
    {
        binding = HotkeyBinding.DefaultCapture;
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(text))
        {
            error = "快捷键不能为空";
            return false;
        }

        var tokens = text.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (tokens.Length == 0)
        {
            error = "快捷键不能为空";
            return false;
        }

        var modifiers = HotkeyModifiers.None;
        string? key = null;
        foreach (var token in tokens)
        {
            if (Aliases.TryGetValue(token, out var canonical))
            {
                modifiers |= canonical switch
                {
                    "Ctrl" => HotkeyModifiers.Control,
                    "Alt" => HotkeyModifiers.Alt,
                    "Shift" => HotkeyModifiers.Shift,
                    _ => HotkeyModifiers.Windows,
                };
                continue;
            }

            if (key != null)
            {
                error = "只能包含一个非修饰键";
                return false;
            }

            key = NormalizeKey(token);
        }

        if (key == null)
        {
            error = "缺少主键，例如 Ctrl+Alt+X";
            return false;
        }

        if (modifiers == HotkeyModifiers.None && !IsFunctionKey(key))
        {
            error = "单独字母作全局键会抢占正常输入，请加 Ctrl、Alt 或 Shift";
            return false;
        }

        binding = new HotkeyBinding(modifiers, key);
        return true;
    }

    private static string NormalizeKey(string token)
    {
        string upper = token.ToUpperInvariant();
        if (upper.StartsWith("F", StringComparison.Ordinal) && int.TryParse(upper[1..], out int f) && f is >= 1 and <= 24)
            return upper;
        if (upper is "PRINTSCREEN" or "PRTSC" or "PRINT") return "PrintScreen";
        if (upper is "ESC" or "ESCAPE") return "Escape";
        if (upper == "SPACE") return "Space";
        if (upper.StartsWith("NUM", StringComparison.Ordinal) && upper.Length > 3) return upper;
        return upper.Length == 1 ? upper : CultureInfo.InvariantCulture.TextInfo.ToTitleCase(token.ToLowerInvariant());
    }

    public static bool IsFunctionKey(string key) =>
        key.Length > 1 && key[0] == 'F' && int.TryParse(key[1..], out int n) && n is >= 1 and <= 24;
}

/// <summary>User settings. Kept intentionally small: capture shortcut and save location.</summary>
public sealed class AppSettings
{
    public string CaptureHotkey { get; set; } = HotkeyBinding.DefaultCapture.ToString();

    public string? SaveDirectory { get; set; }

    public string ImageFormat { get; set; } = "png";

    public bool CopyAfterCapture { get; set; }

    /// <summary>Optional override; by default models live next to the executable in <c>models/</c>.</summary>
    public string? OcrModelDirectory { get; set; }

    [JsonIgnore]
    public string ResolvedSaveDirectory =>
        string.IsNullOrWhiteSpace(SaveDirectory)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "ccShot")
            : SaveDirectory!;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static string DefaultPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ccShot", "settings.json");

    public static AppSettings Load(string? path = null)
    {
        path ??= DefaultPath;
        try
        {
            if (!File.Exists(path)) return new AppSettings();
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
        }
        catch (Exception)
        {
            // A corrupt settings file must not block startup; defaults keep the app usable.
            return new AppSettings();
        }
    }

    public void Save(string? path = null)
    {
        path ??= DefaultPath;
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var json = JsonSerializer.Serialize(this, JsonOptions);
        var temp = path + ".tmp";
        File.WriteAllText(temp, json);
        File.Move(temp, path, overwrite: true);
    }

    public bool TryGetBinding(out HotkeyBinding binding, out string error) =>
        HotkeyParser.TryParse(CaptureHotkey, out binding, out error);
}
