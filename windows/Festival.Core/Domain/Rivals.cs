using System.Globalization;

namespace Festival.Core.Domain;

#region Direction
/// <summary>Which half of a rivals list a row came from.</summary>
public enum RivalDirection
{
    /// <summary>The rival is ahead of the player.</summary>
    Above,
    /// <summary>The player is ahead of the rival.</summary>
    Below,
}
#endregion

#region Row text
/// <summary>
/// Rival row pill copy (web <c>rivals.songsAhead</c>/<c>songsBehind</c>), shared by the Rivals row and the First Run
/// rival demos so they cannot drift. Counts are from the player's perspective: "ahead" is the wire
/// <c>behindCount</c>, "behind" the wire <c>aheadCount</c>. There is deliberately no shared-song copy (owner decision,
/// issues #40/#67/#267): that count is always ahead + behind.
/// </summary>
public static class RivalRowText
{
    /// <summary><c>{n} songs ahead</c>.</summary>
    /// <param name="songs">Songs the player leads.</param>
    /// <returns>Pill text.</returns>
    public static string Ahead(int songs) => string.Create(CultureInfo.CurrentCulture, $"{songs:N0} songs ahead");

    /// <summary><c>{n} songs behind</c>.</summary>
    /// <param name="songs">Songs the rival leads.</param>
    /// <returns>Pill text.</returns>
    public static string Behind(int songs) => string.Create(CultureInfo.CurrentCulture, $"{songs:N0} songs behind");
}
#endregion

#region Combos
/// <summary>
/// Cross-instrument combo scopes (web <c>comboUtils.ts</c>/<c>combos.ts</c>): hex bitmask IDs over the service's
/// instrument order, plus the non-bitmask Pro Drums family token.
/// </summary>
public static class RivalCombo
{
    /// <summary>The Pro Drums family token (<c>PRO_DRUMS_RIVAL_SCOPE</c>).</summary>
    public const string ProDrumsToken = "pro_drums";

    /// <summary>Instrument groups a bitmask combo may be drawn from (OG band 0x0f, Pro Strings 0x30).</summary>
    private static readonly int[] GroupMasks = [0x0f, 0x30];

    /// <summary>Mask of the Pro Drums family.</summary>
    private static readonly int ProDrumsFamilyMask = Mask([Instrument.ProCymbals, Instrument.ProDrums]);

    /// <summary>Bitmask of a set of instruments (bit = service order index).</summary>
    /// <param name="instruments">Instruments.</param>
    /// <returns>Mask.</returns>
    public static int Mask(IEnumerable<Instrument> instruments) => instruments.Aggregate(0, (mask, i) => mask | (1 << (int)i));

    /// <summary>Instruments of a mask in service order.</summary>
    /// <param name="mask">Mask.</param>
    /// <returns>Instruments.</returns>
    public static IReadOnlyList<Instrument> FromMask(int mask) => [.. InstrumentInfo.All.Where(i => (mask & (1 << (int)i)) != 0)];

    /// <summary>Hex combo ID (web <c>comboIdFromInstruments</c>), lowercase and at least two digits.</summary>
    /// <param name="instruments">Instruments.</param>
    /// <returns>Combo ID such as <c>03</c>.</returns>
    public static string ComboId(IEnumerable<Instrument> instruments) =>
        Mask(instruments).ToString("x2", CultureInfo.InvariantCulture);

    /// <summary>The single cross-instrument scope for Settings-visible charts (web <c>deriveRivalScopeFromSettings</c>).</summary>
    /// <param name="visible">Visible instruments.</param>
    /// <returns><see cref="ProDrumsToken"/>, a within-group combo ID, or <see langword="null"/>.</returns>
    public static string? DeriveToken(IEnumerable<Instrument> visible)
    {
        var mask = Mask(visible);
        if (mask == ProDrumsFamilyMask) return ProDrumsToken;
        return int.PopCount(mask) >= 2 && GroupMasks.Any(g => (mask & ~g) == 0) ? ComboId(FromMask(mask)) : null;
    }

