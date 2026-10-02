using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class PlayerStatLinksTests
{
    [Fact]
    public void OverallPreset_ResetsFiltersAndChecksEveryVisibleChart()
    {
        var settings = new AppSettings
        {
            VisibleInstruments = [Instrument.Lead, Instrument.Drums],
            SongFilter = new SongFilter(Instrument.Bass, [2, 5]),
            ShopFilter = new SongShopFilter(available: true, unavailable: false),
            SongSort = SongSortMode.Year,
            SongSortAscending = false,
            PlayerScoreFilter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.MissingFCs, Instrument.Bass, true),
        };
        var applied = new SongsStatPreset(null, SongScoreFilterKind.HasFCs).ApplyTo(settings);
        Assert.Equal(SongFilter.None, applied.SongFilter);
        Assert.False(applied.ShopFilter.IsActive);
        Assert.Equal(SongSortMode.Title, applied.SongSort);
        Assert.True(applied.SongSortAscending);
        Assert.Equal([Instrument.Lead, Instrument.Drums], applied.PlayerScoreFilter.HasFCs);
        Assert.Empty(applied.PlayerScoreFilter.MissingFCs);
    }

    [Fact]
    public void InstrumentPreset_CleansOnlyItsChartAndKeepsShop()
    {
        var settings = new AppSettings
        {
            ShopFilter = new SongShopFilter(available: true, unavailable: false),
            SongFilter = new SongFilter(Instrument.Lead, [3, 4]),
            PlayerScoreFilter = SongPlayerScoreFilter.None
                .With(SongScoreFilterKind.MissingScores, Instrument.Lead, true)
                .With(SongScoreFilterKind.HasFCs, Instrument.Bass, true)
                .WithExcluded(SongBucketKind.Season, [0]),
        };
        var applied = new SongsStatPreset(Instrument.Lead, SongScoreFilterKind.HasScores).ApplyTo(settings);
        Assert.Equal(new SongFilter(Instrument.Lead), applied.SongFilter);
        Assert.True(applied.ShopFilter.Available);
        Assert.False(applied.ShopFilter.Unavailable);
        Assert.Equal([Instrument.Lead], applied.PlayerScoreFilter.HasScores);
        Assert.Empty(applied.PlayerScoreFilter.MissingScores);
        Assert.Equal([Instrument.Bass], applied.PlayerScoreFilter.HasFCs);
        // Web cleanFilters also shows every season/percentile/stars/intensity bucket again.
        Assert.False(applied.PlayerScoreFilter.HasBucketChecks);
    }

    [Fact]
    public void InstrumentPreset_BandAndStarsShowOnlyThatBucket()
    {
        var top = new SongsStatPreset(Instrument.Lead, null, TopPercent: 5).ApplyTo(new AppSettings());
        Assert.Equal(SongBuckets.PercentileKeys.Where(k => k != 5), top.PlayerScoreFilter.ExcludedPercentiles);
        Assert.Empty(top.PlayerScoreFilter.ExcludedStars);
        var gold = new SongsStatPreset(Instrument.Lead, null, Stars: 6).ApplyTo(new AppSettings());
        Assert.Equal([0, 1, 2, 3, 4, 5], gold.PlayerScoreFilter.ExcludedStars);
        Assert.Equal(SongSortMode.Stars, gold.SongSort);
    }

    [Fact]
    public void InstrumentPreset_ReplacesCorruptSavedFilter()
    {
        var corrupt = new SongPlayerScoreFilter { HasScores = [Instrument.Lead, Instrument.Lead] };
        Assert.False(corrupt.IsValid);
        var applied = new SongsStatPreset(Instrument.Bass, SongScoreFilterKind.HasFCs).ApplyTo(new AppSettings { PlayerScoreFilter = corrupt });
        Assert.True(applied.PlayerScoreFilter.IsValid);
        Assert.Empty(applied.PlayerScoreFilter.HasScores);
        Assert.Equal([Instrument.Bass], applied.PlayerScoreFilter.HasFCs);
    }

    [Fact]
    public void Links_RoutesHintsAndSelection()
    {
        var songs = new PlayerStatLink.Songs(new SongsStatPreset(Instrument.Drums, SongScoreFilterKind.HasScores));
        Assert.True(songs.RequiresSelection);
        Assert.Equal("Opens Songs filtered to Drums", songs.Hint);
        Assert.Equal("Opens Songs filtered", new PlayerStatLink.Songs(new SongsStatPreset(null, SongScoreFilterKind.HasScores)).Hint);
        var detail = new PlayerStatLink.SongDetail("s9", Instrument.Bass);
        Assert.False(detail.RequiresSelection);
        Assert.Equal("Opens the song", detail.Hint);
        Assert.Equal(new AppRoute.SongDetail("s9", Instrument.Bass), detail.Route);
        var rankings = new PlayerStatLink.FullRankings(Instrument.Lead);
        Assert.False(rankings.RequiresSelection);
        Assert.Equal(new AppRoute.FullRankings(Instrument.Lead, "totalscore"), rankings.Route);
        // With the player's rank the link opens their page (25 rows per page).
        Assert.Equal(new AppRoute.FullRankings(Instrument.Lead, "totalscore", 5), new PlayerStatLink.FullRankings(Instrument.Lead, 101).Route);
    }

    [Theory]
    [InlineData(true, false, false, true, PlayerLinkStep.Go)]
    [InlineData(false, true, false, true, PlayerLinkStep.SelectThenGo)]
    [InlineData(false, true, true, true, PlayerLinkStep.ConfirmSwitchThenGo)]
    [InlineData(false, false, false, true, PlayerLinkStep.Blocked)]
    [InlineData(false, false, true, false, PlayerLinkStep.Go)]
    public void Policy_SelectFirst(bool selected, bool canSelect, bool other, bool songs, PlayerLinkStep expected)
    {
        PlayerStatLink link = songs
            ? new PlayerStatLink.Songs(new SongsStatPreset(null, SongScoreFilterKind.HasScores))
            : new PlayerStatLink.FullRankings(Instrument.Lead);
        Assert.Equal(expected, PlayerLinkPolicy.Plan(link, selected, canSelect, other));
    }

    [Fact]
    public void StarCounts_GoldFirst()
    {
        var profile = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(PlayerWire.DefaultProfile()),
            PlayerJsonContext.Default.PlayerProfileResponse);
        Assert.Equal([(6, 1), (5, 1), (4, 0), (3, 0), (2, 0), (1, 0)], PlayerStatistics.StarCounts(profile, Instrument.Lead));
    }

    [Fact]
    public void Tiles_ObservableState()
    {
        var tile = new PlayerStatTile("k", "Label", "1", link: new PlayerStatLink.FullRankings(Instrument.Bass));
        Assert.Equal("fst.player.stat.overview.k", tile.AutomationId);
        Assert.True(tile.IsLinked);
        Assert.Equal("Opens Bass rankings", tile.Hint);
        var changes = new List<string?>();
        tile.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        tile.LinkEnabled = false;
        Assert.False(tile.IsLinked);
        Assert.Equal("", tile.Hint);
        tile.Value = "2";
        tile.Tint = PlayerStatTint.Gold;
        Assert.True(tile.Gold);
        Assert.Equal("Label: 2", tile.Announcement);
        Assert.Contains(nameof(PlayerStatTile.IsLinked), changes);
        Assert.Contains(nameof(PlayerStatTile.Announcement), changes);

        var row = new PlayerPercentileRow(new PlayerPercentileBucket(5, 1), Instrument.Lead);
        Assert.True(row.Gold);
        Assert.Equal("Top 5%: 1 song", row.Announcement);
        Assert.Equal("fst.player.percentile.Solo_Guitar.5", row.AutomationId);
        Assert.False(row.IsLinked);
        var linked = new PlayerPercentileRow(new PlayerPercentileBucket(50, 2), Instrument.Lead) { Link = new PlayerStatLink.FullRankings(Instrument.Lead) };
        Assert.True(linked.IsLinked);
        linked.LinkEnabled = false;
        Assert.False(linked.IsLinked);
        Assert.Equal("Top 50%: 2 songs", linked.Announcement);
    }

    [Fact]
    public async Task Viewed_SongsLinkSelectsFirstThenAppliesPreset()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session();
        using var vm = new PlayerProfileViewModel(session, PlayerWire.Id);
        await vm.LoadAsync();
        var played = vm.Overview[0];
        Assert.Equal("songs-played", played.Key);
        Assert.True(played.IsLinked);
        Assert.Equal(PlayerLinkStep.SelectThenGo, vm.PlanLink(played.Link!));
        var (followed, route) = vm.FollowLink(played.Link!);
        Assert.True(followed);
        Assert.Null(route);
        Assert.True(vm.IsSelected);
        Assert.Equal(session.Settings.VisibleInstruments, session.Settings.PlayerScoreFilter.HasScores);

        var best = vm.Overview.Single(t => t.Key == "best-rank");
        Assert.Equal(PlayerLinkStep.Go, vm.PlanLink(best.Link!));
        Assert.Equal((true, (AppRoute?)new AppRoute.SongDetail("s1", Instrument.Lead)), vm.FollowLink(best.Link!));
        Assert.Null(vm.Overview.Single(t => t.Key == "gold-stars").Link);
    }

    [Fact]
    public async Task Viewed_SwitchAndPausedSelection()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session(new SelectedPlayer(PlayerWire.Other, "Two"));
        using var vm = new PlayerProfileViewModel(session, PlayerWire.Id);
        await vm.LoadAsync();
        var link = vm.Instruments[0].Stats[0].Link!;
        Assert.Equal(PlayerLinkStep.ConfirmSwitchThenGo, vm.PlanLink(link));
        Assert.Equal((true, (AppRoute?)null), vm.FollowLink(link));
        Assert.Equal(PlayerWire.Id, session.SelectedPlayer!.AccountId);
        Assert.Equal(new SongFilter(Instrument.Lead), session.Settings.SongFilter);

        fake.Header = false;
        session.DeselectPlayer();
        using var paused = new PlayerProfileViewModel(session, PlayerWire.Other);
        await paused.LoadAsync();
        Assert.Equal(PlayerIdentityAction.Unverified, paused.IdentityAction);
        Assert.False(paused.Overview[0].IsLinked);
        Assert.False(paused.Instruments[0].Stats[0].IsLinked);
        Assert.Equal(PlayerLinkStep.Blocked, paused.PlanLink(paused.Overview[0].Link!));
        Assert.Equal((false, (AppRoute?)null), paused.FollowLink(paused.Overview[0].Link!));
        var rankings = new PlayerStatLink.FullRankings(Instrument.Lead);
        Assert.Equal((true, (AppRoute?)rankings.Route), paused.FollowLink(rankings));
    }
}
