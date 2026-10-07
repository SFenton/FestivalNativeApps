using System.Globalization;

namespace Festival.Core.Domain;

#region Scope
/// <summary>Global search scope (web <c>SearchTarget</c> order; <see cref="All"/> is the web's no-chip state).</summary>
public enum SearchScope
{
    /// <summary>Every scope (Songs → Players → Bands).</summary>
    All,
    /// <summary>Songs from the loaded catalogue.</summary>
    Songs,
    /// <summary>Players from <c>GET /api/account/search</c>.</summary>
    Players,
    /// <summary>Bands from <c>GET /api/bands/search</c> (read-only since the #320 service fix).</summary>
    Bands,
}

/// <summary>Scope tokens for routes and automation IDs.</summary>
public static class SearchScopes
{
    /// <summary>Lowercase token (<c>all</c>, <c>songs</c>, <c>players</c>, <c>bands</c>).</summary>
    /// <param name="scope">Scope.</param>
    /// <returns>Token.</returns>
    public static string Token(this SearchScope scope) => scope.ToString().ToLowerInvariant();

    /// <summary>Parses a token; unknown or missing values mean <see cref="SearchScope.All"/>.</summary>
    /// <param name="token">Query value.</param>
    /// <returns>Scope.</returns>
    public static SearchScope Parse(string? token) =>
        Enum.TryParse<SearchScope>(token, ignoreCase: true, out var scope) && Enum.IsDefined(scope) &&
        !int.TryParse(token, NumberStyles.Integer, CultureInfo.InvariantCulture, out _)
            ? scope : SearchScope.All;
}
#endregion

#region Rows
/// <summary>One song result (catalogue row projection; art is decorative).</summary>
/// <param name="SongId">Song.</param>
/// <param name="Title">Title.</param>
/// <param name="Artist">Artist.</param>
/// <param name="Art">Album-art reference.</param>
public sealed record GlobalSongResult(string SongId, string Title, string Artist, string? Art)
{
    /// <summary>Destination: Song Detail.</summary>
    public AppRoute Route => new AppRoute.SongDetail(SongId);

    /// <summary>UIA name ("Title by Artist").</summary>
    public string AccessibleName => $"{Title} by {Artist}";
}

/// <summary>One player result.</summary>
/// <param name="AccountId">Account.</param>
/// <param name="DisplayName">Display name.</param>
/// <param name="IsSelected">Whether this is the selected player (opens Statistics).</param>
public sealed record GlobalPlayerResult(string AccountId, string DisplayName, bool IsSelected)
{
    /// <summary>Destination: the selected player → Statistics, anyone else → their profile (viewing, not selecting).</summary>
    public AppRoute Route => IsSelected ? new AppRoute.Statistics() : new AppRoute.Player(AccountId, DisplayName);

    /// <summary>Secondary line.</summary>
    public string Subtitle => IsSelected ? "Selected player · Statistics" : "Player";

    /// <summary>UIA name.</summary>
    public string AccessibleName => IsSelected ? $"{DisplayName}, selected player, opens Statistics" : DisplayName;
}

/// <summary>Kind of title-bar suggestion.</summary>
public enum GlobalSuggestionKind
{
    /// <summary>A song result.</summary>
    Song,
    /// <summary>A player result.</summary>
    Player,
    /// <summary>A band result.</summary>
    Band,
    /// <summary>"See all results" → the Search page.</summary>
    SeeAll,
}

/// <summary>One title-bar <c>AutoSuggestBox</c> item. <see cref="ToString"/> is the UIA name of its list item.</summary>
/// <param name="Kind">Kind.</param>
/// <param name="Title">Primary text.</param>
/// <param name="Subtitle">Secondary text.</param>
/// <param name="Art">Song art, if any.</param>
/// <param name="Route">Destination; for <see cref="GlobalSuggestionKind.SeeAll"/> the Search page.</param>
/// <param name="AccessibleName">Spoken name.</param>
public sealed record GlobalSuggestion(
    GlobalSuggestionKind Kind, string Title, string Subtitle, string? Art, AppRoute Route, string AccessibleName)
{
    /// <summary>Whether this row is a song (shows art).</summary>
    public bool IsSong => Kind == GlobalSuggestionKind.Song;

    /// <summary>Whether this row is a player (shows a person picture).</summary>
    public bool IsPlayer => Kind == GlobalSuggestionKind.Player;

    /// <summary>Whether this row is a band (shows a people icon).</summary>
    public bool IsBand => Kind == GlobalSuggestionKind.Band;

    /// <summary>Whether this row is the "See all results" command.</summary>
    public bool IsSeeAll => Kind == GlobalSuggestionKind.SeeAll;

    /// <summary>Whether a secondary line is shown.</summary>
    public bool HasSubtitle => Subtitle.Length > 0;

    /// <inheritdoc />
    public override string ToString() => AccessibleName;
}
#endregion

