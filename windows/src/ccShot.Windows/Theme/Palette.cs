using System.Windows.Media;

namespace ccShot.Windows.Theme;

/// <summary>
/// Colours copied from the macOS build (CoreAppearance.swift) so both platforms look like the same product:
/// warm white surface, deep teal-green accent, ink text, rounded and calm.
/// </summary>
internal static class Palette
{
    private static SolidColorBrush Frozen(byte a, byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromArgb(a, r, g, b));
        brush.Freeze();
        return brush;
    }

    public static readonly Color Accent = Color.FromRgb(0x2B, 0x66, 0x50);
    public static readonly Color AccentSoft = Color.FromRgb(0x4A, 0x8A, 0x73);
    public static readonly Color Surface = Color.FromRgb(0xF7, 0xFA, 0xF5);
    public static readonly Color SurfaceDark = Color.FromRgb(0x21, 0x25, 0x24);
    public static readonly Color Ink = Color.FromRgb(0x1F, 0x25, 0x2B);
    public static readonly Color InkSoft = Color.FromRgb(0x5A, 0x63, 0x6B);
    public static readonly Color Error = Color.FromRgb(0xB3, 0x26, 0x1F);

    public static readonly SolidColorBrush AccentBrush = Frozen(255, Accent.R, Accent.G, Accent.B);
    public static readonly SolidColorBrush AccentSoftBrush = Frozen(255, AccentSoft.R, AccentSoft.G, AccentSoft.B);
    public static readonly SolidColorBrush SurfaceBrush = Frozen(255, Surface.R, Surface.G, Surface.B);
    public static readonly SolidColorBrush InkBrush = Frozen(255, Ink.R, Ink.G, Ink.B);
    public static readonly SolidColorBrush InkSoftBrush = Frozen(255, InkSoft.R, InkSoft.G, InkSoft.B);
    public static readonly SolidColorBrush SelectionBrush = Frozen(0x4C, AccentSoft.R, AccentSoft.G, AccentSoft.B);
    public static readonly SolidColorBrush DimBrush = Frozen(0x9E, 0x10, 0x14, 0x16);
    public static readonly SolidColorBrush PanelBrush = Frozen(0xF2, 0xFF, 0xFF, 0xFF);
    public static readonly SolidColorBrush WhiteBrush = Frozen(255, 255, 255, 255);
    public static readonly SolidColorBrush ErrorBrush = Frozen(255, Error.R, Error.G, Error.B);

    /// <summary>Annotation palette: readable on light and dark screenshots.</summary>
    public static readonly Color[] AnnotationColors =
    {
        Color.FromRgb(0xE0, 0x52, 0x3F), // red
        Color.FromRgb(0xF2, 0xA6, 0x2E), // amber
        Color.FromRgb(0x3D, 0x8B, 0xF5), // blue
        Color.FromRgb(0x2B, 0x66, 0x50), // teal
        Color.FromRgb(0x7A, 0x5C, 0xC4), // purple
        Color.FromRgb(0x1F, 0x25, 0x2B), // ink
        Color.FromRgb(0xFF, 0xFF, 0xFF), // white
    };

    public static Brush BrushFor(uint argb)
    {
        var brush = new SolidColorBrush(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb));
        brush.Freeze();
        return brush;
    }

    public static Color ColorFor(uint argb) => Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb);

    public static uint ToArgb(Color color) =>
        ((uint)color.A << 24) | ((uint)color.R << 16) | ((uint)color.G << 8) | color.B;
}
