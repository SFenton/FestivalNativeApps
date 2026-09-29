using System.Buffers.Binary;
using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Difficulty
/// <summary>CHOpt difficulties served by the public path artifact route.</summary>
public enum PathDifficulty
{
    /// <summary>Easy.</summary>
    Easy,
    /// <summary>Medium.</summary>
    Medium,
    /// <summary>Hard.</summary>
    Hard,
    /// <summary>Expert (the default on every opening).</summary>
    Expert,
}

/// <summary>Wire names and labels for <see cref="PathDifficulty"/>.</summary>
public static class PathDifficultyInfo
{
    /// <summary>All difficulties in menu order.</summary>
    public static IReadOnlyList<PathDifficulty> All { get; } = Enum.GetValues<PathDifficulty>();

    /// <summary>Lowercase URL segment.</summary>
    /// <param name="difficulty">Difficulty.</param>
    /// <returns><c>easy</c>…<c>expert</c>.</returns>
    public static string WireName(this PathDifficulty difficulty) => difficulty.ToString().ToLowerInvariant();

    /// <summary>Title Case label.</summary>
    /// <param name="difficulty">Difficulty.</param>
    /// <returns>Label.</returns>
    public static string Label(this PathDifficulty difficulty) => difficulty.ToString();

    /// <summary>Whether a chart has CHOpt paths (Karaoke has none).</summary>
    /// <param name="instrument">Chart.</param>
    /// <returns><see langword="true"/> when paths exist.</returns>
    public static bool HasPaths(this Instrument instrument) => instrument != Instrument.Karaoke;
}
#endregion

#region Wire
/// <summary>A chart note used to identify the frets at an activation anchor.</summary>
public sealed record PathNote
{
    /// <summary>Beat position.</summary>
    [JsonPropertyName("beat")] public double Beat { get; init; }
    /// <summary>Timestamp in seconds.</summary>
    [JsonPropertyName("seconds")] public double? Seconds { get; init; }
    /// <summary>Whether the note grants Overdrive.</summary>
    [JsonPropertyName("isSpNote")] public bool IsSpNote { get; init; }
    /// <summary>Fret name → sustain length in beats.</summary>
    [JsonPropertyName("frets")] public IReadOnlyDictionary<string, double> Frets { get; init; } = new Dictionary<string, double>();
}

/// <summary>A scored note inside an activation (schema 2).</summary>
public sealed record PathStartNote
{
    /// <summary>Beat.</summary>
    [JsonPropertyName("beat")] public double Beat { get; init; }
    /// <summary>Seconds.</summary>
    [JsonPropertyName("seconds")] public double? Seconds { get; init; }
    /// <summary>Score before this note.</summary>
    [JsonPropertyName("cumulativeScore")] public long CumulativeScore { get; init; }
    /// <summary>Note value.</summary>
    [JsonPropertyName("noteValue")] public long NoteValue { get; init; }
    /// <summary>Overdrive fraction 0–1.</summary>
    [JsonPropertyName("odPercent")] public double OdPercent { get; init; }
    /// <summary>Whether it grants Overdrive.</summary>
    [JsonPropertyName("isSpGranting")] public bool IsSpGranting { get; init; }
}

/// <summary>One CHOpt activation, with optional schema-2 instructions.</summary>
public sealed record PathActivation
{
    /// <summary>Start beat.</summary>
    [JsonPropertyName("startBeat")] public double StartBeat { get; init; }
    /// <summary>End beat.</summary>
    [JsonPropertyName("endBeat")] public double EndBeat { get; init; }
    /// <summary>Start seconds.</summary>
    [JsonPropertyName("startSeconds")] public double? StartSeconds { get; init; }
    /// <summary>Activation beat.</summary>
    [JsonPropertyName("activationBeat")] public double? ActivationBeat { get; init; }
    /// <summary>Activation seconds.</summary>
    [JsonPropertyName("activationSeconds")] public double? ActivationSeconds { get; init; }
    /// <summary>Anchor note beat.</summary>
    [JsonPropertyName("anchorBeat")] public double? AnchorBeat { get; init; }
    /// <summary>Overdrive fraction at activation, 0–1.</summary>
    [JsonPropertyName("odAtActivation")] public double? OdAtActivation { get; init; }
    /// <summary>Score before activation.</summary>
    [JsonPropertyName("scoreBeforeActivation")] public long? ScoreBeforeActivation { get; init; }
    /// <summary>Human instruction.</summary>
    [JsonPropertyName("instruction")] public string? Instruction { get; init; }
    /// <summary>Scored notes in the activation.</summary>
    [JsonPropertyName("startNotes")] public IReadOnlyList<PathStartNote>? StartNotes { get; init; }
}