    /// <summary>Instruments named by a combo token.</summary>
    /// <param name="token"><see cref="ProDrumsToken"/> or a 1–4 digit hex ID over the nine charts.</param>
    /// <returns>Instruments, or <see langword="null"/> for an invalid token.</returns>
    public static IReadOnlyList<Instrument>? InstrumentsFor(string? token)
    {
        if (token == ProDrumsToken) return [Instrument.ProCymbals, Instrument.ProDrums];
        if (token is not { Length: >= 1 and <= 4 } || !token.All(char.IsAsciiHexDigit) ||
            !int.TryParse(token, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var mask) ||
            mask == 0 || mask >= 1 << InstrumentInfo.All.Count)
            return null;
        return FromMask(mask);
    }

    /// <summary>Display label (web <c>rivals.proDrumsFamily</c>/<c>rivals.combo</c>).</summary>
    /// <param name="token">Combo token.</param>
    /// <returns>Label.</returns>
    public static string Label(string token) => token == ProDrumsToken ? "Pro Drums Family" : "Combined";
}
#endregion

#region Scope
/// <summary>Which Settings-derived scope a legacy web link names without instruments.</summary>
public enum RivalSettingsScope
{
    /// <summary><c>category=common</c>: every visible instrument, intersected.</summary>
    Common,
    /// <summary><c>category=combo</c>: the Settings-derived combo.</summary>
    Combo,
}

/// <summary>
/// The typed rival scope a route carries (no navigation side channel): which list or detail endpoint answers it.
/// Carried on <c>AllRivals</c>, <c>RivalDetail</c> and <c>Rivalry</c> routes so deep links behave like taps.
/// </summary>
public abstract record RivalScope
{
    /// <summary>Solo-chart "shared songs" rivals; two or more instruments means Common Rivals (intersection).</summary>
    public sealed record Song : RivalScope
    {
        /// <summary>Creates the scope.</summary>
        /// <param name="instruments">One or more charts (order and duplicates are normalized).</param>
        public Song(IEnumerable<Instrument> instruments) => Mask = RivalCombo.Mask(instruments);

        /// <summary>Canonical instrument mask (value equality).</summary>
        public int Mask { get; }

        /// <summary>Charts in service order.</summary>
        public IReadOnlyList<Instrument> Instruments => RivalCombo.FromMask(Mask);

        /// <summary>Whether this is the Common Rivals intersection.</summary>
        public bool IsCommon => int.PopCount(Mask) > 1;
    }

    /// <summary>A global per-instrument leaderboard's neighbouring rivals.</summary>
    /// <param name="Instrument">Chart.</param>
    /// <param name="RankBy">Metric.</param>
    public sealed record Leaderboard(Instrument Instrument, RankingMetric RankBy) : RivalScope;

    /// <summary>A server-computed combo or Pro Drums family list.</summary>
    /// <param name="Token">Hex combo ID or <see cref="RivalCombo.ProDrumsToken"/>.</param>
    public sealed record Combo(string Token) : RivalScope
    {
        /// <summary>Constituent charts (empty for an invalid token).</summary>
        public IReadOnlyList<Instrument> Instruments => RivalCombo.InstrumentsFor(Token) ?? [];
    }

    /// <summary>A legacy web link resolved against Settings when the page loads.</summary>
    /// <param name="Kind">Common or combo.</param>
    public sealed record FromSettings(RivalSettingsScope Kind) : RivalScope;

    /// <summary>Resolves <see cref="FromSettings"/> against visible charts; concrete scopes pass through.</summary>
    /// <param name="visible">Settings-visible charts.</param>
    /// <returns>A concrete scope, or <see langword="null"/> when Settings cannot supply one.</returns>
    public RivalScope? Resolve(IReadOnlyList<Instrument> visible) => this switch
    {
        FromSettings { Kind: RivalSettingsScope.Common } => visible.Count >= 2 ? new Song(visible) : null,
        FromSettings => RivalCombo.DeriveToken(visible) is { } token ? new Combo(token) : null,
        Song s when s.Mask == 0 => null,
        Combo c when c.Instruments.Count == 0 => null,
        _ => this,
    };

