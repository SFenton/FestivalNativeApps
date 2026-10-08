using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Settings list/detail rules (issue #371).</summary>
public class SettingsDetailsTests
{
    private static (SettingsViewModel Vm, InMemorySettingsStore Store) Create(AppSettings? settings = null)
    {
        var store = new InMemorySettingsStore(settings);
        var session = new FestivalSession(new FakeService().Client(), store);
        return (new SettingsViewModel(session, "0.1.0"), store);
    }

    [Theory]
    [InlineData(1099.9, false)]
    [InlineData(1100, true)]
    [InlineData(1600, true)]
    [InlineData(0, false)]
    public void UsesSplit_FromSharedListDetailWidth(double width, bool split) =>
        Assert.Equal(split, SettingsDetails.UsesSplit(width));

    [Fact]
    public void Items_CoverEveryEntryOnceInPageOrderWithOwnerNamedSections()
    {
        var details = SettingsDetails.Items.Select(i => i.Detail).ToList();
        Assert.Equal(Enum.GetValues<SettingsDetail>().Where(d => d != SettingsDetail.None), details);
        Assert.Equal(details.Count, SettingsDetails.Items.Select(i => i.AutomationId).Distinct().Count());
        Assert.All(SettingsDetails.Items, i => Assert.StartsWith("fst.settings.detail-row.", i.AutomationId));
        string[] ownerNamed = ["Show Instruments", "Item Shop", "Accessibility", "Show Instrument Metadata", "Festival Score Tracker Version",
            "Service Info", "First Run Guides", "Licenses", "Privacy Policy"];
        Assert.All(ownerNamed, title => Assert.Contains(SettingsDetails.Items, i => i.Title == title));
        Assert.Null(SettingsDetails.Item(SettingsDetail.Metadata).Description);
        Assert.Throws<ArgumentOutOfRangeException>(() => SettingsDetails.Item(SettingsDetail.None));
        Assert.Equal("Select a setting to see more options here", SettingsDetails.PlaceholderMessage);
    }

    [Fact]
    public void Availability_FollowsTheSwitchesThatRevealSubsettings()
    {
        var off = new AppSettings() with { EnableVisualOrder = false, FilterInvalidScores = false };
        var on = off with { EnableVisualOrder = true, FilterInvalidScores = true };
        Assert.False(SettingsDetails.IsAvailable(SettingsDetail.None, on));
        Assert.False(SettingsDetails.IsAvailable(SettingsDetail.SongRowOrder, off));
        Assert.False(SettingsDetails.IsAvailable(SettingsDetail.Leeway, off));
        Assert.True(SettingsDetails.IsAvailable(SettingsDetail.SongRowOrder, on));
        Assert.True(SettingsDetails.IsAvailable(SettingsDetail.Leeway, on));
        Assert.True(SettingsDetails.IsAvailable(SettingsDetail.Licenses, off));
        Assert.False(SettingsDetails.IsAvailable((SettingsDetail)99, on));
        Assert.Equal(SettingsDetail.None, SettingsDetails.Reconcile(SettingsDetail.Leeway, off));
        Assert.Equal(SettingsDetail.Leeway, SettingsDetails.Reconcile(SettingsDetail.Leeway, on));
    }

    [Fact]
    public void QuickLinkId_MapsEverySectionRowToItsQuickLinkInMenuOrder()
    {
        var (vm, _) = Create();
        var sectionIds = vm.QuickLinks.Items.Select(i => i.Section.Id).Where(id => id is not "app-settings" and not "reset");
        Assert.Equal(sectionIds, SettingsDetails.Items.Select(i => SettingsDetails.QuickLinkId(i.Detail)).OfType<string>());
        Assert.Null(SettingsDetails.QuickLinkId(SettingsDetail.Leeway));
        Assert.Null(SettingsDetails.QuickLinkId(SettingsDetail.None));
    }

    [Fact]
    public void Value_ShowsChoiceAndLeeway()
    {
        var settings = new AppSettings() with { PathDefaultView = PathDisplayMode.Text, Leeway = 1.5 };
        Assert.Equal("Text", SettingsDetails.Value(SettingsDetail.PathDefaultView, settings));
        Assert.Equal("Image", SettingsDetails.Value(SettingsDetail.PathDefaultView, settings with { PathDefaultView = PathDisplayMode.Image }));
        Assert.Equal("+1.5%", SettingsDetails.Value(SettingsDetail.Leeway, settings));
        Assert.Equal("", SettingsDetails.Value(SettingsDetail.ItemShop, settings));
    }

    [Fact]
    public void ViewModel_TogglesKeepTheSelectionAndHiddenRowsReturnToPlaceholder()
    {
        var (vm, store) = Create(new AppSettings() with { FilterInvalidScores = true, EnableVisualOrder = false });
        var changes = new List<string?>();
        vm.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        Assert.Equal(SettingsDetail.None, vm.SelectedDetail);
        Assert.True(vm.HasLeewayRow);
        Assert.False(vm.HasSongRowOrderRow);

        vm.SelectDetail(SettingsDetail.SongRowOrder);
        Assert.Equal(SettingsDetail.None, vm.SelectedDetail);

        vm.SelectDetail(SettingsDetail.Instruments);
        Assert.Equal(SettingsDetail.Instruments, vm.SelectedDetail);
        Assert.Contains(nameof(SettingsViewModel.SelectedDetail), changes);
        vm.ShowInstrumentIcons = !vm.ShowInstrumentIcons;
        vm.HideShop = true;
        Assert.Equal(SettingsDetail.Instruments, vm.SelectedDetail);

        vm.SelectDetail(SettingsDetail.Leeway);
        Assert.Equal(SettingsDetail.Leeway, vm.SelectedDetail);
        vm.FilterInvalidScores = false;
        Assert.False(store.Current.FilterInvalidScores);
        Assert.False(vm.HasLeewayRow);
        Assert.Equal(SettingsDetail.None, vm.SelectedDetail);

        vm.PathDefaultViewIndex = 1;
        Assert.Equal("Text", vm.PathDefaultViewValue);
        vm.EnableVisualOrder = true;
        Assert.True(vm.HasSongRowOrderRow);
        vm.SelectDetail(SettingsDetail.SongRowOrder);
        vm.ResetAppSettingsCommand.Execute(null);
        Assert.Equal(SettingsDetail.None, vm.SelectedDetail);
    }
}
