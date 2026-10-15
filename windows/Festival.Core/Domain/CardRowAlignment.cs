namespace Festival.Core.Domain;

#region Card row alignment
/// <summary>A card header's own size: its whole height and the part above its title.</summary>
/// <param name="Lead">
/// Height above the title: a combo board's icon row, or space centring a short title in a taller header; 0 when the
/// title starts the header.
/// </param>
/// <param name="Height">The header's whole height.</param>
public readonly record struct CardHeaderSize(double Lead, double Height);

/// <summary>Space a header adds above and below its content to line up with its row.</summary>
/// <param name="Top">Space above the content, so the title starts on the row's title line.</param>
/// <param name="Bottom">Space below the content, so the card surface starts on the row's line.</param>
public readonly record struct CardHeaderInsets(double Top, double Bottom);

/// <summary>
/// Header alignment for cards placed side by side in a grid row (pattern <c>section-headers</c> R14, issue #657). Each
/// header's part above its title (a combo board's icon row, centring space) is padded to the row's tallest such part,
/// so the titles share a line; the rest (title band, subtitle, a title wrapped at large text) is padded below to the
/// row's tallest, so the card surfaces and their first rows share a line. A single column aligns nothing.
/// </summary>
public static class CardRowAlignment
{
    /// <summary>Insets each card header takes.</summary>
    /// <param name="headers">
    /// Each card's own header size in grid order, or <see langword="null"/> for a card without a header (it neither sets
    /// nor takes the row's lines).
    /// </param>
    /// <param name="columns">Cards per row (values below 2 align nothing).</param>
    /// <returns>Per card, the space above and below its header content; zero for cards without a header and in one
    /// column.</returns>
    public static CardHeaderInsets[] Insets(IReadOnlyList<CardHeaderSize?> headers, int columns)
    {
        var result = new CardHeaderInsets[headers.Count];
        if (columns < 2) return result;
        for (var start = 0; start < headers.Count; start += columns)
        {
            var end = Math.Min(start + columns, headers.Count);
            double lead = 0, rest = 0;
            for (var i = start; i < end; i++)
            {
                if (headers[i] is not { } h) continue;
                lead = Math.Max(lead, h.Lead);
                rest = Math.Max(rest, h.Height - h.Lead);
            }
            for (var i = start; i < end; i++)
                if (headers[i] is { } h)
                    result[i] = new CardHeaderInsets(Math.Max(0, lead - h.Lead), Math.Max(0, rest - (h.Height - h.Lead)));
        }
        return result;
    }
}
#endregion
