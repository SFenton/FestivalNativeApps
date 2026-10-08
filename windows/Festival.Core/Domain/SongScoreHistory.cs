using System.Globalization;

namespace Festival.Core.Domain;

#region Points
/// <summary>
/// One bar of the Song Detail score-history chart (web <c>ChartPoint</c>, <c>hooks/chart/useChartData.ts</c>): the change's
/// achieved date, new score and accuracy as a 0–100 percent.
/// </summary>
/// <param name="Entry">Wire row.</param>
/// <param name="Date">Achieved (else recorded) time.</param>
public sealed record ScoreHistoryPoint(ScoreHistoryEntry Entry, DateTimeOffset Date)
{
    /// <summary>Accuracy wire scale: ten-thousandths of a percent (<c>ACCURACY_SCALE</c>).</summary>
    public const double AccuracyScale = 10_000;

    /// <summary>New score.</summary>
    public long Score => Entry.NewScore;

    /// <summary>Accuracy percent 0–100 (0 when missing, as the web).</summary>
    public double AccuracyPercent => Entry.Accuracy is { } a && double.IsFinite(a) ? Math.Clamp(a / AccuracyScale, 0, 100) : 0;

    /// <summary>Full combo flag.</summary>
    public bool IsFullCombo => Entry.IsFullCombo == true;

    /// <summary>Gold bar: a 100% full combo.</summary>
    public bool IsGold => AccuracyPercent >= 100 && IsFullCombo;

    /// <summary>Axis label <c>M/D/YY</c> in local time (web <c>dateLabel</c>).</summary>
    public string DateLabel
    {
        get
        {
            var local = Date.ToLocalTime();
            return string.Create(CultureInfo.InvariantCulture, $"{local.Month}/{local.Day}/{local.Year % 100:00}");
        }
    }

    /// <summary>List/detail label, e.g. <c>Mar 30, 2026</c> (web <c>toLocaleDateString('en-US', { month: 'short', … })</c>).</summary>
    public string LongDate => Date.ToLocalTime().ToString("MMM d, yyyy", CultureInfo.GetCultureInfo("en-US"));
}

/// <summary>Pure score-history rules for the Song Detail section.</summary>
public static class SongScoreHistory
{
    /// <summary>Rows in the list under the chart before "View All Scores" (web <c>slice(0, 5)</c>).</summary>
    public const int ListSize = 5;

    /// <summary>
    /// Drops rows above the chart's invalid-score threshold (<c>maxScore × (1 + leeway / 100)</c>) while filtering is on
    /// (web <c>useScoreFilter.filterHistory</c>); charts without a max score keep every row.
    /// </summary>
    /// <param name="entries">Rows.</param>
    /// <param name="song">Catalogue song (for <c>maxScores</c>).</param>
    /// <param name="filterInvalid">Settings' Filter Invalid Scores.</param>
    /// <param name="leeway">Settings' leeway percent.</param>
    /// <returns>Kept rows.</returns>
    public static List<ScoreHistoryEntry> FilterInvalid(IEnumerable<ScoreHistoryEntry> entries, Song? song, bool filterInvalid, double leeway)
    {
        if (!filterInvalid || song is null) return [.. entries];
        return [.. entries.Where(e => !InstrumentInfo.TryParse(e.Instrument, out var instrument) ||
                                      song.MaxScore(instrument) is not { } max || e.NewScore <= max * (1 + leeway / 100))];
    }

    /// <summary>Row counts per chart.</summary>
    /// <param name="entries">Rows.</param>
    /// <returns>Counts keyed by chart.</returns>
    public static Dictionary<Instrument, int> Counts(IEnumerable<ScoreHistoryEntry> entries)
    {
        var counts = new Dictionary<Instrument, int>();
        foreach (var entry in entries)
            if (InstrumentInfo.TryParse(entry.Instrument, out var instrument))
                counts[instrument] = counts.GetValueOrDefault(instrument) + 1;
        return counts;
    }

    /// <summary>
    /// Initial chart (web <c>ScoreHistoryChart</c> auto-select): the requested one when it has rows, else Lead when it has
    /// rows, else the first chart in <paramref name="pool"/> with rows.
    /// </summary>
    /// <param name="pool">Visible charted instruments in display order.</param>
    /// <param name="counts">Row counts.</param>
    /// <param name="requested">Route instrument, if any.</param>
    /// <returns>Chart, or <see langword="null"/> when no chart has rows.</returns>
    public static Instrument? DefaultInstrument(IReadOnlyList<Instrument> pool, IReadOnlyDictionary<Instrument, int> counts, Instrument? requested)
    {
        bool Has(Instrument i) => pool.Contains(i) && counts.GetValueOrDefault(i) > 0;
        if (requested is { } r && Has(r)) return r;
        if (Has(Instrument.Lead)) return Instrument.Lead;
        foreach (var instrument in pool)
            if (Has(instrument)) return instrument;
        return null;
    }

