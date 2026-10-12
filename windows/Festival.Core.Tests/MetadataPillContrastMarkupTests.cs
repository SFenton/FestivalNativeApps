using System.Text.RegularExpressions;

namespace Festival.Core.Tests;

/// <summary>
/// Guards the #606 review finding: season and percentile pills assign theme brushes in code and opt their label out of
/// WinUI's automatic High Contrast adjustment, so the shared <c>MetadataPill</c> must re-resolve its roles when the contrast
/// theme changes while it is open, and the factory must route every look through it. The live check is
/// <c>tools/windows/journeys/a11y-pill-contrast-switch.json</c> (pattern <c>metadata-pills</c>).
/// </summary>
public class MetadataPillContrastMarkupTests
{
    private static readonly string ControlsRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App", "Controls");

    /// <summary>Reads a Festival.App control source file.</summary>
    /// <param name="file">File name under Controls.</param>
    /// <returns>Source text.</returns>
    private static string Source(string file) => File.ReadAllText(Path.Combine(ControlsRoot, file));

    [Fact]
    public void MetadataPill_ReResolvesItsLook_OnContrastThemeChange()
    {
        var source = Source("MetadataPill.cs");
        Assert.Contains("ContrastTheme.Changed += OnColorsChanged", source);
        Assert.Contains("ContrastTheme.Changed -= OnColorsChanged", source);
        Assert.Matches(@"OnColorsChanged\([^)]*\)\s*=>\s*DispatcherQueue\?\.TryEnqueue\(PaintLook\)", source);
        Assert.Matches(@"Unloaded\s*\+=", source);
    }

    [Fact]
    public void MetadataPills_RoutesEveryLookThroughTheSharedPill()
    {
        var source = Source("MetadataPills.cs");
        Assert.Contains("pill.ApplyLook(look)", source);
        Assert.DoesNotMatch(new Regex(@"\.(Background|BorderBrush|Foreground)\s*="), source);
    }

    [Fact]
    public void OnlyTheSharedPill_ResolvesPillRoleBrushes()
    {
        var appRoot = Path.GetDirectoryName(Path.GetFullPath(ControlsRoot))!;
        var offenders = Directory.EnumerateFiles(appRoot, "*.cs", SearchOption.AllDirectories)
            .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                           && !path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")
                           && Path.GetFileName(path) != "MetadataPill.cs"
                           && Regex.IsMatch(File.ReadAllText(path), @"\.(Fill|Stroke|Text)Key\b"))
            .Select(Path.GetFileName).ToList();
        Assert.Empty(offenders);
    }
}
