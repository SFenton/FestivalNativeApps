using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Suggestions page model: load states, batching, rivals, filter and session changes.</summary>
public sealed class SuggestionsViewModelTests
{
    private const string Account = "p1";

    #region Fake service
    private static readonly Lazy<string> SongsJson = new(() =>
    {
        var fixture = SuggestionParityTests.LoadFixture();
        var songs = JsonSerializer.Serialize(fixture.Songs, new JsonSerializerOptions(JsonSerializerDefaults.Web) { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull });
        return $$"""{"count":{{fixture.Songs.Count}},"currentSeason":12,"songs":{{songs}}}""";
    });

    private static string ProfileJson(string account = Account, int limit = int.MaxValue)
    {
        var rows = new JsonArray();
        foreach (var row in SuggestionParityTests.LoadFixture().Scores.Take(limit))
        {
            InstrumentInfo.TryParse(row.Instrument, out var instrument);
            var node = new JsonObject
            {
                ["si"] = row.SongId, ["ins"] = PlayerInstrumentCode.Encode(instrument), ["sc"] = row.Score,
                ["acc"] = row.Accuracy / 1000, ["fc"] = row.FullCombo, ["sn"] = row.Season,
            };
            if (row.Stars is { } stars) node["st"] = stars;
            if (row.Rank is { } rank) { node["rk"] = rank; node["te"] = row.TotalEntries; }
            rows.Add(node);
        }
        return new JsonObject { ["accountId"] = account, ["displayName"] = "Player", ["totalScores"] = rows.Count, ["scores"] = rows }.ToJsonString();
    }

