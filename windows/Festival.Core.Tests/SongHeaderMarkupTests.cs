using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #315 (pattern <c>song-header</c>) in markup: every song header draws the song title and its artist
/// line with the shared <c>Controls/MarqueeText</c> (one line across the column, scrolling only when it overflows,
/// ellipsized when motion is off) instead of a wrapping or clipping <c>TextBlock</c>, like the web <c>SongInfoHeader</c>.
/// </summary>
public class SongHeaderMarkupTests
{
    /// <summary>Loads an app XAML file.</summary>
    /// <param name="file">Path under <c>Festival.App</c>, e.g. <c>Pages/SongDetailPage.xaml</c>.</param>
    /// <returns>The document.</returns>
    private static XDocument Load(string file) => XDocument.Load(
        Path.Combine(new[] { AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App" }.Concat(file.Split('/')).ToArray()));

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Elements whose <c>Text</c> binds exactly to <paramref name="binding"/>.</summary>
    /// <param name="doc">Page.</param>
    /// <param name="binding">Bound path, e.g. <c>ViewModel.Song.Title</c>.</param>
    /// <returns>Matching elements.</returns>
    private static List<XElement> BoundTo(XDocument doc, string binding) =>
        doc.Descendants().Where(e => Attr(e, "Text") is { } text && text.StartsWith("{x:Bind " + binding + ",", StringComparison.Ordinal)
            || Attr(e, "Text") == "{x:Bind " + binding + "}").ToList();

    [Theory]
    [InlineData("Pages/SongDetailPage.xaml", "ViewModel.Song.Title")]
    [InlineData("Pages/SongDetailPage.xaml", "ViewModel.Song.Subtitle")]
    [InlineData("Controls/SongLeaderboardHeader.xaml", "Title")]
    [InlineData("Controls/SongLeaderboardHeader.xaml", "Artist")]
    [InlineData("Pages/PlayerHistoryPage.xaml", "ViewModel.Subtitle")]
    public void SongHeaderLines_AreMarquees(string file, string binding)
    {
        var lines = BoundTo(Load(file), binding);
        Assert.NotEmpty(lines);
        Assert.All(lines, line => Assert.Equal("MarqueeText", line.Name.LocalName));
    }

    [Theory]
    [InlineData("Pages/SongDetailPage.xaml", "fst.song-detail.title")]
    [InlineData("Controls/SongLeaderboardHeader.xaml", "{x:Bind TitleAutomationId, Mode=OneWay}")]
    public void SongTitle_IsTheLevelOneHeading(string file, string id)
    {
        var title = Load(file).Descendants().Single(e => Attr(e, "AutomationProperties.AutomationId") == id);
        Assert.Equal("MarqueeText", title.Name.LocalName);
        Assert.Equal("Level1", Attr(title, "AutomationProperties.HeadingLevel"));
    }

    [Theory]
    [InlineData("Pages/LeaderboardsSongPage.xaml")]
    [InlineData("Pages/BandsSongLeaderboardPage.xaml")]
    public void SongLeaderboards_UseTheSharedHeader(string file)
    {
        var doc = Load(file);
        var header = Assert.Single(doc.Descendants(), e => e.Name.LocalName == "SongLeaderboardHeader");
        Assert.Equal("{x:Bind ViewModel.Title, Mode=OneWay}", Attr(header, "Title"));
        Assert.Equal("{x:Bind ViewModel.Subtitle, Mode=OneWay}", Attr(header, "Artist"));
        Assert.DoesNotContain(doc.Descendants(), e => e.Name.LocalName == "TextBlock" && Attr(e, "Text") is { } text
            && (text.Contains("ViewModel.Title,", StringComparison.Ordinal) || text.Contains("ViewModel.Subtitle,", StringComparison.Ordinal)));
    }
}
