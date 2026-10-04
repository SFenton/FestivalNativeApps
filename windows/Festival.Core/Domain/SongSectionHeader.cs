namespace Festival.Core.Domain;

#region Songs pinned section header
/// <summary>
/// Picks the label for the Songs list's pinned section header (issue #48, cross-platform check of #9): the section
/// holding the first row that is actually visible below the list's top edge. The list panel's first-visible index can
/// still describe the pre-jump layout when a jump-index pick finishes, so the page reads the realized rows' geometry
/// instead and maps the first visible row to its section.
/// </summary>
public static class SongSectionHeader
{
    /// <summary>A realized row container.</summary>
    /// <param name="Index">Flat row index.</param>
    /// <param name="Top">Top edge relative to the viewport top.</param>
    /// <param name="Bottom">Bottom edge relative to the viewport top.</param>
    public readonly record struct RealizedRow(int Index, double Top, double Bottom);

    /// <summary>A row whose bottom edge is within this many pixels of the top edge counts as scrolled away.</summary>
    public const double Tolerance = 1;

    /// <summary>Returns the index of the section that holds <paramref name="row"/>.</summary>
    /// <param name="sectionStarts">Ascending first-row index of each section.</param>
    /// <param name="row">Flat row index.</param>
    /// <returns>Section index, or -1 when there are no sections.</returns>
    public static int SectionAt(IReadOnlyList<int> sectionStarts, int row)
    {
        if (sectionStarts.Count == 0) return -1;
        int low = 0, high = sectionStarts.Count - 1;
        while (low < high)
        {
            var mid = (low + high + 1) / 2;
            if (sectionStarts[mid] <= row) low = mid;
            else high = mid - 1;
        }
        return low;
    }

    /// <summary>
    /// Finds the first row actually visible in the list viewport from the realized rows' geometry, so a first-visible
    /// index that still describes the layout before a jump cannot win. Rows whose bottom edge is within
    /// <see cref="Tolerance"/> of the top edge, or that start below the viewport, do not count.
    /// </summary>
    /// <param name="fallback">The panel's first-visible index, used when no realized row is in view.</param>
    /// <param name="count">Row count.</param>
    /// <param name="realized">Realized rows with edges relative to the viewport top.</param>
    /// <param name="viewportHeight">Viewport height.</param>
    /// <returns>Index of the first visible row, clamped to the rows.</returns>
    public static int FirstVisibleRow(int fallback, int count, IEnumerable<RealizedRow> realized, double viewportHeight)
    {
        if (count <= 0) return 0;
        var first = -1;
        foreach (var row in realized)
            if (row.Index >= 0 && row.Index < count && row.Bottom > Tolerance && row.Top < viewportHeight
                && (first < 0 || row.Index < first))
                first = row.Index;
        return first >= 0 ? first : Math.Clamp(fallback, 0, count - 1);
    }

    /// <summary>Maps a first-visible row to its section label.</summary>
    /// <param name="sectionStarts">Ascending first-row index of each section.</param>
    /// <param name="labels">Section labels, parallel to <paramref name="sectionStarts"/>.</param>
    /// <param name="fallback">The panel's first-visible index, used when no realized row is in view.</param>
    /// <param name="count">Row count.</param>
    /// <param name="realized">Realized rows with edges relative to the viewport top.</param>
    /// <param name="viewportHeight">Viewport height.</param>
    /// <returns>The label, or an empty string without sections.</returns>
    public static string Label(IReadOnlyList<int> sectionStarts, IReadOnlyList<string> labels, int fallback, int count,
        IEnumerable<RealizedRow> realized, double viewportHeight)
    {
        var section = SectionAt(sectionStarts, FirstVisibleRow(fallback, count, realized, viewportHeight));
        return section >= 0 && section < labels.Count ? labels[section] : "";
    }

    #region Push (issue #288)

