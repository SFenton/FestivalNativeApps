using System.Globalization;

namespace Festival.Core.Domain;

#region Score detail
/// <summary>
/// The selected player's validated score for one chart, reduced to the fields Songs rows use. Built from the
/// publication-matched score index; never inferred (a missing FC flag is not "no FC" evidence of anything).
/// </summary>
/// <param name="Score">Score (0 = no score).</param>
/// <param name="Accuracy">Expanded accuracy (ten-thousandths of a percent, 0–1,000,000).</param>
/// <param name="IsFullCombo">Explicit FC flag.</param>
/// <param name="Stars">Stars (6 = gold).</param>
/// <param name="Season">Season achieved.</param>
/// <param name="Difficulty">Game difficulty 0–3 (Easy–Expert).</param>
/// <param name="Rank">One-based chart rank.</param>
/// <param name="TotalEntries">Chart population.</param>
/// <param name="LastPlayedAt">ISO-8601 last-played timestamp (valid variant preferred).</param>
public sealed record SongScoreDetail(
    long Score, double? Accuracy = null, bool? IsFullCombo = null, int? Stars = null, int? Season = null,
    double? Difficulty = null, int? Rank = null, int? TotalEntries = null, string? LastPlayedAt = null)
{
    /// <summary>Facts used by filters and chips.</summary>
    public ChartScoreFacts Facts => new(Score, IsFullCombo);
}
#endregion

#region Status chips
/// <summary>One chart's Songs status (color is never the only cue: the row announcement carries the text).</summary>
public enum SongInstrumentStatus
{
    /// <summary>Uncharted (even if a score exists).</summary>
    Unavailable,
    /// <summary>Positive score with explicit FC (gold).</summary>
    FullCombo,
    /// <summary>Positive score without FC (green).</summary>
    Scored,
    /// <summary>No row or zero score (red).</summary>
    NoScore,
    /// <summary>Zero score with an explicit FC (amber, native safety deviation).</summary>
    InconsistentFullCombo,
}

/// <summary>One chip: chart plus status.</summary>
/// <param name="Instrument">Chart.</param>
/// <param name="Status">Status.</param>
public sealed record SongInstrumentBadge(Instrument Instrument, SongInstrumentStatus Status)
{
    /// <summary>Spoken status words.</summary>
    public string StatusText => Status switch
    {
        SongInstrumentStatus.Unavailable => "not charted",
        SongInstrumentStatus.FullCombo => "full combo",
        SongInstrumentStatus.Scored => "scored",
        SongInstrumentStatus.NoScore => "no score",
        _ => "score missing despite a reported full combo",
    };

    /// <summary>"Lead, full combo".</summary>
    public string Announcement => $"{Instrument.Label()}, {StatusText}";

    /// <summary>Test ID of this chip on a song's row (<c>fst.songs.instrument-status.&lt;songId&gt;.&lt;ServiceId&gt;</c>).</summary>
    /// <param name="songId">Row song.</param>
    /// <returns>Automation ID.</returns>
    public string AutomationId(string songId) => $"fst.songs.instrument-status.{songId}.{Instrument.ServiceId()}";

    /// <summary>
    /// Ring weight and chip opacity. Colours carry the status normally (1.5 epx ring; not charted is muted to 45%). Under a
    /// contrast theme system colours must not be dimmed, so the ring itself carries it: 3 epx for full combo, scored and
    /// inconsistent FC (told apart by Highlight fill, WindowText ring and Highlight ring), 2 epx GrayText for no score
    /// and no ring for not charted.
    /// </summary>
    /// <param name="contrast">A Windows contrast theme is on.</param>
    /// <returns>Ring thickness (epx) and opacity.</returns>
    public (double Ring, double Opacity) Ring(bool contrast) => contrast
        ? Status switch
        {
            SongInstrumentStatus.Unavailable => (0, 1),
            SongInstrumentStatus.NoScore => (2, 1),
            _ => (3, 1),
        }
        : (1.5, Status == SongInstrumentStatus.Unavailable ? 0.45 : 1);
}

/// <summary>When chips show and how each status is derived.</summary>
public static class SongInstrumentStatusPolicy
{
    /// <summary>
    /// Chips need an available, matching index, icons on and no single-chart filter. Under Filter Invalid Scores they show
    /// the resolved (valid fallback) scores, like the web.
    /// </summary>
    /// <param name="hasPlayer">A player is selected.</param>
    /// <param name="scoresAvailable">Publication-matched 200 scores are loaded.</param>
    /// <param name="iconsEnabled">Show Instrument Icons.</param>
    /// <param name="instrumentFilter">Single-chart filter, if any.</param>
    /// <returns><see langword="true"/> when chips replace metadata.</returns>
    public static bool ShowsChips(bool hasPlayer, bool scoresAvailable, bool iconsEnabled, Instrument? instrumentFilter) =>
        hasPlayer && scoresAvailable && iconsEnabled && instrumentFilter is null;

