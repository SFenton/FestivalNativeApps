using System.Globalization;

namespace Festival.Core.Domain;

#region Generator
/// <summary>
/// Produces score-driven Suggestions categories from the catalogue and the selected player's score
/// index. A line-for-line port of the Apple <c>SuggestionGenerator</c> (itself a port of the web
/// <c>packages/core/src/suggestions/suggestionGenerator.ts</c>): same Mulberry32 seed, pipeline list
/// order, shuffles, emit-probability/skip-streak table, new-first selection and decade re-titling, so
/// a fixed seed and source yield the same categories as iOS. Band pipelines are not included.
/// Not thread-safe; use from one thread.
/// </summary>
public sealed class SuggestionGenerator
{
    #region Options and candidates
    /// <summary>Tuning knobs (web <c>SuggestionGeneratorOptions</c>).</summary>
    /// <param name="Seed">PRNG seed.</param>
    /// <param name="DisableSkipping">Skip the emit-probability roll (tests).</param>
    /// <param name="FixedDisplayCount">Force every category to this many songs instead of 2–5.</param>
    /// <param name="CurrentSeason">Current season; stale categories are disabled at 0.</param>
    public sealed record Options(uint Seed = 1, bool DisableSkipping = false, int? FixedDisplayCount = null, int CurrentSeason = 0);

    /// <summary>One (song, chart) pairing considered before final selection.</summary>
    private readonly record struct Candidate(Song Song, SuggestionScore? Score, Instrument? Instrument);

    /// <summary>One exclusive CHOpt gap tier.</summary>
    private readonly record struct NearMaxTier(int MinGap, int MaxGap, string Label, string Title, string Description);

    private static readonly int[] PercentileThresholds = [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100];
    private static readonly int[] PercentileBuckets = [2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50];
    private static readonly (int Min, double Prob)[] EmitTable =
        [(80, 1.0), (50, 0.98), (35, 0.95), (25, 0.9), (18, 0.85), (12, 0.75), (8, 0.62), (5, 0.5), (0, 0.38)];
    private static readonly NearMaxTier[] NearMaxTiers =
    [
        new(0, 5_000, "5k", "Almost Perfect (Within 5k)", "Scores within 5,000 of the theoretical max. You're almost there!"),
        new(5_000, 10_000, "10k", "Close to Max (Within 10k)", "Scores within 10,000 of the theoretical max. A great run could close the gap."),
        new(10_000, 15_000, "15k", "Approaching Max (Within 15k)", "Scores within 15,000 of the theoretical max. Keep pushing!"),
    ];
    private static readonly IReadOnlyDictionary<Instrument, SuggestionScore> NoScores = new Dictionary<Instrument, SuggestionScore>();
    #endregion

    #region State
    private readonly ISuggestionRng rng;
    private readonly bool disableSkipping;
    private readonly int? fixedDisplayCount;
    private readonly int currentSeason;

    private IReadOnlyList<Song> songs = [];
    private Dictionary<string, Song> songsById = new(StringComparer.Ordinal);
    private IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>> scoresIndex =
        new Dictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>>();
    private RivalDataIndex? rivalData;

    private readonly HashSet<string> emitted = new(StringComparer.Ordinal);
    private List<Func<List<SuggestionCategory>>> pipelines = [];
    private bool initialized;

    private readonly HashSet<string> sessionShownSongs = new(StringComparer.Ordinal);
    private readonly List<string> recentSongIds = [];
    private readonly List<string> recentArtists = [];
    private readonly Dictionary<string, HashSet<string>> categorySongHistory = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> categorySkipStreak = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Instrument> firstPlaysMixedLastInstrument = new(StringComparer.Ordinal);
    #endregion

    /// <summary>Creates a generator seeded from <paramref name="options"/>; call <see cref="SetSource"/> first.</summary>
    /// <param name="options">Tuning knobs; defaults match normal app behavior.</param>
    public SuggestionGenerator(Options? options = null) : this(null, options) { }

    /// <summary>Creates a generator with an injected random source (tests).</summary>
    /// <param name="rng">Random source, or <see langword="null"/> for the seeded default.</param>
    /// <param name="options">Tuning knobs.</param>
    public SuggestionGenerator(ISuggestionRng? rng, Options? options = null)
    {
        options ??= new Options();
        this.rng = rng ?? new SeededSuggestionRng(options.Seed);
        disableSkipping = options.DisableSkipping;
        fixedDisplayCount = options.FixedDisplayCount;
        currentSeason = options.CurrentSeason;
    }

    #region Public API
    /// <summary>Supplies the catalogue and the selected player's score index.</summary>
    /// <param name="songs">Validated catalogue rows.</param>
    /// <param name="scoresIndex">songId → chart → score.</param>
    public void SetSource(IReadOnlyList<Song> songs, IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>> scoresIndex)
    {
        this.songs = songs;
        this.scoresIndex = scoresIndex;
        songsById = new Dictionary<string, Song>(StringComparer.Ordinal);
        foreach (var song in songs) songsById.TryAdd(song.SongId, song);
    }

    /// <summary>
    /// Injects rival data for the <c>song_rival_*</c> pipelines. Before the first <see cref="GetNext"/> they join
    /// the startup shuffle; afterwards they are shuffled alone and spliced at the front of the remaining queue.
    /// </summary>
    /// <param name="data">Index, or <see langword="null"/> to disable rival pipelines.</param>
    public void SetRivalData(RivalDataIndex? data)
    {
        rivalData = data;
        if (data is null || !initialized) return;
        var additions = RivalPipelines(data);
        ShuffleInPlace(additions);
        additions.AddRange(pipelines);
        pipelines = additions;
    }

    /// <summary>Produces up to <paramref name="count"/> more categories, continuing the current mix.</summary>
    /// <param name="count">Page size.</param>
    /// <returns>New categories; empty once every pipeline is exhausted.</returns>
    public IReadOnlyList<SuggestionCategory> GetNext(int count)
    {
        EnsurePipelines();
        var produced = new List<SuggestionCategory>();
        var safety = 0;
        while (produced.Count < count && pipelines.Count > 0 && safety < 500)
        {
            safety++;
            var pipe = pipelines[0];
            pipelines.RemoveAt(0);
            foreach (var category in pipe())
            {
                if (category.Songs.Count == 0 || !emitted.Add(category.Key)) continue;
                produced.Add(category);
                if (produced.Count >= count) break;
            }
        }
        return produced;
    }

    /// <summary>Whether more pipelines remain in the current mix.</summary>
    public bool HasPendingPipelines => !initialized || pipelines.Count > 0;

    /// <summary>Starts a fresh mix: clears emitted categories and shown songs but keeps the source (web "Start New Mix").</summary>
    public void ResetForEndless()
    {
        initialized = false;
        pipelines = [];
        emitted.Clear();
        sessionShownSongs.Clear();
        EnsurePipelines();
    }
    #endregion