    /// <summary>
    /// Which titles the pinned bar draws while scrolling across a section boundary (issue #288).
    /// </summary>
    /// <param name="Current">Section the bar names, or -1 for none.</param>
    /// <param name="Incoming">Section whose in-list title the bar redraws on its way up, or -1 while none is in the push band.</param>
    /// <param name="IncomingTop">The incoming title's text top relative to the list viewport's top (0 without one).</param>
    public readonly record struct PushState(int Current, int Incoming, double IncomingTop)
    {
        /// <summary>No push: the bar names <paramref name="section"/> at rest.</summary>
        /// <param name="section">Current section, or -1.</param>
        /// <returns>The state.</returns>
        public static PushState Resting(int section) => new(section, -1, 0);
    }

    /// <summary>
    /// Lays out the pinned bar like a plain list's pinned headers: the next section's in-list title rides up to the bar
    /// and pushes the current title out 1:1, so neither ever jumps. The bar sits above the list viewport, so a title
    /// reaches its pinned place once its text top is <paramref name="barHeight"/> above the viewport top; until then
    /// the previous section stays current and is pushed by it. Inside <paramref name="band"/> (the edge fade's depth)
    /// the bar draws the incoming title itself at the title's own place, so the row fade never dims it.
    /// </summary>
    /// <param name="rowSection">Section of the first visible row (<see cref="SectionAt"/>), or -1.</param>
    /// <param name="sectionCount">Number of sections.</param>
    /// <param name="rowSectionTitleTop">Text top of <paramref name="rowSection"/>'s in-list title relative to the
    /// viewport top, or <see langword="null"/> when it is not realized or has none (the first section).</param>
    /// <param name="nextTitleTop">The same for the following section's title.</param>
    /// <param name="barHeight">The pinned bar's height (title plus its bottom spacing).</param>
    /// <param name="band">Depth below the viewport top inside which the bar draws the incoming title.</param>
    /// <returns>The bar's state.</returns>
    public static PushState Push(int rowSection, int sectionCount, double? rowSectionTitleTop, double? nextTitleTop,
        double barHeight, double band)
    {
        if (rowSection < 0 || rowSection >= sectionCount) return PushState.Resting(-1);
        if (barHeight <= 0 || double.IsNaN(barHeight)) return PushState.Resting(rowSection);
        // The first visible row's own title has not pinned yet: the previous section is still current.
        if (rowSection > 0 && rowSectionTitleTop is { } own && !double.IsNaN(own) && own > -barHeight)
            return own <= band ? new(rowSection - 1, rowSection, own) : PushState.Resting(rowSection - 1);
        if (rowSection + 1 < sectionCount && nextTitleTop is { } next && !double.IsNaN(next) && next > -barHeight && next <= band)
            return new(rowSection, rowSection + 1, next);
        return PushState.Resting(rowSection);
    }

    /// <summary>How far the current title is pushed up: 0 until the incoming title meets the bar, then 1:1 up to one bar height.</summary>
    /// <param name="incomingTop">Incoming title's text top relative to the viewport top.</param>
    /// <param name="barHeight">The bar's height.</param>
    /// <returns>Vertical offset (≤ 0).</returns>
    public static double PushedOffset(double incomingTop, double barHeight) => Math.Clamp(incomingTop, -Math.Max(0, barHeight), 0);

    /// <summary>Where the bar draws the incoming title, relative to the bar's top: its own place, pinned at the top.</summary>
    /// <param name="incomingTop">Incoming title's text top relative to the viewport top.</param>
    /// <param name="viewportTop">The viewport's top relative to the bar's top.</param>
    /// <returns>Vertical position (≥ 0).</returns>
    public static double IncomingBarTop(double incomingTop, double viewportTop) => Math.Max(0, viewportTop + incomingTop);

    /// <summary>
    /// After a jump-index pick the list rests with the picked section's title at the viewport top; scrolling by the
    /// title's bottom pins it in the bar instead, with the section's first row under it (as a plain list pins a
    /// jumped-to header).
    /// </summary>
    /// <param name="titleBottom">The picked title's container bottom relative to the viewport top.</param>
    /// <param name="viewportHeight">Viewport height.</param>
    /// <returns>Extra scroll in epx, or 0 when the title is already pinned or out of view.</returns>
    public static double JumpPinDelta(double titleBottom, double viewportHeight) =>
        titleBottom > Tolerance && titleBottom < viewportHeight ? titleBottom : 0;

    #endregion
}
#endregion