    /// <summary>One status per visible chart, in service order.</summary>
    /// <param name="song">Catalogue row.</param>
    /// <param name="visible">Settings-visible charts.</param>
    /// <param name="score">This song's score for a chart, if any.</param>
    /// <returns>At most nine badges.</returns>
    public static List<SongInstrumentBadge> Badges(Song song, IReadOnlyCollection<Instrument> visible, Func<Instrument, ChartScoreFacts?> score) =>
        [.. InstrumentInfo.All.Where(visible.Contains).Select(chart => new SongInstrumentBadge(chart, Status(song, chart, score(chart))))];

    /// <summary>Status for one chart.</summary>
    /// <param name="song">Row.</param>
    /// <param name="chart">Chart.</param>
    /// <param name="facts">Score facts, if a row exists.</param>
    /// <returns>Status.</returns>
    public static SongInstrumentStatus Status(Song song, Instrument chart, ChartScoreFacts? facts)
    {
        if (!song.Supports(chart)) return SongInstrumentStatus.Unavailable;
        if (facts is not { } f) return SongInstrumentStatus.NoScore;
        var fc = f.IsFullCombo == true;
        if (f.Score > 0) return fc ? SongInstrumentStatus.FullCombo : SongInstrumentStatus.Scored;
        return fc ? SongInstrumentStatus.InconsistentFullCombo : SongInstrumentStatus.NoScore;
    }
}
#endregion

#region Metadata
/// <summary>Percentile emphasis tier.</summary>
public enum SongPercentileTier
{
    /// <summary>Top 1% (gold fill).</summary>
    TopOne,
    /// <summary>Top 5% (gold outline).</summary>
    TopFive,
    /// <summary>Everything else (neutral).</summary>
    Ordinary,
}

/// <summary>One renderable metadata pill with its visible and spoken text.</summary>
/// <param name="Kind">Field.</param>
/// <param name="Text">Visible text.</param>
/// <param name="Announcement">Spoken text.</param>
public sealed record SongMetadataField(MetadataField Kind, string Text, string Announcement)
{
    /// <summary>Accuracy tint (non-FC accuracy only; the view applies 25% opacity).</summary>
    public (byte R, byte G, byte B)? Tint { get; init; }
    /// <summary>Accuracy pill is a full combo (gold outline and visible FC).</summary>
    public bool FullCombo { get; init; }
    /// <summary>Percentile tier.</summary>
    public SongPercentileTier Percentile { get; init; } = SongPercentileTier.Ordinary;
    /// <summary>Star count (1–5) and whether they are gold.</summary>
    public (int Count, bool Gold) Stars { get; init; }
    /// <summary>Season equals the current catalogue season (inverted pill).</summary>
    public bool CurrentSeason { get; init; }
    /// <summary>Raw chart intensity for the meter.</summary>
    public double? IntensityRaw { get; init; }
    /// <summary>Game difficulty 0–3.</summary>
    public int GameDifficulty { get; init; } = -1;
}

/// <summary>Builds the icons-off / single-chart selected-player metadata row.</summary>
public static class SongMetadataPolicy
{
    /// <summary>Web <c>DEFAULT_METADATA_ORDER</c> (used unless Settings enables a custom visual order): the
    /// <see cref="MetadataField"/> declaration order, also the default Song Row Visual Order.</summary>
    public static IReadOnlyList<MetadataField> DefaultOrder { get; } = SettingsOrder.Normalize<MetadataField>(null);

    /// <summary>Game difficulty names 0–3.</summary>
    public static IReadOnlyList<string> DifficultyNames { get; } = ["Easy", "Medium", "Hard", "Expert"];

    /// <summary>Single-letter game difficulty glyphs 0–3.</summary>
    public static IReadOnlyList<string> DifficultyLetters { get; } = ["E", "M", "H", "X"];

    private static readonly int[] PercentileBuckets = [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100];

