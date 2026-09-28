using System.Globalization;
using System.Text;

namespace Festival.Core.Domain;

#region Search
/// <summary>Web-equivalent title/artist matching: raw substring first, then accent- and separator-folded.</summary>
public static class SongSearch
{
    private const string Apostrophes = "'‘’`´";
    private const string Separators = "()[]{}\"“”.,:;!?_-–—/\\";

    /// <summary>Whether a song's title or artist contains the query on either scale.</summary>
    /// <param name="song">Catalogue row.</param>
    /// <param name="query">User text.</param>
    /// <returns><see langword="true"/> on a match or an empty query.</returns>
    public static bool Matches(Song song, string? query)
    {
        var raw = (query ?? "").Trim().ToLowerInvariant();
        if (raw.Length == 0 ||
            song.Title.Contains(raw, StringComparison.OrdinalIgnoreCase) ||
            song.Artist.Contains(raw, StringComparison.OrdinalIgnoreCase))
            return true;
        var folded = Normalize(raw);
        return folded.Length == 0 || Normalize(song.Title).Contains(folded, StringComparison.Ordinal) ||
               Normalize(song.Artist).Contains(folded, StringComparison.Ordinal);
    }

    /// <summary>Applies the PWA's NFKD, combining-mark, apostrophe and separator rules.</summary>
    /// <param name="value">Title, artist or query.</param>
    /// <returns>Lowercase text with single spaces between words.</returns>
    public static string Normalize(string value)
    {
        var decomposed = value.Normalize(NormalizationForm.FormKD).ToLowerInvariant();
        var output = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark || Apostrophes.Contains(c))
                continue;
            if (char.IsWhiteSpace(c) || Separators.Contains(c))
            {
                if (output.Length > 0 && output[^1] != ' ') output.Append(' ');
            }
            else
            {
                output.Append(c);
            }
        }
        return output.ToString().Trim();
    }
}
#endregion
