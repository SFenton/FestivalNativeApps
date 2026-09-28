using System.Globalization;

namespace Festival.Core.Domain;

#region Sections
/// <summary>Top-level navigation sections (Windows wide split set: Leaderboards and Rivals separate).</summary>
public enum AppSection
{
    /// <summary>Songs catalogue.</summary>
    Songs,
    /// <summary>Suggestions (player selected).</summary>
    Suggestions,
    /// <summary>Leaderboards.</summary>
    Leaderboards,
    /// <summary>Rivals (player selected).</summary>
    Rivals,
    /// <summary>Statistics (player selected).</summary>
    Statistics,
    /// <summary>Settings (footer).</summary>
    Settings,
}

/// <summary>Section visibility and labels (app-navigation spec).</summary>
public static class AppSections
{
    /// <summary>Sections shown for the current selection, in pane order (Settings last).</summary>
    /// <param name="hasPlayer">Whether a player is selected.</param>
    /// <returns>Visible sections.</returns>
    public static IReadOnlyList<AppSection> Visible(bool hasPlayer) => hasPlayer
        ? [AppSection.Songs, AppSection.Suggestions, AppSection.Leaderboards, AppSection.Rivals, AppSection.Statistics, AppSection.Settings]
        : [AppSection.Songs, AppSection.Leaderboards, AppSection.Settings];

    /// <summary>Whether a section requires a selected player.</summary>
    /// <param name="section">Section.</param>
    /// <returns><see langword="true"/> for Suggestions, Rivals and Statistics.</returns>
    public static bool RequiresPlayer(this AppSection section) =>
        section is AppSection.Suggestions or AppSection.Rivals or AppSection.Statistics;

    /// <summary>Pane label.</summary>
    /// <param name="section">Section.</param>
    /// <returns>Title Case label.</returns>
    public static string Label(this AppSection section) => section.ToString();

    /// <summary>Stable automation ID (<c>fst.nav.*</c>).</summary>
    /// <param name="section">Section.</param>
    /// <returns>Automation ID.</returns>
    public static string AutomationId(this AppSection section) => "fst.nav." + section.ToString().ToLowerInvariant();

    /// <summary>Parses a debug tab name (case-insensitive).</summary>
    /// <param name="value">Name such as <c>songs</c>.</param>
    /// <param name="section">Parsed section.</param>
    /// <returns><see langword="true"/> when recognized.</returns>
    public static bool TryParse(string? value, out AppSection section) =>
        Enum.TryParse(value, ignoreCase: true, out section) && Enum.IsDefined(section);
}
#endregion

#region Routes
/// <summary>
/// Every pushable destination, mirroring the web <c>Routes</c> table and Apple's <c>AppRoute</c>
/// (the deprecated Manual route is omitted). Routes carry IDs, not objects, so a publication change
/// can re-resolve them against the new catalogue.
/// </summary>
public abstract record AppRoute
{
    /// <summary>Section whose stack owns this route when it is opened from a deep link.</summary>
    public abstract AppSection Section { get; }

    /// <summary>Web path for this route (for deep links and diagnostics).</summary>
    /// <returns>Path such as <c>/songs/abc</c>.</returns>
    public abstract string ToPath();

