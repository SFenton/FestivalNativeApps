namespace Festival.Core.Domain;

#region Instrument selector
/// <summary>How the selector decides between the full row and compact arrow cycling.</summary>
public enum InstrumentSelectorCompactMode
{
    /// <summary>Compact only when the row is too narrow for every button (web default).</summary>
    Auto,
    /// <summary>Always compact (web <c>compact={true}</c>).</summary>
    Always,
    /// <summary>Always the full row (web <c>compact={false}</c>).</summary>
    Never,
}

/// <summary>
/// Selection rules of the web <c>InstrumentSelector</c> (<c>components/common/InstrumentSelector.tsx</c>), UI-free: a row of
/// instrument circles where pressing one selects it (pressing it again clears it unless <see cref="Required"/>), with
/// hidden, disabled (unselectable) and muted (conflicting but selectable) instruments, and a compact arrow-cycling mode
/// that skips disabled instruments and can preview without committing (<see cref="DeferSelection"/>).
/// </summary>
public sealed class InstrumentSelectorState
{
    /// <summary>Web <c>Layout.demoInstrumentBtn</c>: each circle button is 64 epx.</summary>
    public const double ButtonSize = 64;

    /// <summary>Web <c>Gap.md</c> between buttons.</summary>
    public const double ButtonGap = 12;

    private IReadOnlyList<Instrument> instruments = [];
    private IReadOnlySet<Instrument> hidden = new HashSet<Instrument>();
    private int previewIndex;

    /// <summary>Source instruments in display order.</summary>
    public IReadOnlyList<Instrument> Instruments
    {
        get => instruments;
        set
        {
            var before = Available.Count;
            instruments = value;
            if (Available.Count != before) previewIndex = 0;
        }
    }

    /// <summary>Instruments left out of the rendered row without changing the source list.</summary>
    public IReadOnlySet<Instrument> Hidden
    {
        get => hidden;
        set
        {
            var before = Available.Count;
            hidden = value;
            if (Available.Count != before) previewIndex = 0;
        }
    }

    /// <summary>Instruments rendered but not selectable.</summary>
    public IReadOnlySet<Instrument> Disabled { get; set; } = new HashSet<Instrument>();

    /// <summary>Instruments rendered as conflicting but still selectable.</summary>
    public IReadOnlySet<Instrument> Muted { get; set; } = new HashSet<Instrument>();

    /// <summary>Selected instrument (may name a hidden one; see <see cref="EffectiveSelected"/>).</summary>
    public Instrument? Selected { get; set; }

    /// <summary>When set, pressing the selected instrument keeps it selected.</summary>
    public bool Required { get; set; }

    /// <summary>When set and nothing is selected, compact arrows move a local preview instead of selecting.</summary>
    public bool DeferSelection { get; set; }

    /// <summary>Instruments actually rendered.</summary>
    public IReadOnlyList<Instrument> Available => [.. instruments.Where(i => !hidden.Contains(i))];

    /// <summary>The selection when it is one of the rendered instruments, else <see langword="null"/>.</summary>
    public Instrument? EffectiveSelected => Selected is { } s && Available.Contains(s) ? s : null;

    /// <summary>Whether a rendered instrument is selected (the expandable content shows).</summary>
    public bool HasSelection => EffectiveSelected is not null;

    /// <summary>The instrument the compact centre button shows: the selection, else the preview.</summary>
    public Instrument? CompactKey
    {
        get
        {
            if (EffectiveSelected is { } selected) return selected;
            var available = Available;
            if (available.Count == 0) return null;
            return available[Math.Clamp(previewIndex, 0, available.Count - 1)];
        }
    }

    /// <summary>Whether an instrument is disabled.</summary>
    /// <param name="instrument">Instrument.</param>
    /// <returns><see langword="true"/> when not selectable.</returns>
    public bool IsDisabled(Instrument instrument) => Disabled.Contains(instrument);

    /// <summary>Whether a row button draws muted: a conflicting instrument that is neither selected nor disabled.</summary>
    /// <param name="instrument">Instrument.</param>
    /// <returns><see langword="true"/> when muted.</returns>
    public bool IsMuted(Instrument instrument) =>
        EffectiveSelected != instrument && !IsDisabled(instrument) && Muted.Contains(instrument);

    /// <summary>Whether the compact centre button draws muted (the web ignores selection here).</summary>
    /// <returns><see langword="true"/> when muted.</returns>
    public bool IsCompactMuted() => CompactKey is { } key && !IsDisabled(key) && Muted.Contains(key);

    /// <summary>UIA item status announcing a muted (conflicting) instrument, which is otherwise shown by opacity alone.</summary>
    /// <param name="muted">Whether the button draws muted.</param>
    /// <returns><see cref="ConflictStatus"/> when muted, else an empty string.</returns>
    public static string ItemStatus(bool muted) => muted ? ConflictStatus : "";

