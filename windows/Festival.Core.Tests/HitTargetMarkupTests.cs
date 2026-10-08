using System.Globalization;
using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #72: title-bar and page tool buttons keep Fluent's 40x40 epx minimum touch target
/// (<c>FSTMinTargetSize</c>), so a tap just beside the glyph still activates them. The live check is the hit-target
/// journey (<c>tools/windows/journeys/a11y-hit-targets.json</c>, issue #271); this keeps the markup from regressing.
/// </summary>
public class HitTargetMarkupTests
{
    private const string Resource = "{StaticResource FSTMinTargetSize}";

    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    #region Helpers

    /// <summary>Loads a Festival.App XAML file.</summary>
    /// <param name="relative">Path under Festival.App.</param>
    /// <returns>The parsed document.</returns>
    private static XDocument Load(string relative) => XDocument.Load(Path.Combine(AppRoot, relative));

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Finds every button with a given UIA AutomationId (the wide title-bar search box shares its button's ID).</summary>
    /// <param name="doc">Document.</param>
    /// <param name="id">AutomationId.</param>
    /// <returns>Matching button elements.</returns>
    private static List<XElement> ById(XDocument doc, string id) =>
        doc.Descendants().Where(e => e.Name.LocalName.EndsWith("Button", StringComparison.Ordinal)
                                     && Attr(e, "AutomationProperties.AutomationId") == id).ToList();

    #endregion

    [Fact]
    public void MinTargetResource_IsFluentMinimum()
    {
        var value = Load(Path.Combine("Themes", "Styles.xaml")).Descendants()
            .Single(e => e.Name.LocalName == "Double" && Attr(e, "Key") == "FSTMinTargetSize").Value;
        Assert.True(double.Parse(value, CultureInfo.InvariantCulture) >= 40);
    }

    [Theory]
    [InlineData("MainWindow.xaml", "fst.global-search.open", true)]
    [InlineData("MainWindow.xaml", "fst.shell.profile", true)]
    [InlineData("Controls/NotificationsBell.xaml", "fst.shell.notifications", true)]
    [InlineData("Pages/SongsPage.xaml", "fst.songs.sort", false)]
    [InlineData("Pages/SongsPage.xaml", "fst.songs.filter", false)]
    [InlineData("Pages/SongsPage.xaml", "fst.songs.section-index-button", true)]
    [InlineData("Pages/SuggestionsPage.xaml", "fst.suggestions.filter-button", false)]
    [InlineData("Pages/PlayerHistoryPage.xaml", "fst.history.sort.open", false)]
    [InlineData("Pages/LeaderboardsPage.xaml", "fst.rankings.rank-by-menu", false)]
    [InlineData("Pages/ShopPage.xaml", "fst.shop.sort", false)]
    [InlineData("Pages/ShopPage.xaml", "fst.shop.filter", false)]
    [InlineData("Pages/ShopPage.xaml", "fst.shop.view-toggle", false)]
    [InlineData("Pages/RivalDetailPage.xaml", "fst.rival-detail.view-profile", false)]
    [InlineData("Pages/LeaderboardsFullRankingsPage.xaml", "fst.full-rankings.instrument-menu", false)]
    [InlineData("Pages/LeaderboardsFullRankingsPage.xaml", "fst.rankings.rank-by-menu", false)]
    [InlineData("Pages/LeaderboardsBandRankingsPage.xaml", "fst.band-rankings.band-type-menu", false)]
    [InlineData("Pages/LeaderboardsBandRankingsPage.xaml", "fst.band-rankings.rank-by-menu", false)]
    [InlineData("Pages/SongDetailPage.xaml", "fst.song-detail.pinned-paths", false)]
    public void ToolButtons_UseMinTarget(string file, string id, bool iconOnly)
    {
        var button = Assert.Single(ById(Load(file), id));
        Assert.Equal(Resource, Attr(button, "MinHeight"));
        // Labelled buttons are already wider than 40; icon-only ones need the width too.
        if (iconOnly) Assert.Equal(Resource, Attr(button, "MinWidth"));
    }

[Fact]
    public void EveryDropDownButton_UsesMinTarget()
    {
        // Issue #271: #72 listed its buttons one by one and missed the Full/Band Rankings pickers (31 epx tall). Every
        // DropDownButton in the app is a page tool (sort, filter, picker), so the rule covers them all.
        var buttons = Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
            .Where(path => Path.GetRelativePath(AppRoot, path).Split(Path.DirectorySeparatorChar)[0] is not ("bin" or "obj"))
            .SelectMany(path => XDocument.Load(path).Descendants()
                .Where(e => e.Name.LocalName == "DropDownButton")
                .Select(e => (File: Path.GetFileName(path), Id: Attr(e, "AutomationProperties.AutomationId"), MinHeight: Attr(e, "MinHeight"))))
            .ToList();
        Assert.True(buttons.Count >= 10, $"found only {buttons.Count} DropDownButtons");
        Assert.All(buttons, b => Assert.True(b.MinHeight == Resource, $"{b.File} {b.Id}: MinHeight {b.MinHeight ?? "unset"}"));
    }

    [Fact]
    public void TitleBar_RecomputesPassthroughAfterDynamicChanges()
    {
        // Issue #271: the TitleBar computes its clickable (passthrough) regions before the search box/button swap and
        // the bell settle, so part of the compact Search button, or the whole box after resizing up, dragged the window.
        var code = File.ReadAllText(Path.Combine(AppRoot, "MainWindow.TitleBar.cs"));
        Assert.Contains("AppTitleBar.RecomputeDragRegions();", code, StringComparison.Ordinal);
        foreach (var trigger in new[]
                 {
                     "RootGrid.SizeChanged += (_, _) => QueueDragRegionRefresh();",
                     "TitleBarRightHeader.SizeChanged += (_, _) => QueueDragRegionRefresh();",
                     "GlobalSearchBox.SizeChanged += (_, _) => QueueDragRegionRefresh();",
                     "TitleBar.TitleProperty, (_, _) => QueueDragRegionRefresh()",
                 })
        {
            Assert.Contains(trigger, code, StringComparison.Ordinal);
        }
        var header = Load("MainWindow.xaml").Descendants().Single(e => e.Name.LocalName == "TitleBar.RightHeader");
        Assert.Equal("TitleBarRightHeader", Attr(header.Elements().Single(), "Name"));
    }

    [Fact]
    public void QuickLinks_KeepsMinTarget()
    {
        var source = File.ReadAllText(Path.Combine(AppRoot, "Controls", "QuickLinksMenuButton.cs"));
        Assert.Contains("public const double MinTargetSize = 40;", source);
        Assert.Contains("MinHeight = MinTargetSize;", source);
        // A page may restate the minimum (to match its neighbours) but never shrink it below 40.
        var hosts = Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
            .SelectMany(path => XDocument.Load(path).Descendants().Where(e => e.Name.LocalName == "QuickLinksMenuButton"))
            .ToList();
        Assert.NotEmpty(hosts);
        Assert.All(hosts, host => Assert.Contains(Attr(host, "MinHeight"), new[] { null, Resource }));
    }

    [Theory]
    [InlineData("MenuFlyoutItem", "DefaultMenuFlyoutItemStyle")]
    [InlineData("ToggleMenuFlyoutItem", "DefaultToggleMenuFlyoutItemStyle")]
    [InlineData("RadioMenuFlyoutItem", "DefaultRadioMenuFlyoutItemStyle")]
    public void MenuItems_UseMinTarget(string type, string basedOn)
    {
        // Issue #416: keyboard-opened menu items (Quick Links, Rank By, the rankings pickers, Player History Sort) were
        // 27 epx tall. One implicit style per item type (implicit styles match the exact type) keeps every menu's
        // hit-testable pill at 40: the template insets it by MenuFlyoutItemMargin's 2 epx top and bottom.
        var styles = Load(Path.Combine("Themes", "Styles.xaml"));
        var height = styles.Descendants()
            .Single(e => e.Name.LocalName == "Double" && Attr(e, "Key") == "FSTMenuItemMinHeight").Value;
        var target = styles.Descendants()
            .Single(e => e.Name.LocalName == "Double" && Attr(e, "Key") == "FSTMinTargetSize").Value;
        Assert.Equal(double.Parse(target, CultureInfo.InvariantCulture) + 4, double.Parse(height, CultureInfo.InvariantCulture));
        var style = styles.Descendants()
            .Single(e => e.Name.LocalName == "Style" && Attr(e, "TargetType") == type && Attr(e, "Key") is null);
        Assert.Equal($"{{StaticResource {basedOn}}}", Attr(style, "BasedOn"));
        var setter = style.Elements().Single(e => Attr(e, "Property") == "MinHeight");
        Assert.Equal("{StaticResource FSTMenuItemMinHeight}", Attr(setter, "Value"));
        // No item opts out with its own height or style.
        var items = Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
            .Where(path => Path.GetRelativePath(AppRoot, path).Split(Path.DirectorySeparatorChar)[0] is not ("bin" or "obj"))
            .SelectMany(path => XDocument.Load(path).Descendants().Where(e => e.Name.LocalName == type));
        Assert.All(items, item => Assert.True(Attr(item, "MinHeight") is null && Attr(item, "Height") is null && Attr(item, "Style") is null,
            $"{type} {Attr(item, "AutomationProperties.AutomationId")} overrides its size"));
    }

    [Fact]
    public void QuickLinksPane_RowsUseMinTarget()
    {
        // Issue #230: the wide pane's rows were 36 epx tall; each is a click/touch target like the menu items.
        var setter = Load(Path.Combine("Controls", "QuickLinksPane.xaml")).Descendants()
            .Where(e => e.Name.LocalName == "Style" && Attr(e, "TargetType") == "ListViewItem")
            .SelectMany(style => style.Elements().Where(e => e.Name.LocalName == "Setter"))
            .Single(e => Attr(e, "Property") == "MinHeight");
        Assert.Equal(Resource, Attr(setter, "Value"));
    }

    [Fact]
    public void QuickLinksPane_TitlesWrapInsteadOfClipping()
    {
        // Issue #230: in a horizontal StackPanel the title had infinite width, so at 200% text it was cut mid-word.
        var template = Load(Path.Combine("Controls", "QuickLinksPane.xaml")).Descendants()
            .Single(e => e.Name.LocalName == "DataTemplate");
        Assert.DoesNotContain(template.Descendants(), e => e.Name.LocalName == "StackPanel" && Attr(e, "Orientation") == "Horizontal");
        var title = template.Descendants().Single(e => e.Name.LocalName == "TextBlock" && Attr(e, "Text") == "{x:Bind Title}");
        Assert.Equal("Wrap", Attr(title, "TextWrapping"));
    }

    [Theory]
    [InlineData("Controls/ServiceStatusView.xaml")]
    [InlineData("Controls/ServiceStatusInline.xaml")]
    public void ServiceStatus_RetryUsesMinTargetAndCountdownCollapses(string file)
    {
        // Issue #233: Retry was 36 epx tall, and the always-present countdown left a blank line above it outside a freeze.
        var doc = Load(file);
        var named = doc.Descendants().Where(e => Attr(e, "Name") is not null).ToDictionary(e => Attr(e, "Name")!);
        Assert.Equal(Resource, Attr(named["RetryButton"], "MinHeight"));
        Assert.StartsWith("{x:Bind Status.HasCountdown", Attr(named["CountdownBlock"], "Visibility"));
        Assert.Equal("{x:Bind Status.CountdownAnnouncement, Mode=OneWay}", Attr(named["CountdownBlock"], "AutomationProperties.Name"));
        if (Attr(named["RetryButton"], "Style") == "{StaticResource AccentButtonStyle}")
        {
            // Under a contrast theme the accent button is already HighlightText on Highlight; the automatic backplate boxed the label.
            Assert.Equal("None", Attr(named["RetryButton"], "HighContrastAdjustment"));
        }
    }

    [Fact]
    public void TitleBar_BellAndProfileAreSeparateNamedButtons()
    {
        // Issue #253 (#53/#14): two independent title-bar buttons, each with its own action and UIA name, never one container.
        var header = Load("MainWindow.xaml").Descendants().Single(e => e.Name.LocalName == "TitleBar.RightHeader");
        var children = header.Elements().Single().Elements().Select(e => Attr(e, "Name")).ToList();
        Assert.Equal(["GlobalSearchButton", "NotificationsHost", "ProfileButton"], children);
        var profile = Assert.Single(ById(Load("MainWindow.xaml"), "fst.shell.profile"));
        Assert.Equal("{x:Bind Shell.ProfileButtonName, Mode=OneWay}", Attr(profile, "AutomationProperties.Name"));
        Assert.Equal("OnProfileButtonClick", Attr(profile, "Click"));
        var bell = Assert.Single(ById(Load(Path.Combine("Controls", "NotificationsBell.xaml")), "fst.shell.notifications"));
        Assert.Equal("{x:Bind Model.BellName, Mode=OneWay}", Attr(bell, "AutomationProperties.Name"));
        Assert.Contains(bell.Elements(), e => e.Name.LocalName == "Button.Flyout");
    }

    [Fact]
    public void NotificationsBadge_HasNoContrastBackplate()
    {
        // Issue #253: under a contrast theme the count drew WindowText on a clipped dark backplate inside the Highlight
        // circle. InfoBadge already pairs HighlightText with Highlight, so the badge and its template parts opt out.
        var badge = Load(Path.Combine("Controls", "NotificationsBell.xaml")).Descendants().Single(e => e.Name.LocalName == "InfoBadge");
        Assert.Equal("None", Attr(badge, "HighContrastAdjustment"));
        Assert.Equal("OnBadgeLayout", Attr(badge, "Loaded"));
        Assert.Equal("OnBadgeLayout", Attr(badge, "SizeChanged"));
        Assert.Equal("Raw", Attr(badge, "AutomationProperties.AccessibilityView"));
        var code = File.ReadAllText(Path.Combine(AppRoot, "Controls", "NotificationsBell.xaml.cs"));
        Assert.Contains("DialogChrome.WithoutBackplate(UnreadBadge)", code, StringComparison.Ordinal);
    }

    [Fact]
    public void ViewAllButtonsAndSelectedBandPreviewRow_HaveNoContrastBackplate()
    {
        // Issue #264: under a contrast theme the accent View Full Leaderboard / View All label and the selected band
        // preview row's text (HighlightText on Highlight) drew Window backplate boxes inside the fill.
        var style = Load(Path.Combine("Themes", "Styles.xaml")).Descendants()
            .Single(e => e.Name.LocalName == "Style" && e.Attributes().Any(a => a.Name.LocalName == "Key" && a.Value == "FSTViewAllButtonStyle"));
        Assert.Contains(style.Elements(), s => Attr(s, "Property") == "HighContrastAdjustment" && Attr(s, "Value") == "None");
        var members = Load(Path.Combine("Controls", "SongBandPreviewRowView.xaml")).Descendants()
            .Single(e => e.Name.LocalName == "ItemsRepeater" && e.Attributes().Any(a => a.Name.LocalName == "Name" && a.Value == "MembersRepeater"));
        Assert.Equal("OnMemberPrepared", Attr(members, "ElementPrepared"));
        var code = File.ReadAllText(Path.Combine(AppRoot, "Controls", "SongBandPreviewRowView.xaml.cs"));
        Assert.Contains("ElementHighContrastAdjustment.None", code, StringComparison.Ordinal);
        Assert.Contains("Chevron.HighContrastAdjustment = adjustment", code, StringComparison.Ordinal);
    }

    [Fact]
    public void ServiceStatus_PagesUseTheSharedControls()
    {
        // Issue #233: nine hand-copied inline rows had drifted (missing countdowns, live regions, IDs on panels UIA skips).
        var shared = new[] { "ServiceStatusView.xaml", "ServiceStatusInline.xaml" };
        var offenders = Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
            .Where(path => !shared.Contains(Path.GetFileName(path)) && !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}"))
            .Where(path => File.ReadAllText(path).Contains("fst.service-status", StringComparison.Ordinal)
                           || File.ReadAllText(path).Contains("Status.CountdownText", StringComparison.Ordinal))
            .Select(Path.GetFileName)
            .ToList();
        Assert.Empty(offenders);
        var inline = Load(Path.Combine("Pages", "SongDetailPage.xaml")).Descendants()
            .Where(e => e.Name.LocalName == "ServiceStatusInline").ToList();
        Assert.Contains(inline, e => Attr(e, "TitleAutomationId") == "fst.history.error" && Attr(e, "RetryAutomationId") == "fst.history.retry");
    }
}