    /// <summary><c>/songs/:songId[?instrument=]</c>.</summary>
    /// <param name="SongId">Song.</param>
    /// <param name="Instrument">Initial chart.</param>
    public sealed record SongDetail(string SongId, Instrument? Instrument = null) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Songs;
        /// <inheritdoc />
        public override string ToPath() => $"/songs/{Esc(SongId)}" + (Instrument is { } i ? $"?instrument={i.ServiceId()}" : "");
    }

    /// <summary><c>/songs/:songId/:instrument[?page=]</c>.</summary>
    /// <param name="SongId">Song.</param>
    /// <param name="Instrument">Chart.</param>
    /// <param name="Page">One-based page.</param>
    public sealed record SongLeaderboard(string SongId, Instrument Instrument, int Page = 1) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Songs;
        /// <inheritdoc />
        public override string ToPath() =>
            $"/songs/{Esc(SongId)}/{Instrument.ServiceId()}" + (Page > 1 ? $"?page={Page.ToString(CultureInfo.InvariantCulture)}" : "");
    }

    /// <summary><c>/songs/:songId/bands/:bandType</c>.</summary>
    /// <param name="SongId">Song.</param>
    /// <param name="BandType">Band type.</param>
    public sealed record SongBandLeaderboard(string SongId, string BandType) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Songs;
        /// <inheritdoc />
        public override string ToPath() => $"/songs/{Esc(SongId)}/bands/{Esc(BandType)}";
    }

    /// <summary><c>/songs/:songId/:instrument/history</c>.</summary>
    /// <param name="SongId">Song.</param>
    /// <param name="Instrument">Chart.</param>
    public sealed record PlayerHistory(string SongId, Instrument Instrument) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Songs;
        /// <inheritdoc />
        public override string ToPath() => $"/songs/{Esc(SongId)}/{Instrument.ServiceId()}/history";
    }

    /// <summary><c>/player/:accountId</c>.</summary>
    /// <param name="AccountId">Account.</param>
    /// <param name="DisplayName">Name known from the originating row, shown until the read arrives (not part of the path).</param>
    public sealed record Player(string AccountId, string? DisplayName = null) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Leaderboards;
        /// <inheritdoc />
        public override string ToPath() => $"/player/{Esc(AccountId)}";
    }

    /// <summary><c>/bands/player/:accountId</c>.</summary>
    /// <param name="AccountId">Account.</param>
    public sealed record PlayerBands(string AccountId) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Leaderboards;
        /// <inheritdoc />
        public override string ToPath() => $"/bands/player/{Esc(AccountId)}";
    }

    /// <summary><c>/bands</c>.</summary>
    public sealed record Bands : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Leaderboards;
        /// <inheritdoc />
        public override string ToPath() => "/bands";
    }

    /// <summary><c>/bands/:bandId[?bandType=&amp;teamKey=]</c>; type and key let Band Detail use the safe rankings read.</summary>
    /// <param name="BandId">One-way band hash.</param>
    /// <param name="BandType">Optional band type from the originating row.</param>
    /// <param name="TeamKey">Optional team key from the originating row.</param>
    public sealed record Band(string BandId, string? BandType = null, string? TeamKey = null) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Leaderboards;
        /// <inheritdoc />
        public override string ToPath() => $"/bands/{Esc(BandId)}" + Query(("bandType", BandType), ("teamKey", TeamKey));
    }

    /// <summary><c>/leaderboards</c>.</summary>
    public sealed record Leaderboards : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Leaderboards;
        /// <inheritdoc />
        public override string ToPath() => "/leaderboards";
    }

    /// <summary><c>/leaderboards/all?instrument=&amp;rankBy=</c>.</summary>
    /// <param name="Instrument">Chart.</param>
    /// <param name="RankBy">Ranking metric.</param>
    public sealed record FullRankings(Instrument Instrument, string RankBy) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Leaderboards;
        /// <inheritdoc />
        public override string ToPath() => "/leaderboards/all" + Query(("instrument", Instrument.ServiceId()), ("rankBy", RankBy));
    }

    /// <summary><c>/leaderboards/bands/:bandType</c>.</summary>
    /// <param name="BandType">Band type.</param>
    public sealed record BandRankings(string BandType) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Leaderboards;
        /// <inheritdoc />
        public override string ToPath() => $"/leaderboards/bands/{Esc(BandType)}";
    }

    /// <summary><c>/rivals</c>.</summary>
    public sealed record Rivals : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Rivals;
        /// <inheritdoc />
        public override string ToPath() => "/rivals";
    }

    /// <summary><c>/rivals/all?category=&amp;mode=&amp;rankBy=</c>.</summary>
    /// <param name="Category">Optional category.</param>
    /// <param name="Mode">Optional mode.</param>
    /// <param name="RankBy">Optional metric.</param>
    public sealed record AllRivals(string? Category = null, string? Mode = null, string? RankBy = null) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Rivals;
        /// <inheritdoc />
        public override string ToPath() => "/rivals/all" + Query(("category", Category), ("mode", Mode), ("rankBy", RankBy));
    }

    /// <summary><c>/rivals/:rivalId</c>.</summary>
    /// <param name="RivalId">Rival account.</param>
    public sealed record RivalDetail(string RivalId) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Rivals;
        /// <inheritdoc />
        public override string ToPath() => $"/rivals/{Esc(RivalId)}";
    }

    /// <summary><c>/rivals/:rivalId/rivalry?mode=</c>.</summary>
    /// <param name="RivalId">Rival account.</param>
    /// <param name="Mode">Rivalry mode.</param>
    public sealed record Rivalry(string RivalId, string Mode) : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Rivals;
        /// <inheritdoc />
        public override string ToPath() => $"/rivals/{Esc(RivalId)}/rivalry" + Query(("mode", Mode));
    }

    /// <summary><c>/statistics</c>.</summary>
    public sealed record Statistics : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Statistics;
        /// <inheritdoc />
        public override string ToPath() => "/statistics";
    }

    /// <summary><c>/suggestions</c>.</summary>
    public sealed record Suggestions : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Suggestions;
        /// <inheritdoc />
        public override string ToPath() => "/suggestions";
    }

    /// <summary><c>/compete</c>.</summary>
    public sealed record Compete : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Rivals;
        /// <inheritdoc />
        public override string ToPath() => "/compete";
    }

    /// <summary><c>/shop</c>.</summary>
    public sealed record Shop : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Songs;
        /// <inheritdoc />
        public override string ToPath() => "/shop";
    }

    /// <summary><c>/settings/licenses</c>.</summary>
    public sealed record Licenses : AppRoute
    {
        /// <inheritdoc />
        public override AppSection Section => AppSection.Settings;
        /// <inheritdoc />
        public override string ToPath() => "/settings/licenses";
    }

    /// <summary>Escapes a path segment.</summary>
    /// <param name="value">Raw segment.</param>
    /// <returns>Escaped segment.</returns>
    private protected static string Esc(string value) => Uri.EscapeDataString(value);

    /// <summary>Builds a query string from the non-null pairs.</summary>
    /// <param name="pairs">Key/value pairs.</param>
    /// <returns><c>?a=b&amp;c=d</c> or empty.</returns>
    private protected static string Query(params (string Key, string? Value)[] pairs)
    {
        var present = pairs.Where(p => p.Value is not null).Select(p => $"{p.Key}={Uri.EscapeDataString(p.Value!)}").ToArray();
        return present.Length == 0 ? "" : "?" + string.Join('&', present);
    }
}
#endregion