    #region Pipeline construction
    private void EnsurePipelines()
    {
        if (initialized) return;
        initialized = true;
        var list = new List<Func<List<SuggestionCategory>>>
        {
            FcTheseNext, FcTheseNextDecade, NearFcRelaxed, NearFcRelaxedDecade, AlmostSixStars, AlmostSixStarsDecade,
            StarGains, StarGainsDecade, FirstPlaysMixed, FirstPlaysMixedDecade, UnplayedAll, UnplayedAllDecade,
            VarietyPack, ArtistSamplerRotating, GetMoreStars, GetMoreStarsDecade, AlmostElite, AlmostEliteDecade,
            PercentilePush, PercentilePushDecade, ArtistFocusUnplayed, SameNameSets, SameNameNearFc, SamePercentileBucket,
        };
        foreach (var instrument in InstrumentInfo.All)
        {
            list.Add(() => UnFcInstrument(instrument));
            list.Add(() => UnFcInstrumentDecade(instrument));
            list.Add(() => UnplayedInstrument(instrument));
            list.Add(() => UnplayedInstrumentDecade(instrument));
            list.Add(() => AlmostEliteInstrument(instrument));
            list.Add(() => AlmostEliteInstrumentDecade(instrument));
            list.Add(() => PercentilePushInstrument(instrument));
            list.Add(() => PercentilePushInstrumentDecade(instrument));
            list.Add(() => ImproveInstrumentRankings(instrument));
            for (var seasons = 1; seasons <= 5; seasons++)
            {
                var s = seasons;
                list.Add(() => StaleInstrument(instrument, s));
            }
            foreach (var bucket in PercentileBuckets) list.Add(() => PercentileImproveInstrument(instrument, bucket));
        }
        for (var seasons = 1; seasons <= 5; seasons++)
        {
            var s = seasons;
            list.Add(() => StaleGlobal(s));
        }
        foreach (var bucket in PercentileBuckets)
        {
            list.Add(() => SamePercentileBucketSpecific(bucket));
            list.Add(() => PercentileImproveBucket(bucket));
        }
        foreach (var tier in NearMaxTiers)
        {
            list.Add(() => NearMaxScore(tier));
            list.Add(() => NearMaxScoreDecade(tier));
        }
        if (rivalData is { } data) list.AddRange(RivalPipelines(data));
        ShuffleInPlace(list);
        pipelines = list;
    }

    /// <summary>Rival pipelines in web order: five generic families, then five per kept rival.</summary>
    /// <param name="data">Rival index.</param>
    /// <returns>Unshuffled closures.</returns>
    private List<Func<List<SuggestionCategory>>> RivalPipelines(RivalDataIndex data)
    {
        var list = new List<Func<List<SuggestionCategory>>>
        {
            SongRivalBattleground, SongRivalNearFc, SongRivalStale, SongRivalStarGains, SongRivalPctPush,
        };
        foreach (var rival in data.SongRivals)
        {
            var id = rival.AccountId;
            list.Add(() => SongRivalGap(id));
            list.Add(() => SongRivalProtect(id));
            list.Add(() => SongRivalSpotlight(id));
            list.Add(() => SongRivalSlipping(id));
            list.Add(() => SongRivalDominate(id));
        }
        return list;
    }
    #endregion

    #region Shared helpers
    private void ShuffleInPlace<T>(List<T> array)
    {
        for (var i = array.Count - 1; i > 0; i--)
        {
            var j = rng.NextInt(i + 1);
            (array[i], array[j]) = (array[j], array[i]);
        }
    }

    private int DisplayCount() => fixedDisplayCount is { } fixedCount ? Math.Max(1, fixedCount) : 2 + rng.NextInt(4);

    private static string Canon(string? value) => (value ?? "").Trim().ToLowerInvariant();

    private IReadOnlyDictionary<Instrument, SuggestionScore>? ScoresFor(string songId) =>
        scoresIndex.TryGetValue(songId, out var scores) ? scores : null;

    private SuggestionScore? ScoreFor(string songId, Instrument instrument) =>
        ScoresFor(songId) is { } scores && scores.TryGetValue(instrument, out var score) ? score : null;

    private static double? RawPercentile(SuggestionScore score) =>
        score is { Rank: { } rank and > 0, TotalEntries: { } total and > 0 } ? (double)rank / total : null;

    private static int? PercentileBucket(double rawPct)
    {
        if (!(rawPct > 0)) return null;
        var topPct = Math.Min(Math.Max(rawPct * 100, 1), 100);
        foreach (var threshold in PercentileThresholds)
            if (topPct <= threshold) return threshold;
        return 100;
    }

    private static int? PercentileBucket(SuggestionScore score) => RawPercentile(score) is { } raw ? PercentileBucket(raw) : null;

    private static int? NextLowerThreshold(int bucket)
    {
        var index = Array.IndexOf(PercentileThresholds, bucket);
        return index > 0 ? PercentileThresholds[index - 1] : null;
    }

    private static bool IsNearNextBracket(double rawPct)
    {
        if (PercentileBucket(rawPct) is not { } bucket || bucket <= 1) return false;
        if (NextLowerThreshold(bucket) is not { } next) return false;
        var midpoint = next + (bucket - next) / 2.0;
        return rawPct * 100 <= midpoint;
    }

    private static bool IsAlmostElite(SuggestionScore score) => PercentileBucket(score) is >= 2 and <= 5;

    private static bool IsNearNextBracket(SuggestionScore score) => RawPercentile(score) is { } raw && IsNearNextBracket(raw);

    private static int? DecadeStart(int? year) => year is >= 1970 and <= 2099 ? year.Value / 10 * 10 : null;

    private static string TwoDigits(int value) => value.ToString("00", CultureInfo.InvariantCulture);

    private static string DecadeLabel(int start) => start % 100 == 0 ? "00's" : TwoDigits(start % 100) + "'s";

    private int LatestSeason(string songId)
    {
        if (ScoresFor(songId) is not { } scores) return 0;
        var max = 0;
        var any = false;
        foreach (var instrument in InstrumentInfo.All)
        {
            if (!scores.TryGetValue(instrument, out var score) || score.Season is not { } season) continue;
            max = any ? Math.Max(max, season) : season;
            any = true;
        }
        return max;
    }

    private int InstrumentSeason(string songId, Instrument instrument) => ScoreFor(songId, instrument)?.Season ?? 0;

    /// <summary>Fresh-candidate count feeding the emit table; keyed on plain song ID like the web.</summary>
    private int FreshCount(List<Candidate> pool) => pool.Count(c => !sessionShownSongs.Contains(c.Song.SongId));

    private bool ShouldEmit(string key, int candidateCount)
    {
        if (disableSkipping) return candidateCount > 0;
        var prob = 0.38;
        foreach (var row in EmitTable)
        {
            if (candidateCount < row.Min) continue;
            prob = row.Prob;
            break;
        }
        var skipped = categorySkipStreak.GetValueOrDefault(key);
        if (skipped >= 2)
        {
            categorySkipStreak[key] = 0;
            return true;
        }
        var emit = rng.NextDouble() < prob;
        categorySkipStreak[key] = emit ? 0 : skipped + 1;
        return emit;
    }

    /// <summary>History identity: song+instrument for the mixed first-plays family, song ID otherwise.</summary>
    private static string HistoryId(Candidate candidate, string categoryKey) =>
        categoryKey == "first_plays_mixed" || categoryKey.StartsWith("first_plays_mixed_", StringComparison.Ordinal)
            ? $"{candidate.Song.SongId}:{candidate.Instrument?.ServiceId() ?? "any"}"
            : candidate.Song.SongId;