    /// <summary>Page title for a list of this scope (web <c>rivals.*RivalsShort</c>).</summary>
    public string ListTitle => this switch
    {
        Song { IsCommon: true } or FromSettings { Kind: RivalSettingsScope.Common } => "Common Rivals",
        Song s => $"{s.Instruments.FirstOrDefault().Label()} Rivals",
        Leaderboard l => $"{l.Instrument.Label()} Rivals",
        Combo c => $"{RivalCombo.Label(c.Token)} Rivals",
        _ => "Combined Rivals",
    };

    /// <summary>Compact token for <c>?scope=</c> on rival detail and rivalry paths.</summary>
    /// <returns><c>song:A,B</c>, <c>leaderboard:A:metric</c>, <c>combo:03</c> or <c>settings:common</c>.</returns>
    public string ToToken() => this switch
    {
        Song s => "song:" + string.Join(',', s.Instruments.Select(i => i.ServiceId())),
        Leaderboard l => $"leaderboard:{l.Instrument.ServiceId()}:{l.RankBy.ServiceId()}",
        Combo c => "combo:" + c.Token,
        FromSettings f => "settings:" + f.Kind.ToString().ToLowerInvariant(),
        _ => throw new InvalidOperationException(),
    };

    /// <summary>Parses <see cref="ToToken"/> output.</summary>
    /// <param name="token">Token text.</param>
    /// <returns>Scope, or <see langword="null"/> when malformed.</returns>
    public static RivalScope? FromToken(string? token)
    {
        if (token is null) return null;
        var parts = token.Split(':');
        switch (parts)
        {
            case ["song", var list]:
                var instruments = list.Split(',').Select(p => InstrumentInfo.TryParse(p, out var i) ? i : (Instrument?)null).ToArray();
                return instruments.Length > 0 && instruments.All(i => i is not null) ? new Song(instruments.Select(i => i!.Value)) : null;
            case ["leaderboard", var chart, var metric]:
                return InstrumentInfo.TryParse(chart, out var instrument) && RankingMetricInfo.TryParse(metric, out var rankBy)
                    ? new Leaderboard(instrument, rankBy) : null;
            case ["combo", var comboToken]:
                return RivalCombo.InstrumentsFor(comboToken) is not null ? new Combo(comboToken) : null;
            case ["settings", var kind]:
                return Enum.TryParse<RivalSettingsScope>(kind, ignoreCase: true, out var parsed) && Enum.IsDefined(parsed)
                    ? new FromSettings(parsed) : null;
            default:
                return null;
        }
    }

    /// <summary>Web <c>/rivals/all</c> query pairs (<c>category</c>, <c>mode</c>, <c>rankBy</c>, <c>instruments</c>).</summary>
    /// <returns>Pairs with <see langword="null"/> for absent values.</returns>
    public (string Key, string? Value)[] ToAllRivalsQuery() => this switch
    {
        Song { IsCommon: true } s => [("category", "common"), ("instruments", string.Join(',', s.Instruments.Select(i => i.ServiceId())))],
        Song s => [("category", s.Instruments.FirstOrDefault().ServiceId())],
        Leaderboard l => [("category", l.Instrument.ServiceId()), ("mode", "leaderboard"), ("rankBy", l.RankBy.ServiceId())],
        Combo c => [("category", c.Token)],
        FromSettings f => [("category", f.Kind.ToString().ToLowerInvariant())],
        _ => [],
    };

    /// <summary>Parses web <c>/rivals/all</c> query values (default category is <c>common</c>, as on the web).</summary>
    /// <param name="category"><c>common</c>, <c>combo</c>, an instrument, a hex combo or <c>pro_drums</c>.</param>
    /// <param name="mode"><c>leaderboard</c> for leaderboard rivals.</param>
    /// <param name="rankBy">Leaderboard metric.</param>
    /// <param name="instruments">Optional explicit comma-separated Common Rivals instruments.</param>
    /// <returns>Scope, or <see langword="null"/> for an unknown category.</returns>
    public static RivalScope? FromAllRivalsQuery(string? category, string? mode, string? rankBy, string? instruments)
    {
        category ??= "common";
        var isChart = InstrumentInfo.TryParse(category, out var chart);
        if (mode == "leaderboard")
            return isChart ? new Leaderboard(chart, RankingMetricInfo.TryParse(rankBy, out var metric) ? metric : RankingMetric.TotalScore) : null;
        if (isChart) return new Song([chart]);
        if (category == "common")
            return instruments is null ? new FromSettings(RivalSettingsScope.Common) : FromToken("song:" + instruments);
        if (category == "combo") return new FromSettings(RivalSettingsScope.Combo);
        return RivalCombo.InstrumentsFor(category) is not null ? new Combo(category) : null;
    }
}
#endregion

