using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #546: every <c>ItemsRepeater</c> on Settings (Show Instruments, Show Instrument Metadata, First Run
/// Guides) lays its short fixed list out with the non-virtualizing stack. The default virtualizing <c>StackLayout</c>
/// realizes nothing while the card is off screen, so the page extent above later sections is an estimate: at 225% text
/// What's New moved off screen after being scrolled to, and a Quick Links jump to Show Instruments landed before its
/// first toggle existed, leaving focus on the off-screen Quick Links button.
/// </summary>
public class SettingsRealizationMarkupTests
{
    private static readonly string SettingsPage =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App", "Pages", "SettingsPage.xaml");

    /// <summary>Reads an attribute by local name.</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Attribute local name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    [Fact]
    public void EveryRepeater_UsesTheNonVirtualizingStack()
    {
        var repeaters = XDocument.Load(SettingsPage).Descendants().Where(e => e.Name.LocalName == "ItemsRepeater").ToList();
        Assert.Equal(3, repeaters.Count);
        foreach (var repeater in repeaters)
        {
            var source = Attr(repeater, "ItemsSource");
            var layout = repeater.Elements().FirstOrDefault(e => e.Name.LocalName == "ItemsRepeater.Layout")?.Elements().SingleOrDefault();
            Assert.True(layout is not null, $"{source} keeps the virtualizing default layout");
            Assert.Equal("LeaderboardsCardGridLayout", layout!.Name.LocalName);
            Assert.Equal("1", Attr(layout, "MaxColumns"));
            Assert.Equal("0", Attr(layout, "MinColumnWidth"));
        }
    }
}
