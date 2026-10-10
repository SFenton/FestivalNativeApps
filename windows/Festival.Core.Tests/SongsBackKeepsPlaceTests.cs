using System.ComponentModel;
using System.Text.Json;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>
/// Back to Songs keeps the list's item objects when nothing changed, so the page neither rebinds nor replays its entrance
/// fade and the virtualized list stays where the reader left it (back-keeps-place R2/R3, issue #560).
/// </summary>
public class SongsBackKeepsPlaceTests
{
    private static readonly Song Song = JsonSerializer.Deserialize<Song>("""{"songId":"s","title":"T","artist":"A"}""")!;

    private static List<string> SectionChanges(SongsViewModel vm)
    {
        var changes = new List<string>();
        vm.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(SongsViewModel.Sections) or nameof(SongsViewModel.Notices)) changes.Add(e.PropertyName!);
        };
        return changes;
    }

    [Fact]
    public async Task Reappear_UnchangedCatalogue_KeepsSectionsInstance()
    {
        var vm = new SongsViewModel(new FakeService().Session());
        await vm.AppearCommand.ExecuteAsync(null);
        var shown = vm.Sections;
        var notices = vm.Notices;
        var changes = SectionChanges(vm);
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.Same(shown, vm.Sections);
        Assert.Same(notices, vm.Notices);
        Assert.Empty(changes);
        Assert.Equal(LoadState.Loaded, vm.State);
    }

    [Fact]
    public async Task Reappear_SelectedPlayer_KeepsSectionsInstance()
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var session = service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") });
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.Contains(vm.Sections.SelectMany(s => s.Rows), r => r.Chips.Count > 0 || r.Highlight is not null);
        var shown = vm.Sections;
        var changes = SectionChanges(vm);
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.Same(shown, vm.Sections);
        Assert.Empty(changes);
    }

    [Fact]
    public async Task ChangedInputs_StillReplaceSections()
    {
        var service = new FakeService();
        var session = service.Session();
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        var shown = vm.Sections;
        session.UpdateSettings(s => s with { SongSortAscending = false });
        Assert.NotSame(shown, vm.Sections);
        Assert.Equal(["E", "B", "A"], vm.Sections.Select(s => s.Label));
        shown = vm.Sections;
        vm.SearchText = "zzzz";
        vm.SubmitSearchCommand.Execute(null);
        Assert.NotSame(shown, vm.Sections);
        Assert.True(vm.ShowEmpty);
    }

    [Fact]
    public async Task UnrelatedSetting_KeepsSections_SortChangeReplaces()
    {
        var session = new FakeService().Session();
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        var shown = vm.Sections;
        var changes = SectionChanges(vm);
        session.UpdateSettings(s => s with { ReduceMotion = true });
        Assert.Same(shown, vm.Sections);
        Assert.Empty(changes);
        session.UpdateSettings(s => s with { SongSort = SongSortMode.Duration });
        Assert.Single(changes, c => c == nameof(SongsViewModel.Sections));
    }

    [Fact]
    public void RowSameContent_ComparesEveryShownField()
    {
        SongRowItem Row(ShopHighlight? highlight = ShopHighlight.New, bool inShop = true, Instrument? chart = Instrument.Bass,
            double? raw = 3, string? state = "No score", SongInstrumentStatus chip = SongInstrumentStatus.Scored, string meta = "5") => new(Song)
        {
            Highlight = highlight, InShop = inShop, Chart = chart, ChartRaw = raw, ScoreState = state,
            Chips = [new SongInstrumentBadge(Instrument.Lead, chip)],
            Metadata = [new SongMetadataField(MetadataField.Score, meta, "Score " + meta)],
        };
        var row = Row();
        Assert.True(row.SameContent(row));
        Assert.True(row.SameContent(Row()));
        Assert.False(row.SameContent(Row(highlight: null)));
        Assert.False(row.SameContent(Row(inShop: false)));
        Assert.False(row.SameContent(Row(chart: Instrument.Drums)));
        Assert.False(row.SameContent(Row(raw: 4)));
        Assert.False(row.SameContent(Row(state: null)));
        Assert.False(row.SameContent(Row(chip: SongInstrumentStatus.FullCombo)));
        Assert.False(row.SameContent(Row(meta: "6")));
        var other = JsonSerializer.Deserialize<Song>("""{"songId":"t","title":"T","artist":"A"}""")!;
        Assert.False(row.SameContent(new SongRowItem(other)));
    }

    [Fact]
    public void SectionsSameContent_ComparesLabelsIdsAndRows()
    {
        var a = new SongRowItem(Song);
        IReadOnlyList<SongRowSection> shown = [new("A", [a])];
        Assert.True(SongRowSection.SameContent(shown, shown));
        Assert.True(SongRowSection.SameContent(shown, [new("A", [new SongRowItem(Song)])]));
        Assert.False(SongRowSection.SameContent(shown, [new("B", [a])]));
        Assert.False(SongRowSection.SameContent(shown, [new("A", [a], "fst.shop.section")]));
        Assert.False(SongRowSection.SameContent(shown, [new("A", [a, a])]));
        Assert.False(SongRowSection.SameContent(shown, [new("A", [new SongRowItem(Song) { InShop = true }])]));
        Assert.False(SongRowSection.SameContent(shown, []));
    }
}
