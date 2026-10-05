using System.Xml.Linq;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issues #50/#250 (iOS #11: Quick Links listed nested sections bottom-up): every Windows Quick Links page declares
/// its sections in a view model while the XAML lays them out, so the two lists could drift apart. These tests read each
/// page's <c>QuickLinkAnchor.Id</c> markers in document order (every Quick Links page is a single vertical stack, with
/// repeated cards in row-major repeaters) and require the declared menu order to match. The live check that the real menu
/// matches on-screen geometry is <c>tools/windows/journeys/quick-links-order.json</c>, plus the Settings and profile
/// <c>ql-menu-order</c>/<c>ql-pane-order</c>/<c>ql-profile-*-order</c> journeys in <c>quick-links.json</c> (#46/#246).
/// </summary>
public class QuickLinksOrderMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    #region Helpers

    /// <summary>
    /// The page's anchors in document order: a literal ID, or <c>template:&lt;x:DataType&gt;</c> for an anchor bound inside
    /// a repeater's item template (one anchor per item, in item order).
    /// </summary>
    /// <param name="relative">XAML path under Festival.App.</param>
    /// <returns>Anchor tokens in document order.</returns>
    private static List<string> Anchors(string relative)
    {
        var doc = XDocument.Load(Path.Combine(AppRoot, relative));
        return [.. doc.Descendants()
            .Select(e => (Element: e, Id: e.Attributes().FirstOrDefault(a => a.Name.LocalName == "QuickLinkAnchor.Id")?.Value))
            .Where(x => x.Id is not null)
            .Select(x => x.Id!.StartsWith('{') ? "template:" + TemplateType(x.Element) : x.Id!)];
    }

    /// <summary>The nearest enclosing <c>DataTemplate</c>'s <c>x:DataType</c> without its XML prefix.</summary>
    /// <param name="element">Anchor element.</param>
    /// <returns>Type name.</returns>
    private static string TemplateType(XElement element)
    {
        var type = element.Ancestors().First(a => a.Name.LocalName == "DataTemplate")
            .Attributes().First(a => a.Name.LocalName == "DataType").Value;
        return type[(type.IndexOf(':') + 1)..];
    }

    /// <summary>Collapses runs of the same kind, so many template items compare with one template anchor.</summary>
    /// <param name="kinds">Kinds in order.</param>
    /// <returns>Kinds without consecutive repeats.</returns>
    private static List<string> Runs(IEnumerable<string> kinds)
    {
        var runs = new List<string>();
        foreach (var kind in kinds)
            if (runs.Count == 0 || runs[^1] != kind) runs.Add(kind);
        return runs;
    }

    #endregion

    [Fact]
    public void Settings_DeclaredOrderMatchesMarkup()
    {
        var vm = new SettingsViewModel(new FestivalSession(new FakeService().Client(), new InMemorySettingsStore()), "0.1.0", true);
        Assert.Equal(Anchors("Pages/SettingsPage.xaml"), vm.QuickLinks.Items.Select(i => i.Section.Id));
    }

    [Fact]
    public void SettingsRelease_DropsOnlyDiagnostics()
    {
        var vm = new SettingsViewModel(new FestivalSession(new FakeService().Client(), new InMemorySettingsStore()), "0.1.0", false);
        Assert.Equal(Anchors("Pages/SettingsPage.xaml").Where(id => id != "diagnostics"), vm.QuickLinks.Items.Select(i => i.Section.Id));
    }

    [Fact]
    public void BandDetail_DeclaredOrderMatchesMarkup() =>
        Assert.Equal(Anchors("Pages/BandsDetailPage.xaml"), BandDetailViewModel.QuickLinkSections.Select(s => s.Id));

    [Fact]
    public void SongDetail_MarkupOrderIsIntensityHistoryInstrumentsBands() =>
        Assert.Equal(
            ["intensity", SongDetailViewModel.HistoryQuickLinkId, "template:LeaderboardPreviewViewModel", "template:SongBandPreviewViewModel"],
            Anchors("Pages/SongDetailPage.xaml"));

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task SongDetail_DeclaredOrderFollowsMarkup(bool player)
    {
        var service = new FakeService();
        SongsWire.Install(service, player: player);
        if (player)
        {
            var inner = service.Override!;
            service.Override = r => r.RequestUri!.AbsolutePath.EndsWith("/history", StringComparison.Ordinal)
                ? Wire.Ok(PlayerWire.History(PlayerWire.Id, PlayerWire.HistoryEntry("s1", "Solo_Bass", 50)), ("X-FST-Publication-Id", "7"))
                : inner(r);
        }
        var session = service.Session(settings: player ? new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") } : null);
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        if (player) await Async.Until(() => vm.History.IsVisible);
        Assert.NotEmpty(vm.Leaderboards);
        await Async.Until(() => vm.BandPreviews.Count > 0);

        // Score History is listed exactly when the page shows its section (both read History.IsVisible).
        Assert.Equal(player, vm.History.IsVisible);
        var kinds = Runs(vm.QuickLinkSections.Select(s => s.Id switch
        {
            var id when vm.Leaderboards.Any(c => c.QuickLinkId == id) => "template:LeaderboardPreviewViewModel",
            var id when vm.BandPreviews.Any(b => b.QuickLinkId == id) => "template:SongBandPreviewViewModel",
            var id => id,
        }));
        Assert.Equal(Anchors("Pages/SongDetailPage.xaml").Where(t => player || t != SongDetailViewModel.HistoryQuickLinkId), kinds);
        vm.Detach();
    }

    [Fact]
    public void PlayerProfile_MarkupOrderIsGlobalInstrumentsBands() =>
        Assert.Equal(["global", "template:PlayerInstrumentViewModel", "bands"], Anchors("Controls/PlayerProfileView.xaml"));

    [Fact]
    public void Leaderboards_MarkupOrderIsInstrumentCardsThenBandCards() =>
        Assert.Equal(["template:RankingCardViewModel", "template:BandRankingCardViewModel"], Anchors("Pages/LeaderboardsPage.xaml"));

    [Theory]
    [InlineData("Pages/RivalsPage.xaml", "template:RivalSectionViewModel")]
    [InlineData("Pages/RivalDetailPage.xaml", "template:RivalCategoryItem")]
    public void SingleRepeaterPages_HaveOneTemplatedAnchor(string page, string expected) =>
        Assert.Equal([expected], Anchors(page));
}
