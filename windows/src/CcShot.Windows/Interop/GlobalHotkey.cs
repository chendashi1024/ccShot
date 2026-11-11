using System;
using System.Windows.Interop;
using CcShot.Core.Settings;

namespace CcShot.Windows.Interop;

internal static class VirtualKeys
{
    /// <summary>Maps the key name used in settings onto a Windows virtual-key code.</summary>
    public static bool TryParse(string key, out uint vk)
    {
        vk = 0;
        if (string.IsNullOrWhiteSpace(key)) return false;
        string upper = key.Trim().ToUpperInvariant();

        if (upper.Length == 1)
        {
            char ch = upper[0];
            if (ch >= 'A' && ch <= 'Z') { vk = ch; return true; }
            if (ch >= '0' && ch <= '9') { vk = ch; return true; }
            return false;
        }

        if (upper.StartsWith("F", StringComparison.Ordinal) && int.TryParse(upper[1..], out int fn) && fn is >= 1 and <= 24)
        {
            vk = (uint)(0x70 + fn - 1);
            return true;
        }

        if (upper.StartsWith("NUM", StringComparison.Ordinal) && int.TryParse(upper[3..], out int num) && num is >= 0 and <= 9)
        {
            vk = (uint)(0x60 + num);
            return true;
        }

        vk = upper switch
        {
            "PRINTSCREEN" => 0x2C,
            "SPACE" => 0x20,
            "ESCAPE" => 0x1B,
            "TAB" => 0x09,
            "ENTER" => 0x0D,
            "BACKSPACE" => 0x08,
            "INSERT" => 0x2D,
            "DELETE" => 0x2E,
            "HOME" => 0x24,
            "END" => 0x23,
            "PAGEUP" => 0x21,
            "PAGEDOWN" => 0x22,
            "LEFT" => 0x25,
            "UP" => 0x26,
            "RIGHT" => 0x27,
            "DOWN" => 0x28,
            _ => 0,
        };
        return vk != 0;
    }

    public static uint ToWin32(HotkeyModifiers modifiers)
    {
        uint result = NativeMethods.MOD_NOREPEAT;
        if (modifiers.HasFlag(HotkeyModifiers.Alt)) result |= NativeMethods.MOD_ALT;
        if (modifiers.HasFlag(HotkeyModifiers.Control)) result |= NativeMethods.MOD_CONTROL;
        if (modifiers.HasFlag(HotkeyModifiers.Shift)) result |= NativeMethods.MOD_SHIFT;
        if (modifiers.HasFlag(HotkeyModifiers.Windows)) result |= NativeMethods.MOD_WIN;
        return result;
    }
}

/// <summary>
/// Registers one system-wide shortcut through a hidden message window. A conflict (another application
/// owns the combination) is reported to the caller instead of failing silently.
/// </summary>
internal sealed class GlobalHotkey : IDisposable
{
    private const int HotkeyId = 0x4353;
    private HwndSource? _source;
    private bool _registered;
    private uint _modifiers;
    private uint _key;

    public event EventHandler? Pressed;

    public string? LastError { get; private set; }

    public bool Register(HotkeyBinding binding)
    {
        Unregister();
        if (!VirtualKeys.TryParse(binding.Key, out uint vk))
        {
            LastError = $"无法识别按键：{binding.Key}";
            return false;
        }

        EnsureWindow();
        uint modifiers = VirtualKeys.ToWin32(binding.Modifiers);
        if (!NativeMethods.RegisterHotKey(_source!.Handle, HotkeyId, modifiers, vk))
        {
            int code = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            LastError = code == 1409
                ? $"{binding} 已被其他程序占用"
                : $"注册 {binding} 失败（错误码 {code}）";
            return false;
        }

        _registered = true;
        _modifiers = modifiers;
        _key = vk;
        LastError = null;
        return true;
    }

    /// <summary>Verifies a binding can be registered without disturbing the active one.</summary>
    public static bool CanRegister(HotkeyBinding binding, out string error)
    {
        error = string.Empty;
        if (!VirtualKeys.TryParse(binding.Key, out uint vk))
        {
            error = $"无法识别按键：{binding.Key}";
            return false;
        }

        using var probe = new GlobalHotkey();
        probe.EnsureWindow();
        bool ok = NativeMethods.RegisterHotKey(probe._source!.Handle, HotkeyId, VirtualKeys.ToWin32(binding.Modifiers), vk);
        if (ok)
        {
            NativeMethods.UnregisterHotKey(probe._source!.Handle, HotkeyId);
            return true;
        }

        int code = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
        error = code == 1409 ? $"{binding} 已被其他程序占用" : $"注册 {binding} 失败（错误码 {code}）";
        return false;
    }

    private void EnsureWindow()
    {
        if (_source != null) return;
        var parameters = new HwndSourceParameters("ccShotHotkey")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0,
            ExtendedWindowStyle = NativeMethods.WS_EX_TOOLWINDOW,
            ParentWindow = new IntPtr(-3), // HWND_MESSAGE
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg != NativeMethods.WM_HOTKEY || wParam.ToInt32() != HotkeyId) return IntPtr.Zero;
        handled = true;
        Pressed?.Invoke(this, EventArgs.Empty);
        return IntPtr.Zero;
    }

    public void Unregister()
    {
        if (_registered && _source != null)
        {
            NativeMethods.UnregisterHotKey(_source.Handle, HotkeyId);
            _registered = false;
        }
    }

    public HotkeyBinding? Current =>
        _registered ? new HotkeyBinding(FromWin32(_modifiers), DescribeKey(_key)) : null;

    private static HotkeyModifiers FromWin32(uint modifiers)
    {
        var result = HotkeyModifiers.None;
        if ((modifiers & NativeMethods.MOD_ALT) != 0) result |= HotkeyModifiers.Alt;
        if ((modifiers & NativeMethods.MOD_CONTROL) != 0) result |= HotkeyModifiers.Control;
        if ((modifiers & NativeMethods.MOD_SHIFT) != 0) result |= HotkeyModifiers.Shift;
        if ((modifiers & NativeMethods.MOD_WIN) != 0) result |= HotkeyModifiers.Windows;
        return result;
    }

    private static string DescribeKey(uint vk)
    {
        if (vk is >= 0x41 and <= 0x5A) return ((char)vk).ToString();
        if (vk is >= 0x30 and <= 0x39) return ((char)vk).ToString();
        if (vk is >= 0x70 and <= 0x87) return $"F{vk - 0x70 + 1}";
        if (vk is >= 0x60 and <= 0x69) return $"Num{vk - 0x60}";
        return vk switch
        {
            0x2C => "PrintScreen",
            0x20 => "Space",
            0x1B => "Escape",
            0x0D => "Enter",
            0x09 => "Tab",
            _ => $"0x{vk:X2}",
        };
    }

    public void Dispose()
    {
        Unregister();
        _source?.RemoveHook(WndProc);
        _source?.Dispose();
        _source = null;
    }
}