#region Results
/// <summary>Pure global-search rules: limits, song matching, suggestion ordering, routing and announcements.</summary>
public static class GlobalSearchResults
{
    /// <summary>Shortest searchable (trimmed) query.</summary>
    public const int MinQueryLength = 2;
    /// <summary>Longest query the account search accepts.</summary>
    public const int MaxQueryLength = 200;
    /// <summary>Songs shown on the Search page.</summary>
    public const int SongLimit = 20;
    /// <summary>Players requested and shown.</summary>
    public const int PlayerLimit = 10;
    /// <summary>Songs in the title-bar suggestion list.</summary>
    public const int SuggestedSongs = 5;
    /// <summary>Players in the title-bar suggestion list.</summary>
    public const int SuggestedPlayers = 5;
    /// <summary>Bands requested and shown (web <c>pageSize=10</c>).</summary>
    public const int BandLimit = 10;
    /// <summary>Bands in the title-bar suggestion list (fewer than songs/players: band titles are the longest rows
    /// and the popup keeps "See all results" in view; the Search page lists all ten).</summary>
    public const int SuggestedBands = 3;
    /// <summary>Shared automation ID of every band result card on the Search page.</summary>
    public const string BandResultId = "fst.global-search.result.band";

    /// <summary>Field placeholder naming every scope (web <c>search.placeholders.songsPlayersBands</c>).</summary>
    public const string Placeholder = "Search songs, players, or bands";
    /// <summary>Field accessible name.</summary>
    public const string FieldName = "Search songs, players and bands";
    /// <summary>Short-query hint of the players-only pickers (web <c>search.enterQuery</c>).</summary>
    public const string EnterQueryHint = "Enter at least two characters to search.";
    /// <summary>Search page short-query hint in All (issue #299: every scope names what it searches).</summary>
    public const string EnterQueryHintAll = "Enter at least two characters to search for songs, players, or bands.";
    /// <summary>Search page short-query hint in Songs.</summary>
    public const string EnterQueryHintSongs = "Enter at least two characters to search for songs.";
    /// <summary>Search page short-query hint in Players.</summary>
    public const string EnterQueryHintPlayers = "Enter at least two characters to search for players.";
    /// <summary>Search page short-query hint in Bands.</summary>
    public const string EnterQueryHintBands = "Enter at least two characters to search for bands.";
    /// <summary>Spoken announcement when every scope is empty.</summary>
    public const string NoResults = "No results found.";
    /// <summary>Players-only picker empty text (an empty envelope may be a server timeout, so Retry is offered).</summary>
    public const string NoPlayers = "No players found.";
    /// <summary>All-scope empty-state title (issue #99: centred title and subtitle, like the web <c>EmptyState</c>).</summary>
    public const string EmptyAllTitle = "No results found";
    /// <summary>All-scope empty-state subtitle.</summary>
    public const string EmptyAllSubtitle = "Check the spelling or try a different song, artist, player or band.";
    /// <summary>Songs-scope empty-state title.</summary>
    public const string EmptySongsTitle = "No songs found";
    /// <summary>Songs-scope empty-state subtitle.</summary>
    public const string EmptySongsSubtitle = "Check the spelling or try a different song or artist.";
    /// <summary>Players-scope empty-state title.</summary>
    public const string EmptyPlayersTitle = "No players found";
    /// <summary>Players-scope empty-state subtitle.</summary>
    public const string EmptyPlayersSubtitle = "Check the spelling or try a different player name.";
    /// <summary>Bands-scope empty-state title (issue #320).</summary>
    public const string EmptyBandsTitle = "No bands found";
    /// <summary>Bands-scope empty-state subtitle.</summary>
    public const string EmptyBandsSubtitle = "Check the spelling or try a different band member's name.";
    /// <summary>Players-only picker progress text.</summary>
    public const string Searching = "Searching…";
    /// <summary>Catalogue failure text in the Songs section.</summary>
    public const string SongsFailed = "Search failed. Try again.";