#region Common rivals
/// <summary>Rivals present in every loaded per-instrument list (web <c>RivalsPage</c> <c>commonRivals</c>).</summary>
public static class RivalCommonRivals
{
    /// <summary>
    /// Intersects two or more lists: a rival must appear in every list; direction is a majority vote (ties favour
    /// above); the highest <c>sharedSongCount</c> entry represents the rival; each group sorts by <c>rivalScore</c> descending.
    /// </summary>
    /// <param name="lists">Each loaded instrument's list.</param>
    /// <returns>Above and below groups (empty for fewer than two lists).</returns>
    public static (List<RivalSummary> Above, List<RivalSummary> Below) Intersect(IReadOnlyList<RivalsListResponse> lists)
    {
        if (lists.Count < 2) return ([], []);
        var counts = new Dictionary<string, int>(StringComparer.Ordinal);
        var above = new Dictionary<string, List<RivalSummary>>(StringComparer.Ordinal);
        var below = new Dictionary<string, List<RivalSummary>>(StringComparer.Ordinal);
        var order = new List<string>();
        foreach (var list in lists)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            var aboveIds = list.Above.Select(r => r.AccountId).ToHashSet(StringComparer.Ordinal);
            foreach (var rival in list.Above.Concat(list.Below))
            {
                // Anonymous rows (empty account ID) can't be matched across charts.
                if (rival.AccountId.Length == 0 || !seen.Add(rival.AccountId)) continue;
                if (!counts.TryGetValue(rival.AccountId, out var count)) order.Add(rival.AccountId);
                counts[rival.AccountId] = count + 1;
                var bucket = aboveIds.Contains(rival.AccountId) ? above : below;
                if (!bucket.TryGetValue(rival.AccountId, out var entries)) bucket[rival.AccountId] = entries = [];
                entries.Add(rival);
            }
        }
        var resultAbove = new List<RivalSummary>();
        var resultBelow = new List<RivalSummary>();
        foreach (var id in order.Where(id => counts[id] >= lists.Count))
        {
            var up = above.GetValueOrDefault(id) ?? [];
            var down = below.GetValueOrDefault(id) ?? [];
            var best = up.Concat(down).Aggregate((a, b) => a.SharedSongCount >= b.SharedSongCount ? a : b);
            (up.Count >= down.Count ? resultAbove : resultBelow).Add(best);
        }
        resultAbove.Sort((a, b) => b.RivalScore.CompareTo(a.RivalScore));
        resultBelow.Sort((a, b) => b.RivalScore.CompareTo(a.RivalScore));
        return (resultAbove, resultBelow);
    }
}
#endregion

#region Categories
/// <summary>Tone of a rivalry category.</summary>
public enum RivalCategorySentiment
{
    /// <summary>Mixed.</summary>
    Neutral,
    /// <summary>The player leads.</summary>
    Positive,
    /// <summary>The rival leads.</summary>
    Negative,
}

/// <summary>One themed grouping of shared songs (web <c>rivalCategories.ts</c>).</summary>
/// <param name="Key">Stable key used as the rivalry <c>mode</c>.</param>
/// <param name="Title">Title Case heading.</param>
/// <param name="Subtitle">Description.</param>
/// <param name="Sentiment">Tone.</param>
/// <param name="Songs">Songs in the category's order.</param>
public sealed record RivalCategory(string Key, string Title, string Subtitle, RivalCategorySentiment Sentiment, IReadOnlyList<RivalSongComparison> Songs);

/// <summary>Native port of <c>categorizeRivalSongs</c>.</summary>
public static class RivalCategorization
{
    private const int ClosestBattlesCount = 5;

