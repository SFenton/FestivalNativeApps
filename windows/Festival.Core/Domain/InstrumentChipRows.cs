namespace Festival.Core.Domain;

#region Instrument chip rows
/// <summary>
/// Balanced rows for a Songs row's instrument status chips on a narrow list (web <c>resolveInstrumentChipRows</c> and
/// <c>splitInstrumentRows</c> in <c>pages/songs/layoutMode.ts</c>): the fewest rows that fit every chip, evened out so
/// nine chips that need two rows read 5 + 4 rather than 7 + 2, earlier rows taking the extra chip. Each row is centred
/// by the panel. Pattern <c>instrument-chip-rows</c> R1–R4; unlike the web (at most three rows), rows keep growing at any
/// width so no chip is ever clipped (R6, agent decision #645).
/// </summary>
public static class InstrumentChipRows
{
    /// <summary>Chips per row, top to bottom.</summary>
    /// <param name="count">Chips.</param>
    /// <param name="available">Row width in epx; infinite keeps one row.</param>
    /// <param name="chip">Chip width in epx.</param>
    /// <param name="spacing">Gap between chips in epx.</param>
    /// <returns>Chip count of each row (empty for no chips).</returns>
    public static int[] Split(int count, double available, double chip, double spacing)
    {
        if (count <= 0) return [];
        var fit = double.IsPositiveInfinity(available) || double.IsNaN(available)
            ? count
            // The layout-rounding tolerance keeps arrange from breaking a row that measure kept whole (issue #516).
            : Math.Max(1, (int)Math.Floor((available + spacing + WrapLineLayout.Tolerance) / (chip + spacing)));
        fit = Math.Min(fit, count);
        var rows = (count + fit - 1) / fit;
        var sizes = new int[rows];
        for (var i = 0; i < rows; i++) sizes[i] = count / rows + (i < count % rows ? 1 : 0);
        return sizes;
    }

    /// <summary>Row index of each chip for <see cref="Split"/>'s rows.</summary>
    /// <param name="sizes">Chips per row.</param>
    /// <returns>Zero-based row per chip.</returns>
    public static int[] Lines(IReadOnlyList<int> sizes)
    {
        var lines = new int[sizes.Sum()];
        for (int row = 0, index = 0; row < sizes.Count; row++)
            for (var i = 0; i < sizes[row]; i++) lines[index++] = row;
        return lines;
    }
}
#endregion
