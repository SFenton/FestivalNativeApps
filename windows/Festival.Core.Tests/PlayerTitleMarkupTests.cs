using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issues #97 and #285: the player profile (and Statistics, which reuses the view) opens on the player's name as
/// a plain H1 with no avatar or card around it, then the identity actions, the selection notices and Overview. The
/// actions wrap so Quick Links never clips at large text sizes. The live checks are the
/// <c>tools/windows/journeys/a11y-profile-title.json</c> pages.
/// </summary>
public class PlayerTitleMarkupTests
{
    private static readonly string ViewPath = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..",
        "Festival.App", "Controls", "PlayerProfileView.xaml");

    #region Helpers

    /// <summary>Loads the profile view's XAML.</summary>
    /// <returns>The parsed document.</returns>
    private static XDocument Load() => XDocument.Load(ViewPath);

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Finds the element with an <c>x:Name</c>.</summary>
    /// <param name="doc">Document.</param>
    /// <param name="name">Name.</param>
    /// <returns>The element.</returns>
    private static XElement Named(XDocument doc, string name) =>
        doc.Descendants().Single(e => Attr(e, "Name") == name);

    /// <summary>Finds the element with an AutomationId.</summary>
    /// <param name="doc">Document.</param>
    /// <param name="id">AutomationId.</param>
    /// <returns>The element.</returns>
    private static XElement ById(XDocument doc, string id) =>
        doc.Descendants().Single(e => Attr(e, "AutomationProperties.AutomationId") == id);

    #endregion

    [Fact]
    public void Title_HasNoAvatarOrCard()
    {
        var doc = Load();
        Assert.DoesNotContain(doc.Descendants(), e => e.Name.LocalName == "PersonPicture");
        Assert.DoesNotContain(doc.Descendants(), e => Attr(e, "Name") == "HeaderCard");
        var title = Named(doc, "TitleRow");
        Assert.Equal("StackPanel", title.Name.LocalName);
        Assert.Null(Attr(title, "Style"));
        Assert.DoesNotContain(title.AncestorsAndSelf().Concat(title.Descendants()),
            e => e.Name.LocalName == "Border" || (Attr(e, "Style")?.Contains("FSTCardStyle", StringComparison.Ordinal) ?? false));
    }

    [Fact]
    public void Title_IsThePageHeadingFirst()
    {
        var doc = Load();
        var title = Named(doc, "TitleRow");
        var name = ById(doc, "fst.player.name");
        Assert.Same(title, name.Parent);
        Assert.Same(name, title.Elements().First());
        Assert.Equal("Level1", Attr(name, "AutomationProperties.HeadingLevel"));
        Assert.Equal("{StaticResource FSTPageTitleStyle}", Attr(name, "Style"));
        Assert.Equal("Wrap", Attr(name, "TextWrapping"));
        // Nothing precedes the title in the scroller's content, and Overview follows it directly.
        var content = title.Parent!;
        Assert.Same(title, content.Elements().First());
        Assert.Same(ById(doc, "fst.player.overview"), title.ElementsAfterSelf().First());
    }

    [Fact]
    public void Actions_WrapInReadingOrder()
    {
        var doc = Load();
        var actions = Named(doc, "TitleActions");
        Assert.Equal("WrapPanel", actions.Name.LocalName);
        Assert.Same(Named(doc, "TitleRow"), actions.Parent);
        var order = actions.Elements()
            .Select(e => Attr(e, "AutomationProperties.AutomationId") ?? Attr(e, "Name"))
            .ToList();
        Assert.Equal(["fst.player.select", "fst.player.deselect", "QuickLinksMenu"], order);
    }

    [Fact]
    public void Notices_FollowTheActionsWithoutAChip()
    {
        var doc = Load();
        var title = Named(doc, "TitleRow");
        var children = title.Elements().ToList();
        var notice = ById(doc, "fst.player.identity-notice");
        var error = ById(doc, "fst.player.action-error");
        Assert.Equal(["TextBlock", "WrapPanel", "TextBlock", "TextBlock"], children.Select(e => e.Name.LocalName));
        Assert.Same(notice, children[2]);
        Assert.Same(error, children[3]);
        Assert.Equal("Wrap", Attr(notice, "TextWrapping"));
        Assert.Equal("Wrap", Attr(error, "TextWrapping"));
        Assert.Equal("Assertive", Attr(error, "AutomationProperties.LiveSetting"));
    }
}
