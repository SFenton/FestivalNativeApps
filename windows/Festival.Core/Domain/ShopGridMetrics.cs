namespace Festival.Core.Domain;

#region Item Shop grid
/// <summary>
/// Item Shop album-art grid geometry (web <c>ShopPage.tsx</c>): square tiles, 10 epx gaps, the web's 2–4 columns below
/// 1100 epx. From 1100 epx the grid keeps filling the window (issue #653, owner: "when stretched wide, item shop doesn't
/// continue expanding to fill space") by adding columns of at least <see cref="MinimumTileWidth"/> instead of the web's
/// 1040 epx cap, like the Apple adaptive grid.
/// </summary>
public static class ShopGridMetrics
{
    /// <summary>Gap between tiles.</summary>
    public const double Gap = 10;

    /// <summary>Narrowest tile once the grid adds columns past the web's fifth (the web's capped five-column tile).</summary>
    public const double MinimumTileWidth = 200;

    /// <summary>Width from which the grid adds columns of at least <see cref="MinimumTileWidth"/> (web: five columns).</summary>
    public const double WideWidth = 1100;

    /// <summary>Grid width for the available width: the whole width (no cap; issue #653).</summary>
    /// <param name="available">Available width in epx.</param>
    /// <returns>Grid width.</returns>
    public static double ContentWidth(double available) => Math.Max(0, available);

    /// <summary>
    /// Columns for a content width: the web's 2 below 600 epx, 3 from 600 and 4 from 860; from 1100 at least 5, adding a
    /// column whenever another <see cref="MinimumTileWidth"/> tile and gap fit.
    /// </summary>
    /// <param name="width">Grid width in epx.</param>
    /// <returns>Column count.</returns>
    public static int Columns(double width) => width >= WideWidth
        ? Math.Max(5, (int)Math.Floor((width + Gap) / (MinimumTileWidth + Gap)))
        : width >= 860 ? 4 : width >= 600 ? 3 : 2;

    /// <summary>Square tile edge: tiles share the whole available width across <see cref="Columns"/>.</summary>
    /// <param name="width">Available width in epx.</param>
    /// <returns>Tile edge (at least 1).</returns>
    public static double TileSize(double width)
    {
        var columns = Columns(width);
        return Math.Max(1, Math.Floor((ContentWidth(width) - Gap * (columns - 1)) / columns));
    }
}
#endregion
