namespace Festival.Core.Domain;

#region Song leaderboard header text
/// <summary>
/// Screen-reader text of the shared song leaderboard header (pattern <c>song-leaderboard-header</c>; issue #317, #465).
/// The header is one button, and Narrator reads a named button as one item without its inner lines, so the button's
/// name carries every visible line: like the web's <c>SongInfoHeader</c> title area, a <c>role="link"</c> named by its
/// content (title, artist, board line).
/// </summary>
public static class SongLeaderboardHeaderText
{
    /// <summary>Separator between the header's lines in the accessible name (Narrator pauses at a comma).</summary>
    public const string Separator = ", ";

    /// <summary>
    /// The header button's accessible name: its visible lines in reading order, skipping empty ones. The song title
    /// leads, so the name starts with the visible label (WCAG 2.5.3, label in name).
    /// </summary>
    /// <param name="title">Song title (the level-1 heading).</param>
    /// <param name="artist">Artist line.</param>
    /// <param name="board">Board line: the instrument name or band size.</param>
    /// <param name="total">Entry-total line, empty while hidden (pattern R2, R5).</param>
    /// <returns>The name, e.g. <c>Fixture Pulse, Synthetic Quartet, Duos, 29 Duos entries</c>; empty without a song.</returns>
    public static string AccessibleName(string? title, string? artist, string? board, string? total)
    {
        if (string.IsNullOrWhiteSpace(title)) return "";
        return string.Join(Separator, new[] { title, artist, board, total }
            .Select(line => line?.Trim() ?? "")
            .Where(line => line.Length > 0));
    }
}
#endregion