/// <summary>Structured text artifact from <c>GET /api/paths/{song}/{chart}/{difficulty}/data</c>.</summary>
public sealed record SongPathData
{
    /// <summary>Schema version (1–2).</summary>
    [JsonPropertyName("schemaVersion")] public int? SchemaVersion { get; init; }
    /// <summary>Song name.</summary>
    [JsonPropertyName("songName")] public string SongName { get; init; } = "";
    /// <summary>Artist.</summary>
    [JsonPropertyName("artist")] public string Artist { get; init; } = "";
    /// <summary>Charter.</summary>
    [JsonPropertyName("charter")] public string Charter { get; init; } = "";
    /// <summary>Difficulty the file was generated for.</summary>
    [JsonPropertyName("difficulty")] public string Difficulty { get; init; } = "";
    /// <summary>Optimal total score.</summary>
    [JsonPropertyName("totalScore")] public long TotalScore { get; init; }
    /// <summary>CHOpt summary line.</summary>
    [JsonPropertyName("pathSummary")] public string PathSummary { get; init; } = "";
    /// <summary>Activations.</summary>
    [JsonPropertyName("activations")] public IReadOnlyList<PathActivation> Activations { get; init; } = [];
    /// <summary>Chart notes.</summary>
    [JsonPropertyName("notes")] public IReadOnlyList<PathNote> Notes { get; init; } = [];

    private static readonly string[] FretOrder = ["green", "red", "yellow", "blue", "orange", "open"];

    /// <summary>Rejects malformed or oversized path data.</summary>
    /// <param name="requested">Difficulty whose endpoint produced this response.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(PathDifficulty requested)
    {
        var valid = SchemaVersion is null or 1 or 2 &&
                    string.Equals(Difficulty, requested.WireName(), StringComparison.OrdinalIgnoreCase) &&
                    !string.IsNullOrEmpty(SongName) && !string.IsNullOrEmpty(Artist) && TotalScore > 0 &&
                    Activations is { Count: <= 128 } && Notes is { Count: <= 25_000 } &&
                    Activations.All(ValidActivation) && Notes.All(ValidNote);
        if (!valid) throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }

    /// <summary>Resolves table rows using the source's 0.02-beat anchor tolerance.</summary>
    /// <returns>Ordered activation rows.</returns>
    public List<PathActivationRow> ActivationRows()
    {
        var ordered = Notes.OrderBy(n => n.Beat).ToArray();
        var rows = new List<PathActivationRow>(Activations.Count);
        for (var index = 0; index < Activations.Count; index++)
        {
            var activation = Activations[index];
            var first = activation.StartNotes is { Count: > 0 } notes ? notes[0] : null;
            var beat = activation.ActivationBeat ?? first?.Beat ?? activation.StartBeat;
            var anchor = activation.AnchorBeat ?? first?.Beat ?? NearbyAnchor(beat, ordered);
            rows.Add(new PathActivationRow(
                index + 1,
                activation.Instruction,
                beat,
                activation.ActivationSeconds ?? first?.Seconds ?? activation.StartSeconds ?? 0,
                activation.OdAtActivation is { } od ? od * 100 : first is not null ? first.OdPercent * 100 : null,
                activation.ScoreBeforeActivation ?? first?.CumulativeScore,
                anchor is { } a ? ChordFrets(a, ordered) : []));
        }
        return rows;
    }