    private static string RivalsJson(string account = Account)
    {
        var root = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "suggestions-parity.json")))!;
        var rivals = root["rivalsAll"]!.DeepClone();
        rivals["accountId"] = account;
        return rivals.ToJsonString();
    }

    private sealed class Harness
    {
        public FakeService Service { get; } = new();
        public HttpStatusCode ProfileStatus { get; set; } = HttpStatusCode.OK;
        public string ProfileBody { get; set; } = ProfileJson();
        public HttpStatusCode RivalsStatus { get; set; } = HttpStatusCode.OK;
        public TaskCompletionSource? RivalsGate { get; set; }
        public int ProfileReads { get; private set; }
        public InMemorySuggestionFilterStore Store { get; } = new();
        public FestivalSession Session { get; }

        public Harness(bool selected = true)
        {
            Service.SongsBody = SongsJson.Value;
            Service.Override = request =>
            {
                var path = request.RequestUri!.AbsolutePath;
                var pub = ("X-FST-Publication-Id", Service.PublicationId.ToString(CultureInfo.InvariantCulture));
                if (path.EndsWith("/rivals/all", StringComparison.Ordinal))
                {
                    var id = path.Split('/')[3];
                    return RivalsStatus == HttpStatusCode.OK ? Wire.Ok(RivalsJson(id), pub) : Wire.Response(RivalsStatus);
                }
                if (path.StartsWith("/api/player/", StringComparison.Ordinal))
                {
                    ProfileReads++;
                    var id = path.Split('/')[3];
                    if (ProfileStatus == HttpStatusCode.Accepted)
                        return Wire.Response(HttpStatusCode.Accepted,
                            $$"""{"accountId":"{{id}}","displayName":null,"totalScores":0,"scores":[],"status":"syncing","notYetPublished":true}""", pub);
                    return ProfileStatus == HttpStatusCode.OK ? Wire.Ok(ProfileBody.Replace($"\"{Account}\"", $"\"{id}\""), pub) : Wire.Response(ProfileStatus);
                }
                return null;
            };
            var inner = Service.Handler.Responder;
            Service.Handler.Responder = async (request, token) =>
            {
                if (RivalsGate is { } gate && request.RequestUri!.AbsolutePath.EndsWith("/rivals/all", StringComparison.Ordinal))
                    await gate.Task.WaitAsync(token);
                return await inner(request, token);
            };
            Session = Service.Session(settings: selected ? new AppSettings { SelectedPlayer = new SelectedPlayer(Account, "Player") } : null);
        }

        public SuggestionsViewModel Model(uint seed = 1, int? categoryLimit = null) => new(Session, Store, () => seed, categoryLimit);
    }
    #endregion

    [Fact]
    public async Task NoPlayerShowsChooseProfile()
    {
        var harness = new Harness(selected: false);
        var model = harness.Model();
        Assert.True(model.ShowNoPlayer);
        await model.AppearCommand.ExecuteAsync(null);
        Assert.Equal(SuggestionsPhase.NoPlayer, model.Phase);
        Assert.Empty(model.Cards);
        model.LoadMore();
        Assert.Empty(model.Cards);
    }

    [Fact]
    public async Task LoadsFirstBatchThenMoreOnScroll()
    {
        var harness = new Harness();
        var model = harness.Model();
        Assert.Equal(SuggestionsPhase.Loading, model.Phase);
        await model.AppearCommand.ExecuteAsync(null);
        Assert.True(model.ShowList);
        Assert.Equal(SuggestionsViewModel.InitialBatch, model.Cards.Count);
        Assert.True(model.HasMore);
        Assert.All(model.Cards, c => Assert.StartsWith("fst.suggestions.category.", c.AutomationId, StringComparison.Ordinal));
        Assert.All(model.Cards.SelectMany(c => c.Rows), r => Assert.StartsWith("fst.suggestions.row.", r.AutomationId, StringComparison.Ordinal));
        Assert.True(model.ShouldLoadMore(model.Cards.Count - 1));
        Assert.False(model.ShouldLoadMore(0));
        model.LoadMoreCommand.Execute(null);
        Assert.Equal(SuggestionsViewModel.InitialBatch + SuggestionsViewModel.Batch, model.Cards.Count);
        var card = model.Cards.First(c => c.HasHeaderIcon);
        Assert.EndsWith(".png", card.HeaderIcon, StringComparison.Ordinal);
        Assert.NotEmpty(card.HeaderIconLabel);
        Assert.Equal(card.Category.Title, card.Title);
        Assert.Equal(card.Category.Description, card.Description);
        Assert.Contains(model.Cards, c => !c.HasHeaderIcon && c.HeaderIcon.Length == 0);

        // Appearing again with the same source keeps the mix.
        var keys = model.Cards.Select(c => c.Category.Key).ToList();
        await model.AppearCommand.ExecuteAsync(null);
        Assert.Equal(keys, model.Cards.Select(c => c.Category.Key));
        Assert.Equal(model.Cards.Count, model.Generated.Count);
    }

    [Fact]
    public async Task SameSeedGivesTheSameMixAsTheGenerator()
    {
        var harness = new Harness();
        var model = harness.Model(seed: 42);
        await model.LoadAsync();
        var fixture = SuggestionParityTests.LoadFixture();
        var generator = new SuggestionGenerator(new SuggestionGenerator.Options(42, CurrentSeason: 12));
        generator.SetSource(fixture.Songs.Select(s => s with { }).ToList(), SuggestionParityTests.ScoreIndex(fixture));
        Assert.Equal(generator.GetNext(SuggestionsViewModel.InitialBatch).Select(c => c.Key), model.Cards.Select(c => c.Category.Key));
    }

    [Fact]
    public async Task RivalsSpliceInWhenTheyArrive()
    {
        var harness = new Harness { RivalsGate = new TaskCompletionSource() };
        var model = harness.Model();
        await model.LoadAsync();
        Assert.DoesNotContain(model.Cards, c => c.Category.Type == SuggestionCategoryType.SongRivals);
        harness.RivalsGate.SetResult();
        await Async.Settle();
        for (var i = 0; i < 20 && !model.Cards.Any(c => c.Category.Type == SuggestionCategoryType.SongRivals); i++) model.LoadMore();
        Assert.Contains(model.Cards, c => c.Category.Type == SuggestionCategoryType.SongRivals &&
            c.Rows.Any(r => r.Presentation.Layout == SuggestionRowLayout.Rival));
    }

    [Fact]
    public async Task RivalFailureIsIgnored()
    {
        var harness = new Harness { RivalsStatus = HttpStatusCode.InternalServerError };
        var model = harness.Model();
        await model.LoadAsync();
        await Async.Settle();
        for (var i = 0; i < 30; i++) model.LoadMore();
        Assert.True(model.ShowList);
        Assert.DoesNotContain(model.Cards, c => c.Category.Type == SuggestionCategoryType.SongRivals);
    }

    [Fact]
    public async Task SyncingProfileShowsSyncing()
    {
        var harness = new Harness { ProfileStatus = HttpStatusCode.Accepted };
        var model = harness.Model();
        await model.LoadAsync();
        Assert.True(model.ShowSyncing);
        Assert.Empty(model.Cards);
    }

    [Fact]
    public async Task ProfileFailureShowsStatusAndRetryRecovers()
    {
        var harness = new Harness { ProfileStatus = HttpStatusCode.InternalServerError };
        var model = harness.Model();
        await model.LoadAsync();
        Assert.True(model.ShowError);
        Assert.NotNull(model.Status.Issue);
        harness.ProfileStatus = HttpStatusCode.OK;
        await model.Status.RetryCommand.ExecuteAsync(null);
        Assert.True(model.ShowList);
        Assert.Null(model.Status.Issue);
    }

    [Fact]
    public async Task CatalogueFailureShowsStatus()
    {
        var harness = new Harness();
        harness.Service.SongsBody = "{";
        var model = harness.Model();
        await model.LoadAsync();
        Assert.Equal(SuggestionsPhase.Failed, model.Phase);
        Assert.NotNull(model.Status.Issue);
    }

    [Fact]
    public async Task EmptyScoresStillSuggestUnplayedSongs()
    {
        var harness = new Harness { ProfileBody = ProfileJson(limit: 0) };
        var model = harness.Model();
        await model.LoadAsync();
        Assert.True(model.ShowList);
        Assert.Contains(model.Cards, c => c.Category.Type == SuggestionCategoryType.Unplayed);
        Assert.DoesNotContain(model.Cards, c => c.Category.Type == SuggestionCategoryType.NearFC);
    }

    [Fact]
    public async Task FilterHidesCardsPersistsAndResets()
    {
        var harness = new Harness();
        var model = harness.Model();
        await model.LoadAsync();
        var draft = model.FilterDraft;
        draft.Begin();
        Assert.Equal(InstrumentInfo.All.Count, draft.InstrumentToggles.Count);
        Assert.Equal(SuggestionCategoryTypeInfo.All.Count, draft.TypeToggles.Count);
        Assert.Empty(draft.InstrumentTypeToggles); // nothing selected on opening (web deferSelection)
        Assert.Null(draft.SelectedInstrument);
        Assert.True(draft.HasInstruments);
        Assert.Equal(Instrument.Lead, draft.Instruments[0]);
        Assert.False(draft.CanApply);
        Assert.False(draft.ResetCommand.CanExecute(null));

        // Turn every type off except Unplayed: each switch applies (and persists) at once.
        foreach (var toggle in draft.TypeToggles.Where(t => t.Label != "Unplayed")) toggle.IsOn = false;
        Assert.False(draft.CanApply);
        draft.SelectedInstrument = Instrument.Lead;
        Assert.Equal(SuggestionCategoryTypeInfo.All.Count, draft.InstrumentTypeToggles.Count);
        Assert.All(draft.InstrumentTypeToggles.Where(t => t.Label != "Unplayed"), t => Assert.False(t.IsOn));
        Assert.True(model.IsFilterActive);
        Assert.Equal(SuggestionCategoryTypeInfo.All.Count - 1, harness.Store.SaveCount);
        Assert.All(model.Cards, c => Assert.Equal(SuggestionCategoryType.Unplayed, c.Category.Type));
        Assert.True(model.Cards.Count >= SuggestionsViewModel.InitialBatch || !model.HasMore);

        // Hide every instrument: mixed categories without charts may remain; single-instrument ones vanish.
        draft.Begin();
        foreach (var toggle in draft.InstrumentToggles) toggle.IsOn = false;
        Assert.All(model.Cards, c => Assert.Null(c.Category.Instrument));

        // Per-instrument toggle re-enables the global switch.
        draft.Begin();
        draft.SelectedInstrument = Instrument.Bass;
        var nearFc = draft.InstrumentTypeToggles.First(t => t.Label == "Near FC");
        nearFc.IsOn = true;
        Assert.True(draft.TypeToggles.First(t => t.Label == "Near FC").IsOn);
        nearFc.IsOn = false;
        Assert.False(draft.TypeToggles.First(t => t.Label == "Near FC").IsOn);
        Assert.True(draft.ResetCommand.CanExecute(null));
        draft.ResetCommand.Execute(null);
        Assert.All(draft.TypeToggles, t => Assert.True(t.IsOn));
        Assert.All(draft.InstrumentToggles, t => Assert.True(t.IsOn));
        Assert.False(model.IsFilterActive);
        var saves = harness.Store.SaveCount;
        model.ApplyFilter(SuggestionFilterSettings.Default);
        Assert.Equal(saves, harness.Store.SaveCount);
    }

    [Fact]
    public async Task FilterFollowsSettingsVisibleInstruments()
    {
        var harness = new Harness();
        var model = harness.Model();
        await model.LoadAsync();
        var draft = model.FilterDraft;
        draft.Begin();
        draft.SelectedInstrument = Instrument.Karaoke;
        Assert.NotEmpty(draft.InstrumentTypeToggles);
        draft.InstrumentToggles.First(t => t.Label == "Karaoke").IsOn = false;
        Assert.True(model.IsFilterActive);
        Assert.True(draft.ResetCommand.CanExecute(null));

        // Hiding Karaoke in Settings removes it from the open filter at once and clears the accent it caused.
        var changes = new List<string?>();
        model.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        harness.Session.UpdateSettings(s => s.WithInstrumentVisible(Instrument.Karaoke, false));
        Assert.DoesNotContain(Instrument.Karaoke, draft.Instruments);
        Assert.DoesNotContain(draft.InstrumentToggles, t => t.Label == "Karaoke");
        Assert.Null(draft.SelectedInstrument);
        Assert.Empty(draft.InstrumentTypeToggles);
        Assert.False(model.IsFilterActive);
        Assert.Contains(nameof(SuggestionsViewModel.IsFilterActive), changes);
        Assert.False(draft.ResetCommand.CanExecute(null));
        Assert.Equal("Play a few songs and suggestions will appear here.", model.EmptyMessage);

        // A selection that is no longer visible shows no switches.
        draft.SelectedInstrument = Instrument.Karaoke;
        Assert.Empty(draft.InstrumentTypeToggles);

        // Showing it again restores the saved toggle and the accent.
        harness.Session.UpdateSettings(s => s.WithInstrumentVisible(Instrument.Karaoke, true));
        Assert.False(draft.InstrumentToggles.First(t => t.Label == "Karaoke").IsOn);
        Assert.True(model.IsFilterActive);
    }

    [Fact]
    public async Task HeaderHidesWhileLoading()
    {
        var harness = new Harness();
        var model = harness.Model();
        Assert.Equal(SuggestionsPhase.Loading, model.Phase);
        Assert.False(model.ShowHeader);
        await model.LoadAsync();
        Assert.True(model.ShowList);
        Assert.True(model.ShowHeader);
    }

    [Fact]
    public async Task CardsAddedReportsWhereEachNewBatchStarts()
    {
        var harness = new Harness { RivalsStatus = HttpStatusCode.NotFound };
        var model = harness.Model();
        var starts = new List<int>();
        model.CardsAdded += (_, start) => starts.Add(start);

        await model.LoadAsync();
        Assert.Equal([0], starts);

        // A scroll-triggered batch starts after the cards already shown.
        model.LoadMore();
        Assert.Equal([0, SuggestionsViewModel.InitialBatch], starts);

        // A filter change rebuilds every card (and may generate more): one announcement from 0.
        starts.Clear();
        var unplayed = SuggestionCategoryTypeInfo.All.Where(t => t != SuggestionCategoryType.Unplayed)
            .Aggregate(SuggestionFilterSettings.Default, (f, t) => f.WithGlobalType(t, false));
        model.ApplyFilter(unplayed);
        Assert.Equal([0], starts);

        // Nothing visible: no announcement.
        starts.Clear();
        var none = SuggestionCategoryTypeInfo.All.Aggregate(SuggestionFilterSettings.Default, (f, t) => f.WithGlobalType(t, false));
        model.ApplyFilter(none);
        model.LoadMore();
        Assert.Empty(starts);

        // A new mix is all new cards.
        model.ApplyFilter(SuggestionFilterSettings.Default);
        starts.Clear();
        model.StartNewMixCommand.Execute(null);
        Assert.Equal([0], starts);
    }

    [Fact]
    public async Task FilteringEverythingShowsFilteredEmptyState()
    {
        var harness = new Harness();
        var model = harness.Model();
        await model.LoadAsync();
        var none = SuggestionCategoryTypeInfo.All.Aggregate(SuggestionFilterSettings.Default, (f, t) => f.WithGlobalType(t, false));
        model.ApplyFilter(none);
        Assert.True(model.ShowEmpty);
        Assert.Equal("No suggestions match your filters.", model.EmptyMessage);
        var generated = model.Generated.Count;
        model.LoadMore();
        Assert.Equal(generated, model.Generated.Count);
    }

    [Fact]
    public async Task SavedFilterIsLoadedOnStart()
    {
        var harness = new Harness();
        harness.Store.Save(SuggestionFilterSettings.Default.WithGlobalType(SuggestionCategoryType.Unplayed, false));
        var model = harness.Model();
        Assert.True(model.IsFilterActive);
        await model.LoadAsync();
        Assert.DoesNotContain(model.Cards, c => c.Category.Type == SuggestionCategoryType.Unplayed);
    }

    [Fact]
    public async Task SmallCatalogueRemixesUntilTheCap()
    {
        var harness = new Harness { ProfileBody = ProfileJson(limit: 0) };
        var fixture = SuggestionParityTests.LoadFixture();
        var songs = JsonSerializer.Serialize(fixture.Songs.Take(6), new JsonSerializerOptions(JsonSerializerDefaults.Web) { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull });
        harness.Service.SongsBody = $$"""{"count":6,"currentSeason":12,"songs":{{songs}}}""";
        harness.RivalsStatus = HttpStatusCode.NotFound;
        var model = harness.Model();
        await model.LoadAsync();
        await Async.Settle();
        for (var i = 0; i < 400 && model.HasMore; i++) model.LoadMore();
        Assert.True(model.ReachedLimit);
        Assert.False(model.HasMore);
        Assert.Equal(SuggestionsViewModel.CategoryLimit, model.Generated.Count);
        Assert.Contains(model.Cards, c => c.AutomationId.EndsWith(".1", StringComparison.Ordinal));
        model.StartNewMixCommand.Execute(null);
        Assert.False(model.ReachedLimit);
        Assert.Equal(SuggestionsViewModel.InitialBatch, model.Cards.Count);
    }

    [Theory]
    [InlineData(12, 12)]
    [InlineData(0, SuggestionsViewModel.CategoryLimit)]
    [InlineData(-3, SuggestionsViewModel.CategoryLimit)]
    [InlineData(5_000, SuggestionsViewModel.CategoryLimit)]
    public async Task CategoryLimitOverrideOnlyLowersTheCap(int requested, int expected)
    {
        var harness = new Harness { ProfileBody = ProfileJson(limit: 0) };
        var fixture = SuggestionParityTests.LoadFixture();
        var songs = JsonSerializer.Serialize(fixture.Songs.Take(6), new JsonSerializerOptions(JsonSerializerDefaults.Web) { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull });
        harness.Service.SongsBody = $$"""{"count":6,"currentSeason":12,"songs":{{songs}}}""";
        harness.RivalsStatus = HttpStatusCode.NotFound;
        var model = harness.Model(categoryLimit: requested);
        await model.LoadAsync();
        await Async.Settle();
        for (var i = 0; i < 400 && model.HasMore; i++) model.LoadMore();
        Assert.True(model.ReachedLimit);
        Assert.Equal(expected, model.Generated.Count);
        model.StartNewMixCommand.Execute(null);
        Assert.False(model.ReachedLimit);
        Assert.Equal(Math.Min(expected, SuggestionsViewModel.InitialBatch), model.Cards.Count);
    }

    [Fact]
    public async Task DeselectSwitchAndVisibilityChanges()
    {
        var harness = new Harness();
        var model = harness.Model();
        await model.LoadAsync();
        Assert.True(model.ShowList);

        harness.Session.UpdateSettings(s => s.WithInstrumentVisible(Instrument.Lead, false));
        Assert.DoesNotContain(Instrument.Lead, model.VisibleInstruments);
        Assert.All(model.Cards, c => Assert.NotEqual(Instrument.Lead, c.Category.Instrument));

        harness.Session.UpdateSettings(s => s with { SelectedPlayer = new SelectedPlayer("p2", "Two") });
        await Async.Until(() => model.ShowList);
        Assert.True(harness.ProfileReads >= 2);

        harness.Session.DeselectPlayer();
        Assert.True(model.ShowNoPlayer);
        Assert.Empty(model.Cards);
        Assert.Equal("Play a few songs and suggestions will appear here.", model.EmptyMessage);
    }

    [Fact]
    public async Task ProfileLoadedElsewhereStartsTheMix()
    {
        var harness = new Harness();
        var model = harness.Model();
        await harness.Session.LoadSelectedProfileAsync();
        await Async.Until(() => model.ShowList);
        Assert.NotEmpty(model.Cards);
    }
}
