using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #315 (pattern <c>song-header</c>) in markup: every song header draws the song title and its artist
/// line through the one shared <c>Controls/SongHeaderText</c> column (one-line <c>MarqueeText</c>s that scroll only when
/// they overflow, ellipsize with motion off and wrap in-page at large text) instead of a page-local <c>TextBlock</c> or
/// <c>MarqueeText</c>, like the web <c>SongInfoHeader</c>. The pinned bar copy uses the column's <c>Bar</c> variant.
/// </summary>
public class SongHeaderMarkupTests
{
    /// <summary>Loads an app XAML file.</summary>
    /// <param name="file">Path under <c>Festival.App</c>, e.g. <c>Pages/SongDetailPage.xaml</c>.</param>
    /// <returns>The document.</returns>
    private static XDocument Load(string file) => XDocument.Load(AppPath(file));

    /// <summary>Absolute path of an app source file.</summary>
    /// <param name="file">Path under <c>Festival.App</c>.</param>
    /// <returns>Path.</returns>
    private static string AppPath(string file) =>
        Path.Combine(new[] { AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App" }.Concat(file.Split('/')).ToArray());

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Elements whose <paramref name="attribute"/> binds exactly to <paramref name="binding"/>.</summary>
    /// <param name="doc">Page.</param>
    /// <param name="attribute">Attribute, e.g. <c>Text</c> or <c>Title</c>.</param>
    /// <param name="binding">Bound path, e.g. <c>ViewModel.Song.Title</c>.</param>
    /// <returns>Matching elements.</returns>
    private static List<XElement> BoundTo(XDocument doc, string attribute, string binding) =>
        doc.Descendants().Where(e => Attr(e, attribute) is { } text
            && (text.StartsWith("{x:Bind " + binding + ",", StringComparison.Ordinal) || text == "{x:Bind " + binding + "}")).ToList();

    /// <summary>Shared song header columns of a page.</summary>
    /// <param name="doc">Page.</param>
    /// <returns><c>SongHeaderText</c> elements.</returns>
    private static List<XElement> HeaderTexts(XDocument doc) => doc.Descendants().Where(e => e.Name.LocalName == "SongHeaderText").ToList();

    [Fact]
    public void SongDetail_HeroAndPinnedBar_UseTheSharedColumn()
    {
        var doc = Load("Pages/SongDetailPage.xaml");
        var headers = HeaderTexts(doc);
        Assert.Equal(2, headers.Count);
        Assert.All(headers, h =>
        {
            Assert.Equal("{x:Bind ViewModel.Song.Title, Mode=OneWay}", Attr(h, "Title"));
            Assert.Equal("{x:Bind ViewModel.Song.Subtitle, Mode=OneWay}", Attr(h, "Artist"));
        });
        var hero = Assert.Single(headers, h => Attr(h, "TitleAutomationId") == "fst.song-detail.title");
        Assert.Null(Attr(hero, "Variant"));
        Assert.Equal("fst.song-detail.artist", Attr(hero, "ArtistAutomationId"));
        var bar = Assert.Single(headers, h => Attr(h, "TitleAutomationId") == "fst.song-detail.pinned-title");
        Assert.Equal("Bar", Attr(bar, "Variant"));
        Assert.Equal("fst.song-detail.pinned-artist", Attr(bar, "ArtistAutomationId"));
        // No page-local line draws the song any more.
        Assert.Empty(BoundTo(doc, "Text", "ViewModel.Song.Title"));
        Assert.Empty(BoundTo(doc, "Text", "ViewModel.Song.Subtitle"));
    }

    [Fact]
    public void SongLeaderboardHeader_UsesTheSharedColumn()
    {
        var doc = Load("Controls/SongLeaderboardHeader.xaml");
        var header = Assert.Single(HeaderTexts(doc));
        Assert.Equal("{x:Bind Title, Mode=OneWay}", Attr(header, "Title"));
        Assert.Equal("{x:Bind Artist, Mode=OneWay}", Attr(header, "Artist"));
        Assert.Null(Attr(header, "Variant"));
        Assert.Empty(BoundTo(doc, "Text", "Title"));
        Assert.Empty(BoundTo(doc, "Text", "Artist"));
    }

    [Theory]
    [InlineData("Pages/LeaderboardsSongPage.xaml")]
    [InlineData("Pages/BandsSongLeaderboardPage.xaml")]
    [InlineData("Pages/PlayerHistoryPage.xaml")]
    public void SongLeaderboards_UseTheSharedHeader(string file)
    {
        var doc = Load(file);
        var header = Assert.Single(doc.Descendants(), e => e.Name.LocalName == "SongLeaderboardHeader");
        Assert.Equal("{x:Bind ViewModel.Title, Mode=OneWay}", Attr(header, "Title"));
        Assert.Equal("{x:Bind ViewModel.Subtitle, Mode=OneWay}", Attr(header, "Artist"));
        Assert.DoesNotContain(doc.Descendants(), e => Attr(e, "Text") is { } text
            && (text.Contains("ViewModel.Title,", StringComparison.Ordinal) || text.Contains("ViewModel.Subtitle,", StringComparison.Ordinal)));
    }
}