    /// <summary>All fret keys within 0.02 beats of an anchor, in the source's visible order.</summary>
    /// <param name="anchor">Resolved anchor beat.</param>
    /// <param name="ordered">Beat-sorted notes.</param>
    /// <returns>Fret names.</returns>
    private static List<string> ChordFrets(double anchor, PathNote[] ordered)
    {
        int low = 0, high = ordered.Length;
        while (low < high)
        {
            var middle = (low + high) / 2;
            if (ordered[middle].Beat < anchor - 0.02) low = middle + 1;
            else high = middle;
        }
        var found = new HashSet<string>(StringComparer.Ordinal);
        for (; low < ordered.Length && ordered[low].Beat < anchor + 0.02; low++)
        {
            if (Math.Abs(ordered[low].Beat - anchor) < 0.02) found.UnionWith(ordered[low].Frets.Keys);
        }
        return [.. FretOrder.Where(found.Contains)];
    }

    /// <summary>Prefers a note sustained through the activation, then a coincident earlier note.</summary>
    /// <param name="beat">Activation beat.</param>
    /// <param name="ordered">Beat-sorted notes.</param>
    /// <returns>Anchor beat, or <see langword="null"/>.</returns>
    private static double? NearbyAnchor(double beat, PathNote[] ordered)
    {
        double? prior = null, sustained = null;
        foreach (var note in ordered)
        {
            if (note.Beat > beat + 0.02) break;
            prior = note.Beat;
            var sustain = note.Frets.Count == 0 ? 0 : note.Frets.Values.Max();
            if (note.Beat + sustain >= beat - 0.02) sustained = note.Beat;
        }
        if (sustained is not null) return sustained;
        return prior is { } p && Math.Abs(p - beat) < 0.02 ? p : null;
    }

    /// <summary>Validates one activation's beats, times, OD and notes.</summary>
    /// <param name="a">Activation.</param>
    /// <returns><see langword="true"/> when displayable.</returns>
    private static bool ValidActivation(PathActivation a) =>
        a is not null && ValidBeat(a.StartBeat) && ValidBeat(a.EndBeat) && a.EndBeat >= a.StartBeat &&
        (a.ActivationBeat is null || ValidBeat(a.ActivationBeat.Value)) && (a.AnchorBeat is null || ValidBeat(a.AnchorBeat.Value)) &&
        (a.StartSeconds is null || ValidSeconds(a.StartSeconds.Value)) &&
        (a.ActivationSeconds is null || ValidSeconds(a.ActivationSeconds.Value)) &&
        (a.OdAtActivation is null || ValidFraction(a.OdAtActivation.Value)) && a.ScoreBeforeActivation is null or >= 0 &&
        (a.Instruction is null || (a.Instruction.Length <= 500 && !ProfileText.ContainsUnsafeCharacter(a.Instruction))) &&
        (a.StartNotes ?? []).Count <= 256 &&
        (a.StartNotes ?? []).All(n => n is not null && ValidBeat(n.Beat) && (n.Seconds is null || ValidSeconds(n.Seconds.Value)) &&
                                      n.CumulativeScore >= 0 && n.NoteValue >= 0 && ValidFraction(n.OdPercent));

    /// <summary>Validates one note's beat, time and frets.</summary>
    /// <param name="n">Note.</param>
    /// <returns><see langword="true"/> when displayable.</returns>
    private static bool ValidNote(PathNote n) =>
        n is not null && n.Frets is not null && ValidBeat(n.Beat) && (n.Seconds is null || ValidSeconds(n.Seconds.Value)) &&
        n.Frets.All(f => FretOrder.Contains(f.Key) && ValidBeat(f.Value));

    private static bool ValidBeat(double beat) => double.IsFinite(beat) && beat is >= 0 and <= 1_000_000;

    private static bool ValidSeconds(double seconds) => double.IsFinite(seconds) && seconds is >= 0 and <= 86_400;

    private static bool ValidFraction(double value) => double.IsFinite(value) && value is >= 0 and <= 1;
}
#endregion