    /// <summary>One chart's points, oldest first (undated rows are dropped).</summary>
    /// <param name="entries">Rows.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns>Points.</returns>
    public static List<ScoreHistoryPoint> Points(IEnumerable<ScoreHistoryEntry> entries, Instrument instrument) =>
        [.. entries
            .Where(e => e.Instrument == instrument.ServiceId() && e.DisplayDate is not null)
            .Select(e => new ScoreHistoryPoint(e, e.DisplayDate!.Value))
            .OrderBy(p => p.Date)];

    /// <summary>List rows: highest score first (web <c>visibleCards</c>), ties oldest first.</summary>
    /// <param name="points">Points.</param>
    /// <param name="all">All rows ("View All Scores") instead of the top five.</param>
    /// <returns>Rows.</returns>
    public static List<ScoreHistoryPoint> TopScores(IEnumerable<ScoreHistoryPoint> points, bool all = false)
    {
        var sorted = points.OrderByDescending(p => p.Score).ThenBy(p => p.Date);
        return [.. all ? sorted : sorted.Take(ListSize)];
    }

    /// <summary>Web <c>accuracyColor</c>: red <c>rgb(220,40,40)</c> to green <c>rgb(46,204,113)</c>, clamped.</summary>
    /// <param name="percent">Accuracy percent.</param>
    /// <returns>RGB bytes.</returns>
    public static (byte R, byte G, byte B) AccuracyColor(double percent)
    {
        var p = double.IsFinite(percent) ? Math.Clamp(percent / 100, 0, 1) : 0;
        static byte Mix(int low, int high, double t) => (byte)Math.Round(low * (1 - t) + high * t, MidpointRounding.AwayFromZero);
        return (Mix(220, 46, p), Mix(40, 204, p), Mix(40, 113, p));
    }
}
#endregion

#region Chart scale
/// <summary>Chart sizing: bars that fit a width (web <c>useChartDimensions</c>) and the score axis.</summary>
public static class ScoreHistoryChartScale
{
    /// <summary>Web <c>MIN_BAR_WIDTH</c>.</summary>
    public const double MinBarWidth = 96;

    /// <summary>Web <c>BAR_GAP</c>.</summary>
    public const double BarGap = 8;

    /// <summary>How many bars fit a plot width (at least one; unlimited before layout).</summary>
    /// <param name="plotWidth">Width left for bars.</param>
    /// <returns>Bars per page.</returns>
    public static int MaxBars(double plotWidth) =>
        !double.IsFinite(plotWidth) || plotWidth <= 0 ? int.MaxValue : Math.Max(1, (int)Math.Floor((plotWidth + BarGap) / (MinBarWidth + BarGap)));

    /// <summary>Score axis top: four equal "nice" steps covering the page's highest score (Recharts <c>auto</c> domain).</summary>
    /// <param name="max">Highest score on the page.</param>
    /// <returns>Axis maximum (at least 4).</returns>
    public static long NiceMax(long max)
    {
        if (max <= 0) return 4;
        var raw = max / 4.0;
        var magnitude = Math.Pow(10, Math.Floor(Math.Log10(raw)));
        var step = new[] { 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10 }.Select(m => m * magnitude).First(s => s >= raw);
        return (long)Math.Max(4, Math.Round(step * 4));
    }

    /// <summary>Axis tick label (<c>12k</c> above 1,000, as the web's <c>tickFormatter</c>).</summary>
    /// <param name="value">Score.</param>
    /// <returns>Label.</returns>
    public static string Tick(double value) => value >= 1000
        ? (value / 1000).ToString("0", CultureInfo.InvariantCulture) + "k"
        : value.ToString("0", CultureInfo.InvariantCulture);

    /// <summary>Narrowest side gutter (the 100% text-scale layout).</summary>
    public const double MinAxisGutter = 64;

    /// <summary>Space between the window edge and a rotated axis title.</summary>
    public const double AxisTitleInset = 4;

    /// <summary>Space between a rotated axis title and its tick labels.</summary>
    public const double AxisTitleGap = 4;

    /// <summary>Space between tick labels and the axis line.</summary>
    public const double AxisTickGap = 8;

