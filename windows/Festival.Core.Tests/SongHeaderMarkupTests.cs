using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #315 (pattern <c>song-header</c>) in markup: every song header draws the song title and its artist
/// line with the shared <c>Controls/MarqueeText</c> (one line across the column, scrolling only when it overflows,
/// ellipsized when motion is off) instead of a wrapping or clipping <c>TextBlock</c>, like the web <c>SongInfoHeader</c>.
/// </summary>
public class SongHeaderMarkupTests
{
    /// <summary>Loads a page's XAML.</summary>
    /// <param name="page">File name under <c>Festival.App/Pages</c>.</param>
    /// <returns>The document.</returns>
    private static XDocument Load(string page) => XDocument.Load(
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App", "Pages", page));

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
    [InlineData("SongDetailPage.xaml", "ViewModel.Song.Title")]
    [InlineData("SongDetailPage.xaml", "ViewModel.Song.Subtitle")]
    [InlineData("LeaderboardsSongPage.xaml", "ViewModel.Title")]
    [InlineData("LeaderboardsSongPage.xaml", "ViewModel.Subtitle")]
    [InlineData("BandsSongLeaderboardPage.xaml", "ViewModel.SongTitle")]
    [InlineData("BandsSongLeaderboardPage.xaml", "ViewModel.SongSubtitle")]
    [InlineData("PlayerHistoryPage.xaml", "ViewModel.Subtitle")]
    public void SongHeaderLines_AreMarquees(string page, string binding)
    {
        var lines = BoundTo(Load(page), binding);
        Assert.NotEmpty(lines);
        Assert.All(lines, line => Assert.Equal("MarqueeText", line.Name.LocalName));
    }

    [Theory]
    [InlineData("SongDetailPage.xaml", "fst.song-detail.title")]
    [InlineData("LeaderboardsSongPage.xaml", "fst.song-leaderboard.title")]
    public void SongTitle_IsTheLevelOneHeading(string page, string id)
    {
        var title = Load(page).Descendants().Single(e => Attr(e, "AutomationProperties.AutomationId") == id);
        Assert.Equal("MarqueeText", title.Name.LocalName);
        Assert.Equal("Level1", Attr(title, "AutomationProperties.HeadingLevel"));
    }

    [Fact]
    public void BandSongLink_IsNamedByTheTitleAndReadOnce()
    {
        var link = Load("BandsSongLeaderboardPage.xaml").Descendants()
            .Single(e => Attr(e, "AutomationProperties.AutomationId") == "fst.song-band-leaderboard.song");
        Assert.Equal("HyperlinkButton", link.Name.LocalName);
        Assert.Equal("{x:Bind ViewModel.SongTitle, Mode=OneWay}", Attr(link, "AutomationProperties.Name"));
        var marquee = Assert.Single(link.Elements());
        Assert.Equal("MarqueeText", marquee.Name.LocalName);
        Assert.Equal("Raw", Attr(marquee, "AutomationProperties.AccessibilityView"));
    }
}