#region Display rows
/// <summary>One resolved activation-table row.</summary>
/// <param name="Number">One-based activation number.</param>
/// <param name="Instruction">Optional human instruction.</param>
/// <param name="Beat">Activation beat.</param>
/// <param name="Seconds">Activation time.</param>
/// <param name="OdPercent">Overdrive 0–100, if known.</param>
/// <param name="ScoreBeforeActivation">Score before activating, if known.</param>
/// <param name="Frets">Anchor chord frets in visible order.</param>
public sealed record PathActivationRow(
    int Number, string? Instruction, double Beat, double Seconds, double? OdPercent, long? ScoreBeforeActivation,
    IReadOnlyList<string> Frets)
{
    /// <summary>Beat with two decimals.</summary>
    public string BeatText => Beat.ToString("0.00", CultureInfo.CurrentCulture);

    /// <summary><c>mm:ss:SSS</c> with millisecond rollover.</summary>
    public string TimeText
    {
        get
        {
            var millis = (long)Math.Round(Seconds * 1000, MidpointRounding.AwayFromZero);
            return string.Create(CultureInfo.InvariantCulture, $"{millis / 60_000:00}:{millis / 1_000 % 60:00}:{millis % 1_000:000}");
        }
    }

    /// <summary>Overdrive for the web's bar: rounded and clamped to 0–100, or <see langword="null"/> when unknown.</summary>
    public int? OdFill => OdPercent is { } od ? (int)Math.Clamp(Math.Round(od, MidpointRounding.AwayFromZero), 0, 100) : null;

    /// <summary>Rounded Overdrive, e.g. <c>75%</c>, or the web's em dash when unknown.</summary>
    public string OdText => OdFill is { } od ? string.Create(CultureInfo.CurrentCulture, $"{od}%") : Missing;

    /// <summary>Grouped score, or the web's em dash when unknown.</summary>
    public string ScoreText => ScoreBeforeActivation is { } s ? s.ToString("N0", CultureInfo.CurrentCulture) : Missing;

    /// <summary>Placeholder for an unknown value (web <c>missingValue</c>).</summary>
    public const string Missing = "—";

    /// <summary>Narrator name for the whole row card, e.g. "Activation 1: green, red; beat 10.00; time 01:01:235; Overdrive 50%; score 12,345".</summary>
    public string AccessibleName =>
        $"Activation {Number}: {FretsText}; beat {BeatText}; time {TimeText}; Overdrive {(OdFill is { } od ? od + "%" : "unavailable")}; " +
        $"score {(ScoreBeforeActivation is { } s ? s.ToString("N0", CultureInfo.CurrentCulture) : "unavailable")}";

    /// <summary>Spoken fret list.</summary>
    public string FretsText => Frets.Count == 0 ? "No anchor" : string.Join(", ", Frets);

    /// <summary>Whether a fret is part of the anchor chord.</summary>
    /// <param name="fret">Fret name.</param>
    /// <returns><see langword="true"/> when lit.</returns>
    public bool HasFret(string fret) => Frets.Contains(fret);
}
#endregion

#region Image validation
/// <summary>Bounds a path PNG before decoding (signature, single IHDR, dimensions, byte size).</summary>
public static class PathImageValidation
{
    /// <summary>Largest accepted PNG body.</summary>
    public const int MaxBytes = 8_000_000;

    private static readonly byte[] Signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    /// <summary>Reads and validates PNG dimensions from the IHDR chunk.</summary>
    /// <param name="bytes">Response body.</param>
    /// <returns>Pixel width and height.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public static (int Width, int Height) Dimensions(byte[] bytes)
    {
        if (bytes.Length is < 33 or > MaxBytes || !bytes.AsSpan(0, 8).SequenceEqual(Signature) ||
            !bytes.AsSpan(12, 4).SequenceEqual("IHDR"u8))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var width = BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(16, 4));
        var height = BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(20, 4));
        if (width is < 1 or > 8192 || height is < 1 or > 30_000 || (long)width * height > 24_000_000)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        return (width, height);
    }
}
#endregion
