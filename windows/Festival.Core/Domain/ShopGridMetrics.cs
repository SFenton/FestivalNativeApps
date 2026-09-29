namespace Festival.Core.Domain;

#region Item Shop grid
/// <summary>Item Shop album-art grid geometry (web <c>ShopPage.tsx</c>): square tiles, 10 epx gaps.</summary>
public static class ShopGridMetrics
{
    /// <summary>Gap between tiles.</summary>
    public const double Gap = 10;

    /// <summary>Widest grid (web: <c>min(window, 1080) - 40</c>), so wide windows keep ~200 epx tiles instead of posters.</summary>
    public const double MaxContentWidth = 1040;

    /// <summary>Grid width for the available width, capped at <see cref="MaxContentWidth"/>.</summary>
    /// <param name="available">Available width in epx.</param>
    /// <returns>Grid width.</returns>
    public static double ContentWidth(double available) => Math.Min(Math.Max(0, available), MaxContentWidth);

    /// <summary>Columns for a content width: 5 from 1100 epx, 4 from 860, 3 from 600, else 2.</summary>
    /// <param name="width">Grid width in epx.</param>
    /// <returns>Column count.</returns>
    public static int Columns(double width) => width >= 1100 ? 5 : width >= 860 ? 4 : width >= 600 ? 3 : 2;

    /// <summary>Square tile edge: columns follow the available width (like the web's window width), tiles fill the capped grid.</summary>
    /// <param name="width">Available width in epx.</param>
    /// <returns>Tile edge (at least 1).</returns>
    public static double TileSize(double width)
    {
        var columns = Columns(width);
        return Math.Max(1, Math.Floor((ContentWidth(width) - Gap * (columns - 1)) / columns));
    }
}
#endregion
