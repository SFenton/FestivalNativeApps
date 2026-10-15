namespace Festival.Core.Domain;

#region Stat tile insets
/// <summary>
/// Horizontal metrics of a player stat tile (pattern <c>stat-tile-grid</c>, web <c>StatBox</c>). A linked tile's value
/// and label are centred on the whole card, like Apple <c>chevronInset</c> and Android <c>STAT_TILE_INSET</c>: the
/// padding that clears the trailing chevron is applied to both sides (issue #651). The chevron glyph keeps its size at
/// every Windows text size, so the inset does too and larger text wraps inside it.
/// </summary>
public static class StatTileInsets
{
    /// <summary>Chevron glyph size (epx).</summary>
    public const double ChevronSize = 12;

    /// <summary>Gap from the card's trailing edge to the chevron (epx).</summary>
    public const double ChevronMargin = 10;

    /// <summary>Gap between the text block and the chevron (epx).</summary>
    public const double ChevronGap = 6;

    /// <summary>Side padding of a tile without a chevron (epx).</summary>
    public const double PlainInset = 12;

    /// <summary>Side padding of a tile with a chevron: its margin, glyph and gap (epx).</summary>
    public const double LinkedInset = ChevronMargin + ChevronSize + ChevronGap;

    /// <summary>
    /// Padding on each side of a tile's centred text: <see cref="LinkedInset"/> on both sides of a linked tile, so the
    /// text is centred on the card and never runs under the chevron; <see cref="PlainInset"/> otherwise.
    /// </summary>
    /// <param name="linked">Whether the tile shows a chevron.</param>
    /// <returns>Left and right padding (epx).</returns>
    public static double Horizontal(bool linked) => linked ? LinkedInset : PlainInset;
}
#endregion
