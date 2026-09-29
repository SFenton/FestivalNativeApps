using System.Globalization;

namespace Festival.Core.Domain;

#region Scope
/// <summary>Global search scope (web <c>SearchTarget</c> order; <see cref="All"/> is the web's no-chip state).</summary>
public enum SearchScope
{
    /// <summary>Every live scope (Songs → Players).</summary>
    All,
    /// <summary>Songs from the loaded catalogue.</summary>
    Songs,
    /// <summary>Players from <c>GET /api/account/search</c>.</summary>
    Players,
    /// <summary>Bands: shown but blocked (the service's band search GET can write).</summary>
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

    /// <summary>Field placeholder (only live scopes are named; web <c>search.placeholders.songsPlayers</c>).</summary>
    public const string Placeholder = "Search songs or players";
    /// <summary>Field accessible name.</summary>
    public const string FieldName = "Search songs and players";
    /// <summary>Short-query hint (web <c>search.enterQuery</c>).</summary>
    public const string EnterQueryHint = "Enter at least two characters to search.";
    /// <summary>All-scope empty text.</summary>
    public const string NoResults = "No results found.";
    /// <summary>Songs empty text.</summary>
    public const string NoSongs = "No songs found.";
    /// <summary>Players empty text (an empty envelope may be a server timeout, so Retry is offered).</summary>
    public const string NoPlayers = "No players found.";
    /// <summary>Players-only picker progress text.</summary>
    public const string Searching = "Searching…";
    /// <summary>Catalogue failure text in the Songs section.</summary>
    public const string SongsFailed = "Search failed. Try again.";

    /// <summary>Bands explanation (global-search spec, "Band scope (blocked)").</summary>
    public const string BandsUnavailable =
        "Band search isn't available in the app yet. The service's band search can change stored band data, so the app " +
        "won't call it until a read-only version exists. Browse bands in Leaderboards → Band Rankings, or from a player's Bands.";

    /// <summary>Band Rankings destination offered by the Bands explanation.</summary>
    public static AppRoute BandRankingsRoute { get; } = new AppRoute.BandRankings("Band_Duets");

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
    /// Title-bar suggestions: up to five songs, then up to five players (appended after the songs so the highlighted
    /// index of a song never moves when players arrive), then "See all results".
    /// </summary>
    /// <param name="query">User text.</param>
    /// <param name="songs">Song matches.</param>
    /// <param name="players">Player matches (empty while pending).</param>
    /// <returns>Suggestions; empty for a short query.</returns>
    public static List<GlobalSuggestion> Suggestions(string? query, IReadOnlyList<GlobalSongResult> songs, IReadOnlyList<GlobalPlayerResult> players)
    {
        var text = Normalize(query);
        if (text.Length < MinQueryLength) return [];
        var list = new List<GlobalSuggestion>(SuggestedSongs + SuggestedPlayers + 1);
        foreach (var song in songs.Take(SuggestedSongs))
            list.Add(new(GlobalSuggestionKind.Song, song.Title, "Song · " + song.Artist, song.Art, song.Route,
                $"Song, {song.Title} by {song.Artist}"));
        foreach (var player in players.Take(SuggestedPlayers))
            list.Add(new(GlobalSuggestionKind.Player, player.DisplayName, player.Subtitle, null, player.Route,
                player.IsSelected ? $"Player, {player.DisplayName}, selected, opens Statistics" : $"Player, {player.DisplayName}"));
        var seeAll = $"See All Results for “{text}”";
        list.Add(new(GlobalSuggestionKind.SeeAll, seeAll, "", null, new AppRoute.Search(text), seeAll));
        return list;
    }

    /// <summary>Polite result-count announcement ("3 songs, 10 players").</summary>
    /// <param name="songs">Song count, or <see langword="null"/> when the catalogue failed.</param>
    /// <param name="players">Player count, or <see langword="null"/> when the account search failed.</param>
    /// <returns>Announcement text.</returns>
    public static string Announcement(int? songs, int? players)
    {
        if (songs == 0 && players == 0) return NoResults;
        var songText = songs is { } s ? Count(s, "song", "songs") : "song search failed";
        var playerText = players is { } p ? Count(p, "player", "players") : "player search failed";
        return $"{songText}, {playerText}";
    }

    /// <summary>Formats a count with its noun.</summary>
    /// <param name="count">Count.</param>
    /// <param name="one">Singular noun.</param>
    /// <param name="many">Plural noun.</param>
    /// <returns>"1 song" / "3 songs".</returns>
    private static string Count(int count, string one, string many) =>
        count.ToString(CultureInfo.InvariantCulture) + " " + (count == 1 ? one : many);
}
#endregion