    /// <summary>Search page short-query hint for a scope (issue #299).</summary>
    /// <param name="scope">Selected scope.</param>
    /// <returns>The hint ending in what that scope searches.</returns>
    public static string EnterQueryHintFor(SearchScope scope) => scope switch
    {
        SearchScope.Songs => EnterQueryHintSongs,
        SearchScope.Players => EnterQueryHintPlayers,
        SearchScope.Bands => EnterQueryHintBands,
        _ => EnterQueryHintAll,
    };

    /// <summary>Trimmed query.</summary>
    /// <param name="query">User text.</param>
    /// <returns>Trimmed text.</returns>
    public static string Normalize(string? query) => (query ?? "").Trim();

    /// <summary>
    /// Earlier player matches that still contain the new text, kept while the new account search runs so the
    /// suggestion list doesn't collapse and regrow on every keystroke (operator batch 6.21). Never adds a name that
    /// doesn't match what is typed.
    /// </summary>
    /// <param name="players">Previous matches.</param>
    /// <param name="query">New user text.</param>
    /// <returns>Matches that still apply.</returns>
    public static List<GlobalPlayerResult> RetainMatching(IEnumerable<GlobalPlayerResult> players, string? query)
    {
        var text = Normalize(query);
        return text.Length < MinQueryLength ? [] : [.. players.Where(p => p.DisplayName.Contains(text, StringComparison.OrdinalIgnoreCase))];
    }