    /// <summary>Visible fields for a positive score, in the effective order (Last Played always last).</summary>
    /// <param name="detail">Validated score for the chart.</param>
    /// <param name="chart">First visible or filtered chart.</param>
    /// <param name="song">Catalogue row (for Intensity).</param>
    /// <param name="currentSeason">Catalogue season.</param>
    /// <param name="settings">Visibility and order settings.</param>
    /// <returns>Fields; empty for a zero score.</returns>
    public static List<SongMetadataField> Fields(SongScoreDetail detail, Instrument chart, Song song, int? currentSeason, AppSettings settings)
    {
        if (detail.Score <= 0) return [];
        var byKind = new Dictionary<MetadataField, SongMetadataField>();
        if (settings.MetadataScore)
            byKind[MetadataField.Score] = new(MetadataField.Score, ScoreFormatting.Score(detail.Score), $"Score {ScoreFormatting.Score(detail.Score)}");
        var fc = detail.IsFullCombo == true;
        if (settings.MetadataPercentage || fc)
        {
            var accuracy = settings.MetadataPercentage && detail.Accuracy is { } a && double.IsFinite(a) ? a : (double?)null;
            if (accuracy is { } value)
            {
                var text = ScoreFormatting.Accuracy(value);
                byKind[MetadataField.Percentage] = fc
                    ? new(MetadataField.Percentage, $"{text} FC", $"Full combo, accuracy {text}") { FullCombo = true }
                    : new(MetadataField.Percentage, text, $"Accuracy {text}") { Tint = ScoreFormatting.AccuracyTint(value) };
            }
            else if (fc)
            {
                byKind[MetadataField.Percentage] = new(MetadataField.Percentage, "FC",
                    settings.MetadataPercentage ? "Full combo, accuracy unavailable" : "Full combo") { FullCombo = true };
            }
        }
        if (settings.MetadataPercentile && PercentileBucket(detail.Rank, detail.TotalEntries) is { } bucket)
        {
            var pct = Math.Min((double)detail.Rank!.Value / detail.TotalEntries!.Value * 100, 100);
            var tier = pct <= 1 ? SongPercentileTier.TopOne : pct <= 5 ? SongPercentileTier.TopFive : SongPercentileTier.Ordinary;
            byKind[MetadataField.Percentile] = new(MetadataField.Percentile, bucket, bucket) { Percentile = tier };
        }
        if (settings.MetadataStars && detail.Stars is > 0 and <= 6 && detail.Stars is { } stars)
        {
            var gold = stars >= 6;
            var count = gold ? 5 : stars;
            byKind[MetadataField.Stars] = new(MetadataField.Stars, new string('★', count), gold ? $"{count} gold stars" : count == 1 ? "1 star" : $"{count} stars")
            { Stars = (count, gold) };
        }
        if (settings.MetadataSeason && detail.Season is > 0 and { } season)
        {
            var current = season == currentSeason;
            var number = season.ToString(CultureInfo.CurrentCulture);
            byKind[MetadataField.Season] = new(MetadataField.Season, $"S{number}", current ? $"Current season {number}" : $"Season {number}")
            { CurrentSeason = current };
        }
        if (settings.MetadataIntensity && song.Difficulty?.ChartedValue(chart) is { } raw)
            byKind[MetadataField.Intensity] = new(MetadataField.Intensity, "", $"Song intensity {DifficultyScale.BarsForRaw(raw)} of 7") { IntensityRaw = raw };
        if (settings.MetadataDifficulty && detail.Difficulty is { } d && double.IsFinite(d) && d == Math.Round(d) && d is >= 0 and <= 3)
        {
            var index = (int)d;
            byKind[MetadataField.Difficulty] = new(MetadataField.Difficulty, DifficultyLetters[index], $"{DifficultyNames[index]} difficulty")
            { GameDifficulty = index };
        }
        if (settings.MetadataLastPlayed && detail.LastPlayedAt is { } rawDate)
        {
            var text = DateTimeOffset.TryParse(rawDate, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)
                ? "Last played " + date.ToLocalTime().ToString("d MMM yyyy", CultureInfo.CurrentCulture)
                : "Last played date unavailable";
            byKind[MetadataField.LastPlayed] = new(MetadataField.LastPlayed, text, text);
        }

        var order = settings.EnableVisualOrder ? SettingsOrder.Normalize(settings.SongRowVisualOrder) : DefaultOrder;
        return [.. order.Where(k => k != MetadataField.LastPlayed).Append(MetadataField.LastPlayed)
            .Where(byKind.ContainsKey).Select(k => byKind[k])];
    }

    /// <summary>Songs percentile bucket from rank/total.</summary>
    /// <param name="rank">One-based rank.</param>
    /// <param name="total">Population.</param>
    /// <returns>"Top N%", or <see langword="null"/> without a positive rank and total.</returns>
    public static string? PercentileBucket(int? rank, int? total)
    {
        if (rank is not > 0 || total is not > 0) return null;
        var pct = Math.Clamp((double)rank.Value / total.Value * 100, 1, 100);
        var bucket = PercentileBuckets.First(b => pct <= b);
        return $"Top {bucket.ToString(CultureInfo.CurrentCulture)}%";
    }
}
#endregion