    private static readonly Dictionary<string, (string Title, string Subtitle, RivalCategorySentiment Sentiment)> Meta = new(StringComparer.Ordinal)
    {
        ["closest_battles"] = ("Closest Battles", "Songs where you and your rival are neck and neck.", RivalCategorySentiment.Neutral),
        ["almost_passed"] = ("Almost Passed", "You're just behind — one good run could flip these.", RivalCategorySentiment.Negative),
        ["slipping_away"] = ("Slipping Away", "They're pulling further ahead on these songs.", RivalCategorySentiment.Negative),
        ["barely_winning"] = ("Barely Winning", "You're just ahead — don't let them catch up.", RivalCategorySentiment.Positive),
        ["pulling_forward"] = ("Pulling Forward", "You have a solid lead on these songs.", RivalCategorySentiment.Positive),
        ["dominating_them"] = ("Dominating Them", "You're far ahead — these are your strongest matchups.", RivalCategorySentiment.Positive),
    };

    /// <summary>Title for a category key, or the key itself when unknown (as on the web).</summary>
    /// <param name="key">Category key.</param>
    /// <returns>Heading.</returns>
    public static string Title(string key) => Meta.TryGetValue(key, out var meta) ? meta.Title : key;

    /// <summary>Whether a key names a known category.</summary>
    /// <param name="key">Category key.</param>
    /// <returns><see langword="true"/> for the six web keys.</returns>
    public static bool IsKnown(string? key) => key is not null && Meta.ContainsKey(key);

    /// <summary>Splits shared songs into non-empty categories in web order.</summary>
    /// <param name="songs">Compared songs.</param>
    /// <returns>Categories.</returns>
    public static List<RivalCategory> Categorize(IReadOnlyList<RivalSongComparison> songs)
    {
        var categories = new List<RivalCategory>();
        if (songs.Count == 0) return categories;
        var userLeads = songs.Where(s => s.RankDelta > 0).OrderBy(s => s.RankDelta).ToList();
        var rivalLeads = songs.Where(s => s.RankDelta < 0).OrderByDescending(s => s.RankDelta).ToList();
        Add(categories, "closest_battles", songs.OrderBy(s => Math.Abs((long)s.RankDelta)).Take(ClosestBattlesCount));
        if (rivalLeads.Count > 0)
        {
            var half = (rivalLeads.Count + 1) / 2;
            Add(categories, "almost_passed", rivalLeads.Take(half));
            Add(categories, "slipping_away", rivalLeads.Skip(half));
        }
        if (userLeads.Count > 0)
        {
            var third = (userLeads.Count + 2) / 3;
            Add(categories, "barely_winning", userLeads.Take(third));
            Add(categories, "pulling_forward", userLeads.Skip(third).Take(third));
            Add(categories, "dominating_them", userLeads.Skip(third * 2));
        }
        return categories;
    }

    /// <summary>Adds a category when it has songs.</summary>
    /// <param name="categories">Result.</param>
    /// <param name="key">Key.</param>
    /// <param name="songs">Songs.</param>
    private static void Add(List<RivalCategory> categories, string key, IEnumerable<RivalSongComparison> songs)
    {
        var list = songs.ToList();
        if (list.Count == 0) return;
        var meta = Meta[key];
        categories.Add(new RivalCategory(key, meta.Title, meta.Subtitle, meta.Sentiment, list));
    }
}
#endregion

#region Head to head
/// <summary>Rivalry song orderings (native sort control; the web keeps category order).</summary>
public enum RivalrySort
{
    /// <summary>The category's own order.</summary>
    Category,
    /// <summary>Smallest rank gap first.</summary>
    Closest,
    /// <summary>Your biggest leads first.</summary>
    YouLead,
    /// <summary>Their biggest leads first.</summary>
    TheyLead,
    /// <summary>Song title A–Z.</summary>
    Title,
}