    /// <summary>
    /// Whether an earlier band match still fits the new text, so it stays while the next band search runs (the same
    /// rule as <see cref="RetainMatching"/>: the band search matches member names).
    /// </summary>
    /// <param name="band">Previous match.</param>
    /// <param name="query">New user text.</param>
    /// <returns><see langword="true"/> when a member name contains the trimmed text (two or more characters).</returns>
    public static bool BandStillMatches(PlayerBandEntry band, string? query)
    {
        var text = Normalize(query);
        return text.Length >= MinQueryLength &&
               band.Members.Any(m => m.ResolvedName.Contains(text, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Whether the trimmed query is long enough to search.</summary>
    /// <param name="query">User text.</param>
    /// <returns><see langword="true"/> at two or more characters.</returns>
    public static bool IsSearchable(string? query) => Normalize(query).Length >= MinQueryLength;

    /// <summary>Whether the account search can be asked (2–200 characters, no control or bidi characters).</summary>
    /// <param name="query">User text.</param>
    /// <returns><see langword="true"/> when the request is valid.</returns>
    public static bool CanSearchPlayers(string? query)
    {
        var text = Normalize(query);
        return text.Length is >= MinQueryLength and <= MaxQueryLength && !ProfileText.ContainsUnsafeCharacter(text);
    }

    /// <summary>Local catalogue match in catalogue order (web <c>songMatchesSearch</c>).</summary>
    /// <param name="songs">Catalogue.</param>
    /// <param name="query">User text.</param>
    /// <param name="limit">Maximum rows.</param>
    /// <returns>Matches; empty for a short query.</returns>
    public static List<GlobalSongResult> MatchSongs(IEnumerable<Song> songs, string? query, int limit = SongLimit)
    {
        var text = Normalize(query);
        if (text.Length < MinQueryLength) return [];
        return [.. songs.Where(s => SongSearch.Matches(s, text)).Take(limit)
            .Select(s => new GlobalSongResult(s.SongId, s.Title, s.Artist, s.AlbumArt))];
    }

    /// <summary>Projects account-search rows, marking the selected player.</summary>
    /// <param name="results">Validated rows.</param>
    /// <param name="selectedAccountId">Selected player, if any.</param>
    /// <returns>At most <see cref="PlayerLimit"/> rows.</returns>
    public static List<GlobalPlayerResult> Players(IEnumerable<PlayerSearchResult> results, string? selectedAccountId) =>
        [.. results.Take(PlayerLimit).Select(r => new GlobalPlayerResult(r.AccountId, r.DisplayName,
            string.Equals(r.AccountId, selectedAccountId, StringComparison.OrdinalIgnoreCase)))];

    /// <summary>
    /// Title-bar suggestions: up to five songs, then up to five players, then up to three bands (each group appended
    /// after the previous one so the highlighted index of an earlier row never moves when a later read returns), then
    /// "See all results".
    /// </summary>
    /// <param name="query">User text.</param>
    /// <param name="songs">Song matches.</param>
    /// <param name="players">Player matches (empty while pending).</param>
    /// <param name="bands">Band matches (empty while pending or for the players-only pickers).</param>
    /// <returns>Suggestions; empty for a short query.</returns>
    public static List<GlobalSuggestion> Suggestions(string? query, IReadOnlyList<GlobalSongResult> songs,
        IReadOnlyList<GlobalPlayerResult> players, IReadOnlyList<PlayerBandEntry>? bands = null)
    {
        var text = Normalize(query);
        if (text.Length < MinQueryLength) return [];
        var list = new List<GlobalSuggestion>(SuggestedSongs + SuggestedPlayers + SuggestedBands + 1);
        foreach (var song in songs.Take(SuggestedSongs))
            list.Add(new(GlobalSuggestionKind.Song, song.Title, "Song · " + song.Artist, song.Art, song.Route,
                $"Song, {song.Title} by {song.Artist}"));
        foreach (var player in players.Take(SuggestedPlayers))
            list.Add(new(GlobalSuggestionKind.Player, player.DisplayName, player.Subtitle, null, player.Route,
                player.IsSelected ? $"Player, {player.DisplayName}, selected, opens Statistics" : $"Player, {player.DisplayName}"));
        foreach (var band in (bands ?? []).Take(SuggestedBands))
        {
            var size = BandTypeInfo.TryParse(band.BandType, out var type) ? type.Label() : "Band";
            list.Add(new(GlobalSuggestionKind.Band, band.MembersLabel, "Band · " + size, null, BandRoute(band),
                $"Band, {band.MembersLabel}, {size}"));
        }
        var seeAll = $"See All Results for “{text}”";
        list.Add(new(GlobalSuggestionKind.SeeAll, seeAll, "", null, new AppRoute.Search(text), seeAll));
        return list;
    }

    /// <summary>
    /// Band result destination: its band page with the type and team key the row carried (the safe lookup). The web
    /// opens Statistics for the selected band; Windows has no selected band yet, so a band always opens its page.
    /// </summary>
    /// <param name="band">Validated band-search row.</param>
    /// <returns>Band route.</returns>
    public static AppRoute BandRoute(PlayerBandEntry band) => new AppRoute.Band(band.Key, band.BandType, band.TeamKey);

    /// <summary>Polite result-count announcement ("3 songs, 10 players, 2 bands").</summary>
    /// <param name="songs">Song count, or <see langword="null"/> when the catalogue failed.</param>
    /// <param name="players">Player count, or <see langword="null"/> when the account search failed.</param>
    /// <param name="bands">Band count, or <see langword="null"/> when the band search failed.</param>
    /// <returns>Announcement text.</returns>
    public static string Announcement(int? songs, int? players, int? bands)
    {
        if (songs == 0 && players == 0 && bands == 0) return NoResults;
        var songText = songs is { } s ? Count(s, "song", "songs") : "song search failed";
        var playerText = players is { } p ? Count(p, "player", "players") : "player search failed";
        var bandText = bands is { } b ? Count(b, "band", "bands") : "band search failed";
        return $"{songText}, {playerText}, {bandText}";
    }

    /// <summary>
    /// Polite announcement for the players-only pickers (profile flyout, Rivals), which never search songs:
    /// "3 players", "No players found." or the failure text the picker shows.
    /// </summary>
    /// <param name="players">Player count, or <see langword="null"/> when the account search failed.</param>
    /// <param name="failure">Visible failure text, spoken when <paramref name="players"/> is <see langword="null"/>.</param>
    /// <returns>Announcement text.</returns>
    public static string PlayersAnnouncement(int? players, string failure) => players switch
    {
        null => failure.Length > 0 ? failure : "Player search failed.",
        0 => NoPlayers,
        { } p => Count(p, "player", "players"),
    };

    /// <summary>Formats a count with its noun.</summary>
    /// <param name="count">Count.</param>
    /// <param name="one">Singular noun.</param>
    /// <param name="many">Plural noun.</param>
    /// <returns>"1 song" / "3 songs".</returns>
    private static string Count(int count, string one, string many) =>
        count.ToString(CultureInfo.InvariantCulture) + " " + (count == 1 ? one : many);
}
#endregion
