using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>Shared metadata geometry, contrast and consumer/lifecycle regression guards.</summary>
public class MetadataPillTests
{
    private static readonly string AppRoot =
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App"));

    #region Geometry
    [Theory]
    [InlineData(2, 1, 48)]
    [InlineData(3, 2.25, 108)]
    [InlineData(5, 1, 63)]
    public void SeasonColumnIncludesPillPadding(int characters, double scale, double expected) =>
        Assert.Equal(expected, MetadataPillMetrics.SeasonColumnWidth(characters, scale));

    [Fact]
    public void SharedMetricsMatchEveryConsumer()
    {
        Assert.Equal(14, MetadataPillMetrics.FontSize);
        Assert.Equal(24, MetadataPillMetrics.Height);
        Assert.Equal(48, MetadataPillMetrics.SeasonWidth);
        Assert.Equal(77, MetadataPillMetrics.PercentileWidth);
        Assert.Equal(2, MetadataPillMetrics.Stroke);
        foreach (var file in new[] { "SongRowVisuals.cs", "SuggestionSongRow.cs", "LeaderboardEntryRow.xaml.cs",
                     "PlayerPercentileRowView.cs", "FirstRunDemo.cs", "PercentilePillView.cs" })
            Assert.Contains("MetadataPills.", File.ReadAllText(Path.Combine(AppRoot, "Controls", file)));
        var band = File.ReadAllText(Path.Combine(AppRoot, "Pages", "BandsDetailPage.xaml"));
        Assert.Equal(2, System.Text.RegularExpressions.Regex.Matches(band, "<controls:PercentilePillView ").Count);
        Assert.DoesNotContain("FSTPercentilePillFillBrush", band);
    }
    #endregion

    #region Contrast
    [Fact]
    public void SeasonColorsMatchTheInvertedIosPairAndExceedSevenToOne()
    {
        var normal = Dictionary("Default");
        var fill = Color(normal, "FSTSeasonFillBrush");
        var text = Color(normal, "FSTSeasonTextBrush");
        Assert.Equal("#FF162133", fill);
        Assert.Equal("#FFD7DEE8", text);
        Assert.Equal(fill, Color(normal, "FSTCurrentSeasonTextBrush"));
        Assert.Equal(text, Color(normal, "FSTCurrentSeasonFillBrush"));
        Assert.True(Contrast(fill, text) >= 7);
    }

    [Theory]
    [InlineData("FSTSeasonFillBrush", "SystemColorButtonFaceColor")]
    [InlineData("FSTSeasonTextBrush", "SystemColorButtonTextColor")]
    [InlineData("FSTSeasonStrokeBrush", "SystemColorButtonTextColor")]
    [InlineData("FSTCurrentSeasonFillBrush", "SystemColorHighlightColor")]
    [InlineData("FSTCurrentSeasonTextBrush", "SystemColorHighlightTextColor")]
    public void ContrastThemeUsesSystemPairs(string key, string systemColor) =>
        Assert.Equal("{ThemeResource " + systemColor + "}", Color(Dictionary("HighContrast"), key));

    [Fact]
    public void FactoryPillsOwnLiveThemeRepaintWithoutLeakingUnloadedHosts()
    {
        var factory = File.ReadAllText(Path.Combine(AppRoot, "Controls", "MetadataPills.cs"));
        var host = File.ReadAllText(Path.Combine(AppRoot, "Controls", "MetadataPill.cs"));
        Assert.Contains("pill.RefreshColors = () =>", factory);
        Assert.Contains("ContrastTheme.Brush(fill)", factory);
        Assert.Contains("ContrastTheme.Brush(foreground)", factory);
        Assert.Contains("ContrastTheme.Brush(stroke)", factory);
        Assert.Contains("Services.ContrastTheme.Changed += OnColorsChanged", host);
        Assert.Contains("Unloaded += (_, _) => Services.ContrastTheme.Changed -= OnColorsChanged", host);
        Assert.Contains("if (IsLoaded) RefreshColors?.Invoke()", host);
        Assert.DoesNotContain("Height = MetadataPillMetrics.Height", factory.Replace("MinHeight = MetadataPillMetrics.Height", ""));
    }

    /// <summary>Loads one theme dictionary.</summary>
    /// <param name="key">Theme.</param>
    /// <returns>Dictionary.</returns>
    private static XElement Dictionary(string key) => XDocument.Load(Path.Combine(AppRoot, "Themes", "Styles.xaml"))
        .Descendants().Single(e => e.Name.LocalName == "ResourceDictionary" && Attr(e, "Key") == key);

    /// <summary>Reads an XML attribute independent of its namespace.</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Attribute.</param>
    /// <returns>Value.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Reads a brush's declared colour.</summary>
    /// <param name="dictionary">Theme.</param>
    /// <param name="key">Brush.</param>
    /// <returns>Colour.</returns>
    private static string Color(XElement dictionary, string key) =>
        Attr(dictionary.Elements().Single(e => Attr(e, "Key") == key), "Color")!;

    /// <summary>WCAG contrast of two opaque ARGB colours.</summary>
    /// <param name="a">First colour.</param>
    /// <param name="b">Second colour.</param>
    /// <returns>Contrast ratio.</returns>
    private static double Contrast(string a, string b)
    {
        static double Luminance(string color)
        {
            static double Linear(string hex)
            {
                var channel = Convert.ToInt32(hex, 16) / 255d;
                return channel <= 0.04045 ? channel / 12.92 : Math.Pow((channel + 0.055) / 1.055, 2.4);
            }
            return 0.2126 * Linear(color[3..5]) + 0.7152 * Linear(color[5..7]) + 0.0722 * Linear(color[7..9]);
        }
        var first = Luminance(a);
        var second = Luminance(b);
        return (Math.Max(first, second) + 0.05) / (Math.Min(first, second) + 0.05);
    }
    #endregion
}