    /// <summary>New-first selection with fallback to category- and session-repeated songs (web <c>selectNewFirst</c>).</summary>
    private List<Candidate> SelectNewFirst(string categoryKey, List<Candidate> pool, int take)
    {
        if (pool.Count == 0 || take <= 0) return [];
        var used = categorySongHistory.TryGetValue(categoryKey, out var history)
            ? new HashSet<string>(history, StringComparer.Ordinal)
            : new HashSet<string>(StringComparer.Ordinal);
        if (pool.All(c => used.Contains(HistoryId(c, categoryKey)))) used.Clear();

        var freshNew = pool.Where(c => !sessionShownSongs.Contains(HistoryId(c, categoryKey)) && !used.Contains(HistoryId(c, categoryKey))).ToList();
        ShuffleInPlace(freshNew);
        var freshNewIds = freshNew.Select(c => c.Song.SongId).ToHashSet(StringComparer.Ordinal);
        var categoryNew = pool.Where(c => !used.Contains(HistoryId(c, categoryKey)) && !freshNewIds.Contains(c.Song.SongId)).ToList();
        ShuffleInPlace(categoryNew);
        var oldOnes = pool.Where(c => used.Contains(HistoryId(c, categoryKey))).ToList();
        ShuffleInPlace(oldOnes);

        var result = new List<Candidate>();
        var chosen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var tier in (List<Candidate>[])[freshNew, categoryNew, oldOnes])
        {
            foreach (var candidate in tier)
            {
                if (!chosen.Add(candidate.Song.SongId)) continue;
                result.Add(candidate);
                if (result.Count == take) break;
            }
            if (result.Count == take) break;
        }
        foreach (var picked in result)
        {
            var id = HistoryId(picked, categoryKey);
            used.Add(id);
            sessionShownSongs.Add(id);
        }
        categorySongHistory[categoryKey] = used;
        return result;
    }

    private static SuggestionSongItem MapItem(Candidate candidate, bool includeInstrument)
    {
        var score = candidate.Score;
        string? percentile = null;
        if (score is { Rank: { } rank and > 0, TotalEntries: { } total and > 0 })
            percentile = $"Top {PercentileBucket((double)rank / total)}%";
        return new SuggestionSongItem
        {
            Song = candidate.Song,
            Instrument = includeInstrument ? candidate.Instrument : null,
            Stars = score?.Stars,
            Percent = score?.Accuracy / 10_000,
            FullCombo = score?.IsFullCombo,
            PercentileDisplay = percentile,
        };
    }

    private void PushRecentArtist(string artist)
    {
        recentArtists.Add(artist);
        while (recentArtists.Count > 12) recentArtists.RemoveAt(0);
    }

    private void RecordRecent(Song song)
    {
        recentSongIds.Add(song.SongId);
        while (recentSongIds.Count > 40) recentSongIds.RemoveAt(0);
        var artist = Canon(song.Artist);
        if (artist.Length > 0) PushRecentArtist(artist);
    }

    private SuggestionSongItem FinalizeOne(Candidate candidate, bool includeInstrument)
    {
        RecordRecent(candidate.Song);
        return MapItem(candidate, includeInstrument);
    }

    private List<SuggestionSongItem> Finalize(List<Candidate> candidates, bool includeInstrument) =>
        candidates.Select(c => FinalizeOne(c, includeInstrument)).ToList();

    private List<Candidate> CandidatesForSong(Song song, Func<SuggestionScore, bool> predicate)
    {
        var output = new List<Candidate>();
        if (ScoresFor(song.SongId) is not { } scores) return output;
        foreach (var instrument in InstrumentInfo.All)
            if (scores.TryGetValue(instrument, out var score) && predicate(score))
                output.Add(new Candidate(song, score, instrument));
        return output;
    }

    private List<Candidate> Candidates(Func<SuggestionScore, bool> predicate) =>
        songs.SelectMany(s => CandidatesForSong(s, predicate)).ToList();

    private List<Candidate> Candidates(Instrument instrument, Func<SuggestionScore, bool> predicate)
    {
        var output = new List<Candidate>();
        foreach (var song in songs)
            if (ScoreFor(song.SongId, instrument) is { } score && predicate(score))
                output.Add(new Candidate(song, score, instrument));
        return output;
    }

    private static List<SuggestionCategory> One(string key, string title, string description, SuggestionCategoryType type,
        Instrument? instrument, IReadOnlyList<SuggestionSongItem> items) =>
        [new SuggestionCategory(key, title, description, type, instrument, items)];

    /// <summary>Shared shuffle → probability → select → map pipeline for a plain category.</summary>
    private List<SuggestionCategory> Emit(string key, string title, string description, SuggestionCategoryType type,
        Instrument? instrument, List<Candidate> pool, bool includeInstrumentInItems)
    {
        var shuffled = new List<Candidate>(pool);
        ShuffleInPlace(shuffled);
        if (!ShouldEmit(key, FreshCount(shuffled))) return [];
        var selected = SelectNewFirst(key, shuffled, DisplayCount());
        return selected.Count == 0 ? [] : One(key, title, description, type, instrument, Finalize(selected, includeInstrumentInItems));
    }

    /// <summary>Decade gate + <see cref="BuildDecadeVariant"/>, the shape every <c>*Decade</c> pipeline shares.</summary>
    private List<SuggestionCategory> EmitDecade(string baseKey, string baseTitle, string baseDescription,
        SuggestionCategoryType type, Instrument? instrument, bool includeInstrumentInItems, List<Candidate> pool) =>
        ShouldEmit($"{baseKey}_decade_wrap", FreshCount(pool))
            ? BuildDecadeVariant(baseKey, baseTitle, baseDescription, type, instrument, includeInstrumentInItems, pool)
            : [];

    /// <summary>Picks one decade with 2+ eligible songs and re-titles the category for it.</summary>
    private List<SuggestionCategory> BuildDecadeVariant(string baseKey, string baseTitle, string baseDescription,
        SuggestionCategoryType type, Instrument? instrument, bool includeInstrumentInItems, List<Candidate> pool)
    {
        var valid = pool.Where(c => (c.Song.Year ?? 0) > 0).ToList();
        if (valid.Count < 2) return [];
        var byDecade = new Dictionary<int, List<Candidate>>();
        foreach (var candidate in valid)
        {
            if (DecadeStart(candidate.Song.Year) is not { } start) continue;
            if (!byDecade.TryGetValue(start, out var group)) byDecade[start] = group = [];
            group.Add(candidate);
        }
        var groups = byDecade.Where(p => p.Value.Count >= 2).OrderBy(p => p.Key).ToList();
        if (groups.Count == 0) return [];
        ShuffleInPlace(groups);
        var (decade, chosen) = (groups[0].Key, groups[0].Value);
        var label = DecadeLabel(decade);
        var variantKey = $"{baseKey}_decade_{TwoDigits(decade % 100)}";
        var selection = SelectNewFirst(variantKey, chosen, DisplayCount());
        if (selection.Count < 2) return [];

        if (baseKey == "first_plays_mixed")
            foreach (var candidate in selection)
                if (candidate.Instrument is { } i) firstPlaysMixedLastInstrument[candidate.Song.SongId] = i;

        var name = instrument?.Label() ?? "";
        var title = $"{baseTitle} ({label})";
        var description = $"{baseDescription} Limited to {label} songs.";
        if (baseKey is "more_stars" or "almost_six_star") title = $"Push {label} to Gold";
        else if (baseKey.StartsWith("unfc_", StringComparison.Ordinal)) title = $"Close {name} FCs ({label})";
        else if (baseKey == "unplayed_any") title = $"First Plays ({label})";
        else if (baseKey.StartsWith("unplayed_", StringComparison.Ordinal)) title = $"First {name} Plays ({label})";
        else if (baseKey == "first_plays_mixed") title = $"First Plays (Mixed {label})";
        else if (baseKey == "near_fc_relaxed") title = $"Close to FC (92%+) - {label}";
        else if (baseKey == "near_fc_any") title = $"FC These Next! ({label})";
        else if (baseKey == "star_gains") title = $"Easy Star Gains ({label})";
        else if (baseKey == "almost_elite")
        {
            title = $"Almost Elite ({label})";
            description = $"You're in the top 5% on these {label} songs — one good run could crack the top 1%.";
        }
        else if (baseKey.StartsWith("almost_elite_", StringComparison.Ordinal))
        {
            title = $"Almost Elite on {name} ({label})";
            description = $"Your {name} scores on these {label} songs are in the top 5% — push them into the top 1%.";
        }
        else if (baseKey == "pct_push")
        {
            title = $"Percentile Push ({label})";
            description = $"These {label} scores are close to the next percentile bracket — replay them to climb.";
        }
        else if (baseKey.StartsWith("pct_push_", StringComparison.Ordinal))
        {
            title = $"Percentile Push: {name} ({label})";
            description = $"Replay these {label} {name} songs to jump to the next percentile bracket.";
        }
        if (baseKey == "unplayed_any") description = $"Unplayed songs from the {label}.";
        else if (baseKey.StartsWith("unplayed_", StringComparison.Ordinal)) description = $"Unplayed {name} songs from the {label}.";

        return One(variantKey, title, description, type, instrument, Finalize(selection, includeInstrumentInItems));
    }
    #endregion

    #region Near FC
    private static bool IsGoldNotFc95(SuggestionScore s) => (s.Stars ?? 0) == 6 && s.IsFullCombo != true && (s.Accuracy ?? 0) >= 950_000;
    private static bool IsRelaxedNearFc(SuggestionScore s) => (s.Stars ?? 0) >= 5 && (s.Accuracy ?? 0) >= 920_000 && s.IsFullCombo != true;
    private static bool IsGoldNotFc(SuggestionScore s) => (s.Stars ?? 0) == 6 && s.IsFullCombo != true;

    private const string FcNextTitle = "FC These Next!";
    private const string FcNextDescription = "If you can get gold stars, you can FC it!";
    private const string RelaxedTitle = "Close to FC (92%+)";
    private const string RelaxedDescription = "Great runs to try and FC next!";

    private List<SuggestionCategory> FcTheseNext() =>
        Emit("near_fc_any", FcNextTitle, FcNextDescription, SuggestionCategoryType.NearFC, null, Candidates(IsGoldNotFc95), true);

    private List<SuggestionCategory> FcTheseNextDecade() =>
        EmitDecade("near_fc_any", FcNextTitle, FcNextDescription, SuggestionCategoryType.NearFC, null, true, Candidates(IsGoldNotFc95));

    private List<SuggestionCategory> NearFcRelaxed() =>
        Emit("near_fc_relaxed", RelaxedTitle, RelaxedDescription, SuggestionCategoryType.NearFC, null, Candidates(IsRelaxedNearFc), true);

    private List<SuggestionCategory> NearFcRelaxedDecade() =>
        EmitDecade("near_fc_relaxed", RelaxedTitle, RelaxedDescription, SuggestionCategoryType.NearFC, null, true, Candidates(IsRelaxedNearFc));

    private List<SuggestionCategory> UnFcInstrument(Instrument instrument) =>
        Emit($"unfc_{instrument.ServiceId()}", $"Finish the {instrument.Label()} FCs",
            $"Play these songs again on {instrument.Label()} and grab an FC!", SuggestionCategoryType.NearFC, instrument,
            Candidates(instrument, IsGoldNotFc), false);

    private List<SuggestionCategory> UnFcInstrumentDecade(Instrument instrument) =>
        EmitDecade($"unfc_{instrument.ServiceId()}", $"Finish the {instrument.Label()} FCs",
            $"Play these songs again on {instrument.Label()} and grab an FC!", SuggestionCategoryType.NearFC, instrument, false,
            Candidates(instrument, IsGoldNotFc));

    private List<SuggestionCategory> SameNameNearFc()
    {
        var buckets = new Dictionary<string, List<Song>>(StringComparer.Ordinal);
        foreach (var song in songs)
        {
            if (ScoresFor(song.SongId) is null) continue;
            var key = Canon(song.Title);
            if (!buckets.TryGetValue(key, out var group)) buckets[key] = group = [];
            group.Add(song);
        }
        var groups = buckets.Where(p => p.Value.Count >= 2).OrderBy(p => p.Key, StringComparer.Ordinal).ToList();
        if (groups.Count == 0) return [];
        ShuffleInPlace(groups);
        var picked = groups[0].Value;
        var displayTitle = picked[0].Title.Trim();
        var poolAll = new List<Candidate>();
        foreach (var song in picked)
            poolAll.AddRange(CandidatesForSong(song, s => (s.Stars ?? 0) == 6 && s.IsFullCombo != true && (s.Accuracy ?? 0) >= 900_000));
        ShuffleInPlace(poolAll);
        var final = SelectNewFirst("samename_nearfc", poolAll.Take(30).ToList(), DisplayCount());
        if (final.Count == 0) return [];
        return One($"samename_nearfc_{displayTitle}", $"Close to FC: '{displayTitle}' Variants",
            "FC these same-name songs for a unique achievement!", SuggestionCategoryType.NearFC, null, Finalize(final, true));
    }
    #endregion

    #region Star progress
    private static bool IsAlmostSix(SuggestionScore s) => (s.Stars ?? 0) == 5 && (s.Accuracy ?? 0) >= 900_000;
    private static bool IsStarGain(SuggestionScore s) => (s.Stars ?? 0) is >= 3 and < 6;
    private static bool IsMoreStars(SuggestionScore s) => (s.Stars ?? 0) is >= 1 and < 6;

    private List<SuggestionCategory> AlmostSixStars() =>
        Emit("almost_six_star", "Push to Gold Stars", "Push these five-star runs to gold stars!", SuggestionCategoryType.StarProgress, null, Candidates(IsAlmostSix), true);

    private List<SuggestionCategory> AlmostSixStarsDecade() =>
        EmitDecade("almost_six_star", "Push to Gold Stars", "Push these five-star runs to gold stars!", SuggestionCategoryType.StarProgress, null, true, Candidates(IsAlmostSix));

    private List<SuggestionCategory> StarGains() =>
        Emit("star_gains", "Easy Star Gains", "Hit a new high score to get even more stars on these songs!", SuggestionCategoryType.StarProgress, null, Candidates(IsStarGain), true);

    private List<SuggestionCategory> StarGainsDecade() =>
        EmitDecade("star_gains", "Easy Star Gains", "Hit a new high score to get even more stars on these songs!", SuggestionCategoryType.StarProgress, null, true, Candidates(IsStarGain));

    private List<SuggestionCategory> GetMoreStars() =>
        Emit("more_stars", "Push These to Gold Stars", "Try gold-starring this selection of tracks!", SuggestionCategoryType.StarProgress, null, Candidates(IsMoreStars), true);

    private List<SuggestionCategory> GetMoreStarsDecade() =>
        EmitDecade("more_stars", "Push These to Gold Stars", "Try gold-starring this selection of tracks!", SuggestionCategoryType.StarProgress, null, true, Candidates(IsMoreStars));
    #endregion

    #region Unplayed
    private bool IsUnplayedOn(Song song, Instrument instrument) =>
        song.Supports(instrument) && (ScoreFor(song.SongId, instrument) is not { } score || (score.Stars ?? 0) == 0);

    private List<Candidate> FirstPlaysMixedPool()
    {
        var pool = new List<Candidate>();
        foreach (var song in songs)
        {
            var unplayed = InstrumentInfo.All.Where(i => IsUnplayedOn(song, i)).ToList();
            if (unplayed.Count == 0) continue;
            var eligible = firstPlaysMixedLastInstrument.TryGetValue(song.SongId, out var last) && unplayed.Count > 1
                ? unplayed.Where(i => i != last).ToList()
                : unplayed;
            foreach (var instrument in eligible) pool.Add(new Candidate(song, null, instrument));
        }
        return pool;
    }

    private List<SuggestionCategory> FirstPlaysMixed()
    {
        var pool = FirstPlaysMixedPool();
        if (pool.Count == 0) return [];
        ShuffleInPlace(pool);
        var final = SelectNewFirst("first_plays_mixed", pool, DisplayCount());
        foreach (var candidate in final)
            if (candidate.Instrument is { } i) firstPlaysMixedLastInstrument[candidate.Song.SongId] = i;
        if (final.Count == 0) return [];
        return One("first_plays_mixed", "First Plays (Mixed)", "Unplayed picks across instruments.", SuggestionCategoryType.Unplayed, null, Finalize(final, true));
    }

    private List<SuggestionCategory> FirstPlaysMixedDecade() =>
        EmitDecade("first_plays_mixed", "First Plays (Mixed)", "Unplayed picks across instruments.", SuggestionCategoryType.Unplayed, null, true, FirstPlaysMixedPool());

    private List<Candidate> UnplayedAnyPool() =>
        songs.Where(s => ScoresFor(s.SongId) is null).Select(s => new Candidate(s, null, null)).ToList();

    private List<SuggestionCategory> UnplayedAll()
    {
        var pool = UnplayedAnyPool();
        ShuffleInPlace(pool);
        if (!ShouldEmit("unplayed_any", FreshCount(pool))) return [];
        var final = SelectNewFirst("unplayed_any", pool, DisplayCount());
        if (final.Count == 0) return [];
        return One("unplayed_any", "Try Something New", "Songs you haven't played on any instrument yet.", SuggestionCategoryType.Unplayed, null, Finalize(final, false));
    }

    private List<SuggestionCategory> UnplayedAllDecade() =>
        EmitDecade("unplayed_any", "Try Something New", "Songs you haven't played on any instrument yet.", SuggestionCategoryType.Unplayed, null, false, UnplayedAnyPool());

    private List<Candidate> UnplayedInstrumentPool(Instrument instrument) =>
        songs.Where(s => IsUnplayedOn(s, instrument)).Select(s => new Candidate(s, null, null)).ToList();

    private List<SuggestionCategory> UnplayedInstrument(Instrument instrument)
    {
        var pool = UnplayedInstrumentPool(instrument);
        ShuffleInPlace(pool);
        var key = $"unplayed_{instrument.ServiceId()}";
        if (!ShouldEmit(key, FreshCount(pool))) return [];
        var final = SelectNewFirst(key, pool, DisplayCount());
        if (final.Count == 0) return [];
        return One(key, $"New on {instrument.Label()}", $"Songs you haven't played on {instrument.Label()} yet.",
            SuggestionCategoryType.Unplayed, instrument, Finalize(final, false));
    }

    private List<SuggestionCategory> UnplayedInstrumentDecade(Instrument instrument) =>
        EmitDecade($"unplayed_{instrument.ServiceId()}", $"New on {instrument.Label()}", $"Songs you haven't played on {instrument.Label()} yet.",
            SuggestionCategoryType.Unplayed, instrument, false, UnplayedInstrumentPool(instrument));
    #endregion

    #region Variety, artists, same name
    private Candidate LeadOrDrums(Song song)
    {
        var scores = ScoresFor(song.SongId) ?? NoScores;
        var score = scores.TryGetValue(Instrument.Lead, out var lead) ? lead : scores.TryGetValue(Instrument.Drums, out var drums) ? drums : null;
        return new Candidate(song, score, null);
    }

    private List<SuggestionCategory> VarietyPack()
    {
        var sorted = songs.OrderBy(s => Canon(s.Artist), StringComparer.Ordinal).ThenBy(s => s.SongId, StringComparer.Ordinal).ToList();
        ShuffleInPlace(sorted);
        var usedArtists = new HashSet<string>(StringComparer.Ordinal);
        var picks = new List<Song>();
        foreach (var song in sorted)
        {
            var key = Canon(song.Artist);
            if (usedArtists.Contains(key) || recentSongIds.Contains(song.SongId) || sessionShownSongs.Contains(song.SongId)) continue;
            usedArtists.Add(key);
            picks.Add(song);
            if (picks.Count == 5) break;
        }
        var freshPicks = picks.Count(s => !sessionShownSongs.Contains(s.SongId));
        if (!ShouldEmit("variety_pack", freshPicks)) return [];
        ShuffleInPlace(picks);
        var selected = SelectNewFirst("variety_pack", picks.Select(LeadOrDrums).ToList(), DisplayCount());
        var display = Finalize(selected, false);
        if (display.Count < 2) return [];
        var description = display.Count switch
        {
            2 => "Two different artists for variety.",
            3 => "Three different artists for variety.",
            4 => "Four different artists for variety.",
            _ => "Five different artists for variety.",
        };
        return One("variety_pack", "Variety Pack", description, SuggestionCategoryType.VarietyPack, null, display);
    }

    private List<SuggestionCategory> ArtistSamplerRotating()
    {
        var groups = new Dictionary<string, List<Song>>(StringComparer.Ordinal);
        foreach (var song in songs)
        {
            var key = Canon(song.Artist);
            if (!groups.TryGetValue(key, out var group)) groups[key] = group = [];
            group.Add(song);
        }
        var eligible = groups.Where(p => p.Value.Count >= 3).OrderBy(p => p.Key, StringComparer.Ordinal).ToList();
        if (eligible.Count == 0) return [];
        ShuffleInPlace(eligible);
        var chosen = eligible[0];
        var artist = Canon(chosen.Key);
        if (artist.Length == 0) return [];
        PushRecentArtist(artist);

        var picked = chosen.Value.OrderBy(s => s.SongId, StringComparer.Ordinal).Take(10).ToList();
        ShuffleInPlace(picked);
        if (picked.Count > 5) picked = picked.Take(DisplayCount()).ToList();
        var artistName = picked[0].Artist;
        // Apple/web substitute "Featured Artist" for a blank name and then refuse to emit it (so does a literal match).
        if (new StringInfo(artistName.Trim()).LengthInTextElements <= 1 || artistName == "Featured Artist") return [];
        var items = picked.Select(s => FinalizeOne(LeadOrDrums(s), false)).ToList();
        return One($"artist_sampler_{artistName}", $"{artistName} Essentials", $"A selection of songs by {artistName}.",
            SuggestionCategoryType.ArtistEssentials, null, items);
    }

    private List<SuggestionCategory> ArtistFocusUnplayed()
    {
        var groups = new Dictionary<string, List<Song>>(StringComparer.Ordinal);
        foreach (var song in songs)
        {
            if (ScoresFor(song.SongId) is not null) continue;
            var key = Canon(song.Artist);
            if (!groups.TryGetValue(key, out var group)) groups[key] = group = [];
            group.Add(song);
        }
        if (groups.Count == 0) return [];
        var entries = groups.OrderBy(p => p.Key, StringComparer.Ordinal).ToList();
        ShuffleInPlace(entries);
        var (artistKey, groupSongs) = (entries[0].Key, entries[0].Value);
        var displayName = groupSongs[0].Artist;
        var key2 = $"artist_unplayed_{artistKey}";
        var picked = SelectNewFirst(key2, groupSongs.Select(s => new Candidate(s, null, null)).ToList(), DisplayCount());
        if (picked.Count == 0) return [];
        return One(key2, $"Discover {displayName}", $"Unplayed songs from {displayName}.", SuggestionCategoryType.ArtistDiscover, null, Finalize(picked, false));
    }

    private List<SuggestionCategory> SameNameSets()
    {
        var groups = new Dictionary<string, List<Song>>(StringComparer.Ordinal);
        foreach (var song in songs)
        {
            var key = Canon(song.Title);
            if (!groups.TryGetValue(key, out var group)) groups[key] = group = [];
            group.Add(song);
        }
        var duplicates = groups.Where(p => p.Value.Count >= 2).OrderBy(p => p.Key, StringComparer.Ordinal).ToList();
        if (duplicates.Count == 0) return [];
        ShuffleInPlace(duplicates);
        var selected = SelectNewFirst("samename", duplicates[0].Value.Select(s => new Candidate(s, null, null)).ToList(), DisplayCount());
        if (selected.Count == 0) return [];
        var displayTitle = selected[0].Song.Title.Trim();
        return One($"samename_{displayTitle}", $"Songs Named '{displayTitle}'", "Different tracks sharing the same title.",
            SuggestionCategoryType.SameName, null, Finalize(selected, false));
    }
    #endregion

    #region Almost elite / percentile push
    private const string EliteDescription = "You're in the top 5% on these — one good run could crack the top 1%.";
    private const string PushDescription = "These scores are close to the next percentile bracket — replay them to climb.";

    private List<SuggestionCategory> AlmostElite() =>
        Emit("almost_elite", "Almost Elite", EliteDescription, SuggestionCategoryType.AlmostElite, null, Candidates(IsAlmostElite), true);

    private List<SuggestionCategory> AlmostEliteDecade() =>
        EmitDecade("almost_elite", "Almost Elite", EliteDescription, SuggestionCategoryType.AlmostElite, null, true, Candidates(IsAlmostElite));

    private List<SuggestionCategory> AlmostEliteInstrument(Instrument instrument) =>
        Emit($"almost_elite_{instrument.ServiceId()}", $"Almost Elite on {instrument.Label()}",
            $"Your {instrument.Label()} scores are in the top 5% — push them into the top 1%.", SuggestionCategoryType.AlmostElite,
            instrument, Candidates(instrument, IsAlmostElite), false);

    private List<SuggestionCategory> AlmostEliteInstrumentDecade(Instrument instrument) =>
        EmitDecade($"almost_elite_{instrument.ServiceId()}", $"Almost Elite on {instrument.Label()}",
            $"Your {instrument.Label()} scores are in the top 5% — push them into the top 1%.", SuggestionCategoryType.AlmostElite,
            instrument, false, Candidates(instrument, IsAlmostElite));

    private List<SuggestionCategory> PercentilePush() =>
        Emit("pct_push", "Percentile Push", PushDescription, SuggestionCategoryType.PercentilePush, null, Candidates(IsNearNextBracket), true);

    private List<SuggestionCategory> PercentilePushDecade() =>
        EmitDecade("pct_push", "Percentile Push", PushDescription, SuggestionCategoryType.PercentilePush, null, true, Candidates(IsNearNextBracket));

    private List<SuggestionCategory> PercentilePushInstrument(Instrument instrument) =>
        Emit($"pct_push_{instrument.ServiceId()}", $"Percentile Push: {instrument.Label()}",
            $"Replay these {instrument.Label()} songs to jump to the next percentile bracket.", SuggestionCategoryType.PercentilePush,
            instrument, Candidates(instrument, IsNearNextBracket), false);

    private List<SuggestionCategory> PercentilePushInstrumentDecade(Instrument instrument) =>
        EmitDecade($"pct_push_{instrument.ServiceId()}", $"Percentile Push: {instrument.Label()}",
            $"Replay these {instrument.Label()} songs to jump to the next percentile bracket.", SuggestionCategoryType.PercentilePush,
            instrument, false, Candidates(instrument, IsNearNextBracket));
    #endregion

    #region Stale songs
    private static bool IsStale(int ago, int minSeasonsAgo) => minSeasonsAgo >= 5 ? ago >= 5 : ago >= minSeasonsAgo;

    private static string StaleSuffix(int minSeasonsAgo) =>
        minSeasonsAgo >= 5 ? "5plus" : minSeasonsAgo.ToString(CultureInfo.InvariantCulture);

    private List<SuggestionCategory> StaleGlobal(int minSeasonsAgo)
    {
        if (currentSeason <= 0) return [];
        var pool = new List<Candidate>();
        foreach (var song in songs)
        {
            var latest = LatestSeason(song.SongId);
            if (latest > 0 && IsStale(currentSeason - latest, minSeasonsAgo)) pool.Add(new Candidate(song, null, null));
        }
        ShuffleInPlace(pool);
        var key = $"stale_global_{StaleSuffix(minSeasonsAgo)}";
        if (!ShouldEmit(key, FreshCount(pool))) return [];
        var final = SelectNewFirst(key, pool, DisplayCount());
        if (final.Count == 0) return [];
        var title = minSeasonsAgo == 1 ? "Play This Season"
            : minSeasonsAgo >= 5 ? "Untouched for 5+ Seasons" : $"Untouched for {minSeasonsAgo} Seasons";
        var description = minSeasonsAgo == 1 ? "Songs you haven't played on any instrument this season."
            : minSeasonsAgo >= 5 ? "Songs you haven't played on any instrument in 5 or more seasons."
            : $"Songs you haven't played on any instrument in at least {minSeasonsAgo} seasons.";
        return One(key, title, description, SuggestionCategoryType.Stale, null, Finalize(final, false));
    }

    private List<SuggestionCategory> StaleInstrument(Instrument instrument, int minSeasonsAgo)
    {
        if (currentSeason <= 0) return [];
        var pool = new List<Candidate>();
        foreach (var song in songs)
        {
            var season = InstrumentSeason(song.SongId, instrument);
            if (season > 0 && IsStale(currentSeason - season, minSeasonsAgo))
                pool.Add(new Candidate(song, ScoreFor(song.SongId, instrument), instrument));
        }
        ShuffleInPlace(pool);
        var key = $"stale_{instrument.ServiceId()}_{StaleSuffix(minSeasonsAgo)}";
        if (!ShouldEmit(key, FreshCount(pool))) return [];
        var final = SelectNewFirst(key, pool, DisplayCount());
        if (final.Count == 0) return [];
        var name = instrument.Label();
        var title = minSeasonsAgo == 1 ? $"Play {name} This Season"
            : minSeasonsAgo >= 5 ? $"{name} Untouched for 5+ Seasons" : $"{name} Untouched for {minSeasonsAgo} Seasons";
        var description = minSeasonsAgo == 1 ? $"Songs you haven't played on {name} this season."
            : minSeasonsAgo >= 5 ? $"Songs you haven't played on {name} in 5 or more seasons."
            : $"Songs you haven't played on {name} in at least {minSeasonsAgo} seasons.";
        return One(key, title, description, SuggestionCategoryType.Stale, instrument, Finalize(final, true));
    }
    #endregion

    #region Percentile improvement
    /// <summary>Buckets of every ranked chart on a song, in instrument order.</summary>
    private List<int> SongBuckets(IReadOnlyDictionary<Instrument, SuggestionScore> scores)
    {
        var buckets = new List<int>();
        foreach (var instrument in InstrumentInfo.All)
            if (scores.TryGetValue(instrument, out var score) && PercentileBucket(score) is { } bucket)
                buckets.Add(bucket);
        return buckets;
    }

    private List<SuggestionCategory> SamePercentileBucket()
    {
        var pool = new List<Candidate>();
        var songBucket = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var song in songs)
        {
            if (ScoresFor(song.SongId) is not { } scores) continue;
            var buckets = SongBuckets(scores);
            if (buckets.Count >= 2 && buckets.All(b => b == buckets[0]) && buckets[0] > 1)
            {
                pool.Add(new Candidate(song, null, null));
                songBucket[song.SongId] = buckets[0];
            }
        }
        ShuffleInPlace(pool);
        const string key = "same_pct_improve";
        if (!ShouldEmit(key, FreshCount(pool))) return [];
        var final = SelectNewFirst(key, pool, DisplayCount());
        if (final.Count == 0) return [];
        var items = final.Select(c => FinalizeOne(c, false) with { PercentileDisplay = $"Top {songBucket[c.Song.SongId]}%" }).ToList();
        return One(key, "Competitive Improvements",
            "Songs where your percentile is the same across all instruments. An improvement on any instrument moves you up everywhere.",
            SuggestionCategoryType.PctImprove, null, items);
    }

    private List<SuggestionCategory> SamePercentileBucketSpecific(int bucket)
    {
        var pool = new List<Candidate>();
        foreach (var song in songs)
        {
            if (ScoresFor(song.SongId) is not { } scores) continue;
            var buckets = SongBuckets(scores);
            if (buckets.Count >= 2 && buckets.All(b => b == bucket)) pool.Add(new Candidate(song, null, null));
        }
        ShuffleInPlace(pool);
        var key = $"same_pct_{bucket}";
        if (!ShouldEmit(key, FreshCount(pool))) return [];
        var final = SelectNewFirst(key, pool, DisplayCount());
        if (final.Count == 0) return [];
        var target = NextLowerThreshold(bucket) is { } next ? $"Top {next}%" : "a higher bracket";
        var items = final.Select(c => FinalizeOne(c, false) with { PercentileDisplay = $"Top {bucket}%" }).ToList();
        return One(key, $"Break Into {target}",
            $"Songs where all your instruments are ranked Top {bucket}%. Improve any instrument to break the tie and climb to {target}.",
            SuggestionCategoryType.PctImprove, null, items);
    }

    private List<SuggestionCategory> PercentileImproveBucket(int bucket) =>
        Emit($"pct_improve_{bucket}", $"Top {bucket}% Push",
            $"Songs with at least one instrument ranked Top {bucket}%. A small score bump could push you higher.",
            SuggestionCategoryType.PctImprove, null, Candidates(s => PercentileBucket(s) == bucket), true);

    private List<SuggestionCategory> PercentileImproveInstrument(Instrument instrument, int bucket) =>
        Emit($"pct_improve_{instrument.ServiceId()}_{bucket}", $"Top {bucket}% Push",
            $"Songs with {instrument.Label()} scores ranked Top {bucket}%. A small score bump could push you higher.",
            SuggestionCategoryType.PctImprove, instrument, Candidates(instrument, s => PercentileBucket(s) == bucket), false);

    private List<SuggestionCategory> ImproveInstrumentRankings(Instrument instrument)
    {
        var byBucket = new Dictionary<int, List<Candidate>>();
        foreach (var song in songs)
        {
            if (ScoreFor(song.SongId, instrument) is not { } score || PercentileBucket(score) is not { } bucket || bucket <= 1) continue;
            if (!byBucket.TryGetValue(bucket, out var group)) byBucket[bucket] = group = [];
            group.Add(new Candidate(song, score, instrument));
        }
        if (byBucket.Count < 3) return [];
        var picks = new List<Candidate>();
        foreach (var bucket in byBucket.Keys.Order())
        {
            var group = byBucket[bucket];
            ShuffleInPlace(group);
            picks.Add(group[0]);
        }
        ShuffleInPlace(picks);
        var key = $"improve_rankings_{instrument.ServiceId()}";
        if (!ShouldEmit(key, FreshCount(picks))) return [];
        var final = SelectNewFirst(key, picks, Math.Min(DisplayCount(), picks.Count));
        if (final.Count < 3) return [];
        return One(key, $"Improve {instrument.Label()} Rankings",
            $"A varied mix of {instrument.Label()} songs across different percentile brackets — all with room to grow.",
            SuggestionCategoryType.PctImprove, instrument, Finalize(final, false));
    }
    #endregion

    #region Near max score
    /// <summary>Scored charts whose CHOpt max gap falls in <c>(MinGap, MaxGap]</c>.</summary>
    private List<Candidate> NearMaxCandidates(NearMaxTier tier)
    {
        var output = new List<Candidate>();
        foreach (var song in songs)
        {
            if (song.MaxScores is null || ScoresFor(song.SongId) is not { } scores) continue;
            foreach (var instrument in InstrumentInfo.All)
            {
                if (!scores.TryGetValue(instrument, out var score) || score.Score <= 0 || song.MaxScore(instrument) is not { } max) continue;
                var gap = max - score.Score;
                if (gap > tier.MinGap && gap <= tier.MaxGap) output.Add(new Candidate(song, score, instrument));
            }
        }
        return output;
    }

    private List<SuggestionCategory> NearMaxScore(NearMaxTier tier) =>
        Emit($"near_max_{tier.Label}", tier.Title, tier.Description, SuggestionCategoryType.NearMax, null, NearMaxCandidates(tier), true);

    private List<SuggestionCategory> NearMaxScoreDecade(NearMaxTier tier) =>
        EmitDecade($"near_max_{tier.Label}", tier.Title, tier.Description, SuggestionCategoryType.NearMax, null, true, NearMaxCandidates(tier));
    #endregion

    #region Rival strategies
    private static Dictionary<string, RivalSongMatch> MatchLookup(IReadOnlyList<RivalSongMatch> matches)
    {
        var output = new Dictionary<string, RivalSongMatch>(StringComparer.Ordinal);
        foreach (var match in matches) output[RivalDataIndex.ClosestKey(match.SongId, match.Instrument)] = match;
        return output;
    }

    private static int? DeltaFor(Dictionary<string, RivalSongMatch> lookup, Candidate candidate) =>
        candidate.Instrument is { } i && lookup.TryGetValue(RivalDataIndex.ClosestKey(candidate.Song.SongId, i), out var match) ? match.RankDelta : null;

    private SuggestionSongItem MapRivalItem(Candidate candidate, RivalInfo rival, int rankDelta) =>
        FinalizeOne(candidate, true) with { RivalName = rival.DisplayName, RivalAccountId = rival.AccountId, RivalRankDelta = rankDelta };

    private RivalSongMatch? ClosestMatch(Candidate candidate) =>
        candidate.Instrument is { } i && rivalData is { } data &&
        data.ClosestRivalBySong.TryGetValue(RivalDataIndex.ClosestKey(candidate.Song.SongId, i), out var match) ? match : null;

    private SuggestionSongItem MapWithClosestRival(Candidate candidate)
    {
        var item = FinalizeOne(candidate, true);
        return ClosestMatch(candidate) is { } match
            ? item with { RivalName = match.Rival.DisplayName, RivalAccountId = match.Rival.AccountId, RivalRankDelta = match.RankDelta }
            : item;
    }

    private string ClosestRivalName(Candidate candidate) => ClosestMatch(candidate)?.Rival.DisplayName ?? "a rival";

    private IReadOnlyList<RivalSongMatch>? MatchesFor(string rivalId) =>
        rivalData is { } data && data.ByRival.TryGetValue(rivalId, out var matches) && matches.Count > 0 ? matches : null;

    private Candidate CandidateFor(Song song, RivalSongMatch match) => new(song, ScoreFor(match.SongId, match.Instrument), match.Instrument);

    private List<Candidate> RivalPool(IReadOnlyList<RivalSongMatch> matches, Func<RivalSongMatch, bool> keep)
    {
        var pool = new List<Candidate>();
        foreach (var match in matches)
            if (keep(match) && songsById.TryGetValue(match.SongId, out var song)) pool.Add(CandidateFor(song, match));
        return pool;
    }

    /// <summary>Shared emit → select → map tail of the per-rival families.</summary>
    private List<SuggestionCategory> EmitRival(string key, string title, string description, RivalInfo rival,
        Dictionary<string, RivalSongMatch> lookup, List<Candidate> pool)
    {
        if (!ShouldEmit(key, FreshCount(pool))) return [];
        var final = SelectNewFirst(key, pool, DisplayCount());
        if (final.Count == 0) return [];
        return One(key, title, description, SuggestionCategoryType.SongRivals, null,
            final.Select(c => MapRivalItem(c, rival, DeltaFor(lookup, c) ?? 0)).ToList());
    }

    private List<SuggestionCategory> SongRivalGap(string rivalId)
    {
        if (MatchesFor(rivalId) is not { } matches) return [];
        var rival = matches[0].Rival;
        var lookup = MatchLookup(matches);
        var pool = RivalPool(matches, m => m.RankDelta < 0);
        if (pool.Count == 0) return [];
        pool = pool.OrderBy(c => Math.Abs(DeltaFor(lookup, c) ?? 999)).ToList();
        return EmitRival($"song_rival_gap_{rivalId}", $"Close the Gap vs {rival.DisplayName}",
            $"Songs where {rival.DisplayName} barely leads you. One good run could overtake them.", rival, lookup, pool);
    }

    private List<SuggestionCategory> SongRivalProtect(string rivalId)
    {
        if (MatchesFor(rivalId) is not { } matches) return [];
        var rival = matches[0].Rival;
        var lookup = MatchLookup(matches);
        var pool = RivalPool(matches, m => m.RankDelta > 0);
        if (pool.Count == 0) return [];
        pool = pool.OrderBy(c => DeltaFor(lookup, c) ?? 999).ToList();
        return EmitRival($"song_rival_protect_{rivalId}", $"Protect Your Lead vs {rival.DisplayName}",
            $"You're barely ahead of {rival.DisplayName} on these. Don't let them pass you.", rival, lookup, pool);
    }

    private List<SuggestionCategory> SongRivalBattleground()
    {
        if (rivalData is not { } data) return [];
        var counts = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var matches in data.ByRival.Values)
            foreach (var match in matches)
                if (Math.Abs(match.RankDelta) <= 10)
                {
                    var k = RivalDataIndex.ClosestKey(match.SongId, match.Instrument);
                    counts[k] = counts.GetValueOrDefault(k) + 1;
                }
        var pool = new List<Candidate>();
        foreach (var k in counts.Keys.Order(StringComparer.Ordinal))
        {
            if (counts[k] < 2) continue;
            var separator = k.LastIndexOf(':');
            var songId = k[..separator];
            if (!InstrumentInfo.TryParse(k[(separator + 1)..], out var instrument) || !songsById.TryGetValue(songId, out var song)) continue;
            pool.Add(new Candidate(song, ScoreFor(songId, instrument), instrument));
        }
        if (pool.Count == 0) return [];
        ShuffleInPlace(pool);
        const string key = "song_rival_battleground";
        if (!ShouldEmit(key, FreshCount(pool))) return [];
        var final = SelectNewFirst(key, pool, DisplayCount());
        if (final.Count == 0) return [];
        return One(key, "Battleground Songs", "Multiple rivals are clustered around your rank on these songs. Every position matters.",
            SuggestionCategoryType.SongRivals, null, final.Select(MapWithClosestRival).ToList());
    }

    /// <summary>Curated per-rival mix; gated only on "already emitted" (no probability roll), like the web.</summary>
    private List<SuggestionCategory> SongRivalSpotlight(string rivalId)
    {
        if (MatchesFor(rivalId) is not { Count: >= 3 } matches) return [];
        var rival = matches[0].Rival;
        var behind = matches.Where(m => m.RankDelta < 0).OrderBy(m => Math.Abs(m.RankDelta)).ToList();
        var ahead = matches.Where(m => m.RankDelta > 0).OrderBy(m => m.RankDelta).ToList();
        var closest = matches.OrderBy(m => Math.Abs(m.RankDelta)).ToList();
        var picks = new List<RivalSongMatch>();
        picks.AddRange(behind.Take(2));
        picks.AddRange(ahead.Take(2));
        if (closest.FirstOrDefault(c => !picks.Any(p => p.SongId == c.SongId)) is { } closestNew) picks.Add(closestNew);
        var pool = RivalPool(picks, _ => true);
        if (pool.Count < 3) return [];
        var key = $"song_rival_spotlight_{rivalId}";
        if (emitted.Contains(key)) return [];
        var lookup = MatchLookup(matches);
        return One(key, $"Rival Spotlight: {rival.DisplayName}",
            $"A curated mix of your rivalry with {rival.DisplayName} — catches, defenses, and closest battles.",
            SuggestionCategoryType.SongRivals, null, pool.Select(c => MapRivalItem(c, rival, DeltaFor(lookup, c) ?? 0)).ToList());
    }

    private List<SuggestionCategory> SongRivalSlipping(string rivalId)
    {
        if (MatchesFor(rivalId) is not { } matches) return [];
        var rival = matches[0].Rival;
        var pool = RivalPool(matches, m => m.RankDelta < -20);
        if (pool.Count == 0) return [];
        ShuffleInPlace(pool);
        return EmitRival($"song_rival_slipping_{rivalId}", $"{rival.DisplayName} is Pulling Ahead",
            $"{rival.DisplayName} has a big lead on these songs. Time to close the gap.", rival, MatchLookup(matches), pool);
    }

    private List<SuggestionCategory> SongRivalDominate(string rivalId)
    {
        if (MatchesFor(rivalId) is not { } matches) return [];
        var rival = matches[0].Rival;
        var pool = RivalPool(matches, m => m.RankDelta > 30);
        if (pool.Count == 0) return [];
        ShuffleInPlace(pool);
        return EmitRival($"song_rival_dominate_{rivalId}", $"Dominate {rival.DisplayName}",
            $"You're crushing {rival.DisplayName} on these. Keep up the dominance.", rival, MatchLookup(matches), pool);
    }

    /// <summary>Shared body of the four cross-pollination families.</summary>
    private List<SuggestionCategory> CrossPollinate(string key, Func<SuggestionScore, bool> predicate, bool requireRivalAhead,
        Func<string, string> title, string description)
    {
        if (rivalData is null) return [];
        var pool = Candidates(predicate).Where(c => ClosestMatch(c) is { } m && (!requireRivalAhead || m.RankDelta < 0)).ToList();
        if (pool.Count == 0) return [];
        ShuffleInPlace(pool);
        if (!ShouldEmit(key, FreshCount(pool))) return [];
        var final = SelectNewFirst(key, pool, DisplayCount());
        if (final.Count == 0) return [];
        return One(key, title(ClosestRivalName(final[0])), description, SuggestionCategoryType.SongRivals, null,
            final.Select(MapWithClosestRival).ToList());
    }

    private List<SuggestionCategory> SongRivalNearFc() =>
        CrossPollinate("song_rival_near_fc", IsRelaxedNearFc, false, name => $"FC These to Beat {name}!",
            "Almost FC songs where your rival also competes. Nail the combo to pull ahead.");

    private List<SuggestionCategory> SongRivalStale() =>
        currentSeason == 0 ? [] :
        CrossPollinate("song_rival_stale", s => s.Season is { } season && season != 0 && currentSeason - season >= 2, true,
            _ => "Stale Songs Your Rivals Are Beating You On", "Songs you haven't touched in a while where rivals have pulled ahead.");

    private List<SuggestionCategory> SongRivalStarGains() =>
        CrossPollinate("song_rival_star_gains", s => (s.Stars ?? 0) is >= 3 and <= 5, true, name => $"Gain Stars & Beat {name}",
            "Improving your star count on these would also overtake a rival.");

    private List<SuggestionCategory> SongRivalPctPush() =>
        CrossPollinate("song_rival_pct_push", s => PercentileBucket(s) is > 1, true, name => $"Climb Past {name}",
            "A percentile push on these would also move you past a rival.");
    #endregion
}
#endregion
