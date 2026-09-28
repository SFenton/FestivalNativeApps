namespace Festival.Core.Domain;

#region Rival suggestion data
/// <summary>Summary of one per-song rival (web <c>RivalInfo</c>, always <c>source: "song"</c>).</summary>
/// <param name="AccountId">Rival account.</param>
/// <param name="DisplayName">Rival name (<c>Unknown</c> when absent).</param>
/// <param name="Direction"><c>above</c> or <c>below</c>.</param>
/// <param name="SharedSongCount">Songs both players have scores on.</param>
/// <param name="AheadCount">Songs where the rival is ahead.</param>
/// <param name="BehindCount">Songs where the rival is behind.</param>
public sealed record RivalInfo(
    string AccountId, string DisplayName, string Direction, int SharedSongCount, int AheadCount, int BehindCount);

/// <summary>One per-song, per-chart comparison between the selected player and a rival (web <c>RivalSongMatch</c>).</summary>
/// <param name="Rival">Rival summary.</param>
/// <param name="SongId">Catalogue song.</param>
/// <param name="Instrument">Chart.</param>
/// <param name="UserRank">Player's rank.</param>
/// <param name="RivalRank">Rival's rank.</param>
/// <param name="RankDelta"><c>UserRank - RivalRank</c>; negative means the rival leads.</param>
/// <param name="UserScore">Player's score.</param>
/// <param name="RivalScore">Rival's score.</param>
public sealed record RivalSongMatch(
    RivalInfo Rival, string SongId, Instrument Instrument, int UserRank, int RivalRank, int RankDelta,
    long? UserScore, long? RivalScore);

/// <summary>
/// Indexed rival lookups feeding the <c>song_rival_*</c> families, ported from the web
/// <c>buildRivalDataIndexFromRivalsAll</c> via the Apple <c>RivalDataIndex</c>.
/// </summary>
/// <param name="SongRivals">Kept rivals: up to <c>limit</c> ahead, then up to <c>limit</c> behind.</param>
/// <param name="ByRival">Every match per rival account, merged across combos.</param>
/// <param name="ClosestRivalBySong">Closest match (smallest |delta|) per <see cref="ClosestKey"/>.</param>
public sealed record RivalDataIndex(
    IReadOnlyList<RivalInfo> SongRivals,
    IReadOnlyDictionary<string, IReadOnlyList<RivalSongMatch>> ByRival,
    IReadOnlyDictionary<string, RivalSongMatch> ClosestRivalBySong)
{
    /// <summary>An index with no rivals.</summary>
    public static RivalDataIndex Empty { get; } = new([], new Dictionary<string, IReadOnlyList<RivalSongMatch>>(), new Dictionary<string, RivalSongMatch>());

    /// <summary>Lookup key for one song/chart pairing (web <c>${songId}:${instrument}</c>).</summary>
    /// <param name="songId">Song ID.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns>Key such as <c>abc:Solo_Guitar</c>.</returns>
    public static string ClosestKey(string songId, Instrument instrument) => $"{songId}:{instrument.ServiceId()}";

    /// <summary>
    /// Builds an index from one <c>/rivals/all</c> read: dedupe rivals by account (first occurrence wins,
    /// scanning combos in response order), keep the top <paramref name="limit"/> per direction, then resolve
    /// every sampled song/chart match for the kept rivals.
    /// </summary>
    /// <param name="response">Rivals-all response.</param>
    /// <param name="combo">Restrict to one combo token, or <see langword="null"/> for every combo.</param>
    /// <param name="limit">Rivals kept per direction.</param>
    /// <returns>The index <see cref="SuggestionGenerator.SetRivalData"/> expects.</returns>
    public static RivalDataIndex Build(RivalsAllResponse response, string? combo = null, int limit = 5)
    {
        var combos = combo is null ? response.Combos : response.Combos.Where(c => c.Combo == combo).ToList();
        var aboveOrder = new List<string>();
        var belowOrder = new List<string>();
        var aboveInfo = new Dictionary<string, RivalInfo>(StringComparer.Ordinal);
        var belowInfo = new Dictionary<string, RivalInfo>(StringComparer.Ordinal);
        foreach (var entry in combos)
        {
            Collect(entry.Above, "above", aboveOrder, aboveInfo);
            Collect(entry.Below, "below", belowOrder, belowInfo);
        }

        var songRivals = aboveOrder.Take(limit).Select(id => aboveInfo[id])
            .Concat(belowOrder.Take(limit).Select(id => belowInfo[id])).ToList();
        var kept = songRivals.Select(r => r.AccountId).ToHashSet(StringComparer.Ordinal);
        var byRival = new Dictionary<string, List<RivalSongMatch>>(StringComparer.Ordinal);
        var closest = new Dictionary<string, RivalSongMatch>(StringComparer.Ordinal);

        foreach (var entry in combos)
        {
            foreach (var rival in entry.Above.Concat(entry.Below))
            {
                if (!kept.Contains(rival.AccountId)) continue;
                var info = aboveInfo.TryGetValue(rival.AccountId, out var a) ? a : belowInfo[rival.AccountId];
                if (!byRival.TryGetValue(rival.AccountId, out var matches)) byRival[rival.AccountId] = matches = [];
                foreach (var sample in rival.Samples ?? [])
                {
                    if (response.SongId(sample) is not { } songId || !InstrumentInfo.TryParse(sample.Instrument, out var instrument)) continue;
                    var match = new RivalSongMatch(info, songId, instrument, sample.UserRank, sample.RivalRank,
                        sample.UserRank - sample.RivalRank, sample.UserScore, sample.RivalScore);
                    matches.Add(match);
                    var key = ClosestKey(songId, instrument);
                    if (!closest.TryGetValue(key, out var existing) || Math.Abs(match.RankDelta) < Math.Abs(existing.RankDelta))
                        closest[key] = match;
                }
            }
        }

        return new RivalDataIndex(songRivals,
            byRival.ToDictionary(p => p.Key, p => (IReadOnlyList<RivalSongMatch>)p.Value, StringComparer.Ordinal),
            closest);

        static void Collect(IReadOnlyList<RivalsAllEntry> entries, string direction, List<string> order, Dictionary<string, RivalInfo> info)
        {
            foreach (var e in entries)
            {
                if (info.ContainsKey(e.AccountId)) continue;
                order.Add(e.AccountId);
                info[e.AccountId] = new RivalInfo(e.AccountId, e.DisplayName ?? "Unknown", direction, e.SharedSongCount, e.AheadCount, e.BehindCount);
            }
        }
    }
}
#endregion
