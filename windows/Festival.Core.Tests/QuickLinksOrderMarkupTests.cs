using System.Xml.Linq;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #46/#246: the Quick Links menu and pane list sections in <see cref="QuickLinksViewModel.Items"/> order,
/// so each page's declared section list must follow its anchors' on-page (document) order. The UIA journeys
/// <c>ql-menu-order</c>/<c>ql-pane-order</c>/<c>ql-profile-*-order</c> in <c>tools/windows/journeys/quick-links.json</c>
/// check the rendered order; this keeps the declarations from drifting apart.
/// </summary>
public class QuickLinksOrderMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    /// <summary>Reads every <c>QuickLinkAnchor.Id</c> in document order.</summary>
    /// <param name="relative">Path under Festival.App.</param>
    /// <returns>Anchor IDs (or their binding expressions).</returns>
    private static List<string> Anchors(string relative) =>
        [.. XDocument.Load(Path.Combine(AppRoot, relative)).Descendants()
            .Select(e => e.Attributes().FirstOrDefault(a => a.Name.LocalName == "QuickLinkAnchor.Id")?.Value)
            .OfType<string>()];

    [Fact]
    public void Settings_SectionsFollowPageOrder()
    {
        var vm = new SettingsViewModel(new FestivalSession(new FakeService().Client(), new InMemorySettingsStore()), "0.1.0", true);
        Assert.Equal(Anchors(Path.Combine("Pages", "SettingsPage.xaml")), vm.QuickLinks.Items.Select(i => i.Section.Id));
    }

    [Fact]
    public void PlayerProfile_SectionsFollowPageOrder()
    {
        // Overview, then one anchor per instrument card (in ViewModel.Instruments order, as QuickLinkSections), then Bands.
        Assert.Equal(["global", "{x:Bind QuickLinkId}", "bands"], Anchors(Path.Combine("Controls", "PlayerProfileView.xaml")));
    }
}