    /// <summary>Item status of a muted instrument (the web's <c>data-conflict</c>).</summary>
    public const string ConflictStatus = "Conflicts with current selection";

    /// <summary>
    /// The row button that should take keyboard focus when the selector leaves compact mode while its centre button
    /// was focused: the selection, else the previewed instrument, else the first selectable one.
    /// </summary>
    /// <returns>Instrument, or <see langword="null"/> when nothing is selectable.</returns>
    public Instrument? FocusTarget()
    {
        if (EffectiveSelected is { } selected) return selected;
        if (CompactKey is { } key && !IsDisabled(key)) return key;
        foreach (var instrument in Available)
            if (!IsDisabled(instrument)) return instrument;
        return null;
    }

    /// <summary>Whether to render compact.</summary>
    /// <param name="mode">Caller's mode.</param>
    /// <param name="rowWidth">Measured row width in epx (0 before layout).</param>
    /// <param name="buttonSize">Button width.</param>
    /// <param name="gap">Gap between buttons.</param>
    /// <returns><see langword="true"/> for arrow cycling.</returns>
    public bool IsCompact(InstrumentSelectorCompactMode mode, double rowWidth, double buttonSize = ButtonSize, double gap = ButtonGap)
    {
        var count = Available.Count;
        if (count == 0) return false;
        return mode switch
        {
            InstrumentSelectorCompactMode.Always => true,
            InstrumentSelectorCompactMode.Never => false,
            _ => rowWidth > 0 && rowWidth < count * buttonSize + (count - 1) * gap,
        };
    }

    /// <summary>Row button press: select it, or clear it when already selected and not required.</summary>
    /// <param name="instrument">Pressed instrument.</param>
    /// <returns>New selection to report, or <see langword="false"/> in <paramref name="changed"/> when nothing happens.</returns>
    /// <param name="changed">Whether the caller should report a selection.</param>
    public Instrument? Press(Instrument instrument, out bool changed)
    {
        changed = !IsDisabled(instrument) && Available.Contains(instrument);
        if (!changed) return Selected;
        return EffectiveSelected == instrument && !Required ? null : instrument;
    }

    /// <summary>Compact centre press: toggles the selection, or commits the preview.</summary>
    /// <param name="changed">Whether the caller should report a selection.</param>
    /// <returns>New selection.</returns>
    public Instrument? PressCompact(out bool changed)
    {
        if (EffectiveSelected is { } selected)
        {
            changed = true;
            return Required ? selected : null;
        }
        changed = CompactKey is { } key && !IsDisabled(key);
        return changed ? CompactKey : Selected;
    }

    /// <summary>Compact arrow: moves the selection (skipping disabled), or the local preview when deferring.</summary>
    /// <param name="direction">+1 next, −1 previous.</param>
    /// <param name="changed">Whether the caller should report a selection (the preview changes silently).</param>
    /// <returns>New selection.</returns>
    public Instrument? Cycle(int direction, out bool changed)
    {
        changed = false;
        var available = Available;
        if (available.Count == 0) return Selected;
        var dir = direction >= 0 ? 1 : -1;
        if (EffectiveSelected is not { } selected)
        {
            if (DeferSelection)
            {
                previewIndex = ((previewIndex + dir) % available.Count + available.Count) % available.Count;
                return Selected;
            }
            var edge = NextSelectable(available, dir == 1 ? -1 : 0, dir);
            if (edge < 0) return Selected;
            changed = true;
            return available[edge];
        }
        var next = NextSelectable(available, IndexOf(available, selected), dir);
        if (next < 0) return Selected;
        changed = true;
        return available[next];
    }

    /// <summary>First selectable index after <paramref name="start"/> walking in <paramref name="dir"/>, wrapping.</summary>
    /// <param name="available">Rendered instruments.</param>
    /// <param name="start">Start index (exclusive).</param>
    /// <param name="dir">±1.</param>
    /// <returns>Index or −1.</returns>
    private int NextSelectable(IReadOnlyList<Instrument> available, int start, int dir)
    {
        for (var offset = 1; offset <= available.Count; offset++)
        {
            var next = ((start + offset * dir) % available.Count + available.Count) % available.Count;
            if (!IsDisabled(available[next])) return next;
        }
        return -1;
    }

    /// <summary>Index of an instrument in a list.</summary>
    /// <param name="list">List.</param>
    /// <param name="instrument">Instrument.</param>
    /// <returns>Index or −1.</returns>
    private static int IndexOf(IReadOnlyList<Instrument> list, Instrument instrument)
    {
        for (var i = 0; i < list.Count; i++)
            if (list[i] == instrument) return i;
        return -1;
    }
}
#endregion