    /// <summary>
    /// Side gutter that fits a rotated axis title and its tick labels without overlap, so text scaling (Windows
    /// Accessibility › Text size up to 225%) grows the gutter instead of drawing the title over the ticks.
    /// </summary>
    /// <param name="tickWidth">Widest tick label's measured width.</param>
    /// <param name="titleHeight">Axis title's measured line height (its width once rotated).</param>
    /// <returns>Gutter width, at least <see cref="MinAxisGutter"/>.</returns>
    public static double AxisGutter(double tickWidth, double titleHeight)
    {
        var needed = AxisTitleInset + Math.Max(0, titleHeight) + AxisTitleGap + Math.Max(0, tickWidth) + AxisTickGap;
        return double.IsFinite(needed) ? Math.Max(MinAxisGutter, Math.Ceiling(needed)) : MinAxisGutter;
    }
}
#endregion

#region Pager
/// <summary>
/// Offset paging of chart bars with optional point selection (web <c>useChartPagination</c>): offset 0 shows the newest
/// bars; back moves to older bars; with a point selected the arrows step the selection and page to keep it visible.
/// </summary>
public sealed class ScoreHistoryPager
{
    private int offset;

    /// <summary>Points on the chart.</summary>
    public int Count { get; private set; }

    /// <summary>Bars per page.</summary>
    public int MaxBars { get; private set; } = int.MaxValue;

    /// <summary>Selected point index, or −1.</summary>
    public int SelectedIndex { get; private set; } = -1;

    /// <summary>Largest offset.</summary>
    public int MaxOffset => Math.Max(0, Count - MaxBars);

    /// <summary>Offset from the newest bar (clamped).</summary>
    public int Offset => Math.Min(offset, MaxOffset);

    /// <summary>First visible index (inclusive).</summary>
    public int PageStart => Math.Max(0, PageEnd - MaxBars);

    /// <summary>Last visible index (exclusive).</summary>
    public int PageEnd => Count - Offset;

    /// <summary>Whether paging buttons show.</summary>
    public bool NeedsPagination => Count > MaxBars;

    /// <summary>Whether the page-jump buttons show (more than one bar per page).</summary>
    public bool ShowPageJumps => MaxBars > 1;

    /// <summary>Whether back is unavailable.</summary>
    public bool BackDisabled => SelectedIndex >= 0 ? SelectedIndex <= 0 : Offset >= MaxOffset;

    /// <summary>Whether forward is unavailable.</summary>
    public bool ForwardDisabled => SelectedIndex >= 0 ? SelectedIndex >= Count - 1 : Offset <= 0;

    /// <summary>New data (another chart): newest page, no selection.</summary>
    /// <param name="count">Points.</param>
    public void Reset(int count)
    {
        Count = Math.Max(0, count);
        offset = 0;
        SelectedIndex = -1;
    }

    /// <summary>Resized plot.</summary>
    /// <param name="maxBars">Bars per page (≥ 1).</param>
    public void SetMaxBars(int maxBars) => MaxBars = Math.Max(1, maxBars);

    /// <summary>Selects a point, or clears it when it is already selected (bar click).</summary>
    /// <param name="index">Point index.</param>
    public void Toggle(int index)
    {
        if (index < 0 || index >= Count) return;
        SelectedIndex = SelectedIndex == index ? -1 : index;
    }

    /// <summary>Clears the selection.</summary>
    public void ClearSelection() => SelectedIndex = -1;

    /// <summary>« : a page back (older), or the selection a page back.</summary>
    public void BackPage() => Step(-MaxBars);

    /// <summary>‹ : one bar back, or the previous point.</summary>
    public void BackEntry() => Step(-1);

    /// <summary>› : one bar forward, or the next point.</summary>
    public void ForwardEntry() => Step(1);

    /// <summary>» : a page forward (newer), or the selection a page forward.</summary>
    public void ForwardPage() => Step(MaxBars);

    /// <summary>Moves the selection (keeping it visible) or the page.</summary>
    /// <param name="delta">Signed index change (negative = older).</param>
    private void Step(int delta)
    {
        if (Count == 0) return;
        if (SelectedIndex < 0)
        {
            offset = Math.Clamp(Offset - delta, 0, MaxOffset);
            return;
        }
        var target = Math.Clamp(SelectedIndex + delta, 0, Count - 1);
        SelectedIndex = target;
        if (target >= PageStart && target < PageEnd) return;
        offset = target < PageStart ? Math.Min(Count - target - MaxBars, MaxOffset) : Math.Max(Count - target - 1, 0);
    }
}
#endregion
