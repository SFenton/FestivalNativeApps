namespace Festival.Core.Domain;

#region Ranking board
/// <summary>
/// One account-rankings board: a single instrument (<c>/api/rankings/{instrument}</c>) or a within-group combo
/// (<c>/api/rankings/combo?combo=</c>), as the web's <c>RankingScope</c> (<c>utils/rankingScopes.ts</c>). Value-equal by
/// its instrument mask.
/// </summary>
public sealed record RankingBoard
{
    /// <summary>Scope families in page order (web <c>SCOPE_FAMILIES</c>): OG band and Pro Strings support a combo board.</summary>
    private static readonly (Instrument[] Instruments, bool SupportsCombo)[] Families =
    [
        ([Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals], true),
        ([Instrument.ProLead, Instrument.ProBass], true),
        ([Instrument.Karaoke, Instrument.ProCymbals, Instrument.ProDrums], false),
    ];

    /// <summary>Creates a board from a validated mask.</summary>
    /// <param name="mask">One instrument bit, or a within-group combo mask.</param>
    private RankingBoard(int mask) => Mask = mask;

    /// <summary>Instrument bitmask (bit = service order index).</summary>
    public int Mask { get; }

    /// <summary>A single instrument's board.</summary>
    /// <param name="instrument">Chart.</param>
    /// <returns>Board.</returns>
    public static RankingBoard Single(Instrument instrument) => new(1 << (int)instrument);

    /// <summary>A combo board from its hex ID (web <c>isRankingScopeComboId</c>): two or more instruments of one group.</summary>
    /// <param name="comboId">Hex combo ID such as <c>0f</c> (any case).</param>
    /// <returns>Board, or <see langword="null"/> for a missing, malformed or cross-group ID.</returns>
    public static RankingBoard? Combo(string? comboId) =>
        comboId != RivalCombo.ProDrumsToken && RivalCombo.InstrumentsFor(comboId) is { } instruments &&
        RivalCombo.IsWithinGroup(RivalCombo.Mask(instruments))
            ? new RankingBoard(RivalCombo.Mask(instruments))
            : null;

    /// <summary>Instruments in service order.</summary>
    public IReadOnlyList<Instrument> Instruments => RivalCombo.FromMask(Mask);

    /// <summary>Whether this is a combo board.</summary>
    public bool IsCombo => int.PopCount(Mask) > 1;

    /// <summary>The board's first instrument (the only one for a single board).</summary>
    public Instrument Instrument => Instruments[0];

    /// <summary>Lowercase hex combo ID (web <c>comboIdFromInstruments</c>), or <see langword="null"/> for a single board.</summary>
    public string? ComboId => IsCombo ? RivalCombo.ComboId(Instruments) : null;

    /// <summary>Stable key: the combo ID or the instrument's service ID (web <c>scopeKey</c>).</summary>
    public string Id => ComboId ?? Instrument.ServiceId();

    /// <summary>Display label, instrument labels joined with " + " (web <c>rankingScopeLabel</c>).</summary>
    public string Label => string.Join(" + ", Instruments.Select(i => i.Label()));

    /// <summary>Icon files in service order.</summary>
    public IReadOnlyList<string> IconFiles => [.. Instruments.Select(i => i.IconFile())];

    /// <summary>
    /// The boards for the Settings-visible instruments (web <c>resolveSupportedRankingScopes</c>): per family in order, a
    /// combo board first when two or more of an OG band or Pro Strings family are visible, then each visible instrument.
    /// The Karaoke / Pro Drums family has no combo board.
    /// </summary>
    /// <param name="visible">Settings-visible instruments.</param>
    /// <returns>Boards in page order.</returns>
    public static IReadOnlyList<RankingBoard> Scopes(IEnumerable<Instrument> visible)
    {
        var shown = visible.ToHashSet();
        var boards = new List<RankingBoard>();
        foreach (var (instruments, supportsCombo) in Families)
        {
            var selected = instruments.Where(shown.Contains).ToList();
            if (supportsCombo && selected.Count > 1) boards.Add(new RankingBoard(RivalCombo.Mask(selected)));
            boards.AddRange(selected.Select(Single));
        }
        return boards;
    }
}
#endregion