/// <summary>Head-to-head summaries, orderings and number formatting for rival comparisons.</summary>
public static class RivalHeadToHead
{
    /// <summary>Picker label.</summary>
    /// <param name="sort">Sort.</param>
    /// <returns>Label.</returns>
    public static string Label(this RivalrySort sort) => sort switch
    {
        RivalrySort.Category => "Default",
        RivalrySort.Closest => "Closest Gap",
        RivalrySort.YouLead => "Your Biggest Leads",
        RivalrySort.TheyLead => "Their Biggest Leads",
        _ => "Title",
    };

    /// <summary>Orders songs; ties keep the incoming order.</summary>
    /// <param name="songs">Category songs.</param>
    /// <param name="sort">Sort.</param>
    /// <returns>Ordered copy.</returns>
    public static List<RivalSongComparison> Sort(IEnumerable<RivalSongComparison> songs, RivalrySort sort) => Sort(songs, s => s, sort);

    /// <summary>Orders items that wrap a comparison; ties keep the incoming order.</summary>
    /// <typeparam name="T">Item type.</typeparam>
    /// <param name="items">Items.</param>
    /// <param name="comparison">Comparison accessor.</param>
    /// <param name="sort">Sort.</param>
    /// <param name="title">Displayed title for <see cref="RivalrySort.Title"/>, so the order matches what rows show
    /// when the service omits a title the catalogue supplies; defaults to the comparison title, then song ID.</param>
    /// <returns>Ordered copy.</returns>
    public static List<T> Sort<T>(IEnumerable<T> items, Func<T, RivalSongComparison> comparison, RivalrySort sort, Func<T, string>? title = null) => sort switch
    {
        RivalrySort.Closest => [.. items.OrderBy(i => Math.Abs((long)comparison(i).RankDelta))],
        RivalrySort.YouLead => [.. items.OrderByDescending(i => comparison(i).RankDelta)],
        RivalrySort.TheyLead => [.. items.OrderBy(i => comparison(i).RankDelta)],
        RivalrySort.Title => [.. items.OrderBy(i => title?.Invoke(i) ?? comparison(i).Title ?? comparison(i).SongId, StringComparer.CurrentCultureIgnoreCase)],
        _ => [.. items],
    };

    /// <summary>Web <c>rivals.detail.summary</c>: "{total} shared songs · {ahead} ahead / {behind} behind".</summary>
    /// <param name="songs">Compared songs.</param>
    /// <returns>Summary text.</returns>
    public static string Summary(IReadOnlyList<RivalSongComparison> songs) =>
        string.Create(CultureInfo.CurrentCulture,
            $"{songs.Count:N0} shared songs · {songs.Count(s => s.RankDelta > 0):N0} ahead / {songs.Count(s => s.RankDelta < 0):N0} behind");

    /// <summary>Web <c>formatRankDelta</c>: sign, then exact below 10K, <c>K</c> below 1M, then <c>M</c>.</summary>
    /// <param name="delta">Signed rank delta (positive: the player leads).</param>
    /// <returns>Text such as <c>+12</c>, <c>−15K</c> or <c>+1.5M</c>.</returns>
    public static string FormatRankDelta(long delta)
    {
        var abs = Math.Abs(delta);
        var sign = delta > 0 ? "+" : delta < 0 ? "−" : "";
        if (abs < 10_000) return sign + abs.ToString("N0", CultureInfo.CurrentCulture);
        if (abs >= 1_000_000)
        {
            var millions = abs / 1_000_000d;
            var text = millions >= 10
                ? millions.ToString("0", CultureInfo.InvariantCulture)
                : millions.ToString("0.#", CultureInfo.InvariantCulture);
            return sign + text + "M";
        }
        return sign + Math.Round(abs / 1_000d, MidpointRounding.AwayFromZero).ToString("0", CultureInfo.InvariantCulture) + "K";
    }

    /// <summary>Signed score difference (player minus rival; missing scores count as zero).</summary>
    /// <param name="song">Comparison.</param>
    /// <returns>Text such as <c>+200</c> or <c>−7,000</c>.</returns>
    public static string FormatScoreDiff(RivalSongComparison song)
    {
        var diff = (song.UserScore ?? 0) - (song.RivalScore ?? 0);
        return (diff >= 0 ? "+" : "−") + Math.Abs(diff).ToString("N0", CultureInfo.CurrentCulture);
    }
}
#endregion
