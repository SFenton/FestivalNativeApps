using System.Text;
using System.Text.Json;

namespace Festival.Core.Domain;

#region Filter settings
/// <summary>
/// Persisted Suggestions filter (web <c>SuggestionsFilterDraft</c>, Apple <c>SuggestionFilterSettings</c>):
/// per-instrument visibility plus a global and a per-instrument toggle per <see cref="SuggestionCategoryType"/>.
/// Only overrides that differ from the "on" default are stored, so an untouched filter serializes to nothing.
/// Immutable: every mutation returns a new value.
/// </summary>
public sealed class SuggestionFilterSettings : IEquatable<SuggestionFilterSettings>
{
    /// <summary>Largest accepted serialized size; anything bigger is treated as corrupt.</summary>
    public const int MaxBytes = 16_384;

    private readonly SortedSet<string> instrumentOff;
    private readonly SortedSet<string> globalTypeOff;
    private readonly SortedSet<string> perInstrumentTypeOff;

    private SuggestionFilterSettings(IEnumerable<string> instrumentOff, IEnumerable<string> globalTypeOff, IEnumerable<string> perInstrumentTypeOff)
    {
        this.instrumentOff = new SortedSet<string>(instrumentOff, StringComparer.Ordinal);
        this.globalTypeOff = new SortedSet<string>(globalTypeOff, StringComparer.Ordinal);
        this.perInstrumentTypeOff = new SortedSet<string>(perInstrumentTypeOff, StringComparer.Ordinal);
    }

    /// <summary>Every instrument and type enabled.</summary>
    public static SuggestionFilterSettings Default { get; } = new([], [], []);

    private static string PerKey(Instrument instrument, SuggestionCategoryType type) => $"{instrument.ServiceId()}|{type.Key()}";

    #region Reads
    /// <summary>Whether this instrument's suggestions are shown at all.</summary>
    /// <param name="instrument">Chart.</param>
    /// <returns><see langword="true"/> unless hidden.</returns>
    public bool IsInstrumentEnabled(Instrument instrument) => !instrumentOff.Contains(instrument.ServiceId());

    /// <summary>Whether a type is enabled globally.</summary>
    /// <param name="type">Family.</param>
    /// <returns><see langword="true"/> unless turned off.</returns>
    public bool IsGlobalEnabled(SuggestionCategoryType type) => !globalTypeOff.Contains(type.Key());

    /// <summary>Whether a type is enabled for an instrument-scoped category (global toggle when <paramref name="instrument"/> is null).</summary>
    /// <param name="type">Family.</param>
    /// <param name="instrument">The category's or row's chart.</param>
    /// <returns>Effective toggle.</returns>
    public bool IsTypeEnabled(SuggestionCategoryType type, Instrument? instrument)
    {
        if (instrument is not { } i) return IsGlobalEnabled(type);
        return !perInstrumentTypeOff.Contains(PerKey(i, type)) && IsGlobalEnabled(type);
    }

    /// <summary>Whether any toggle differs from its default (drives the filter button's accent).</summary>
    public bool IsActive => instrumentOff.Count > 0 || globalTypeOff.Count > 0 || perInstrumentTypeOff.Count > 0;

    /// <summary>Settings-visible charts intersected with this filter's instrument toggles.</summary>
    /// <param name="appVisible">Instruments enabled in Settings.</param>
    /// <returns>Instruments that may surface suggestions.</returns>
    public IReadOnlySet<Instrument> EffectiveInstruments(IEnumerable<Instrument> appVisible) =>
        appVisible.Where(IsInstrumentEnabled).ToHashSet();
    #endregion

    #region Mutations
    /// <summary>Shows or hides every suggestion for one instrument.</summary>
    /// <param name="instrument">Chart.</param>
    /// <param name="enabled">New value.</param>
    /// <returns>Updated filter.</returns>
    public SuggestionFilterSettings WithInstrument(Instrument instrument, bool enabled) =>
        new(Toggle(instrumentOff, instrument.ServiceId(), enabled), globalTypeOff, perInstrumentTypeOff);

    /// <summary>Toggles a type globally, cascading the value to every listed instrument's row.</summary>
    /// <param name="type">Family.</param>
    /// <param name="enabled">New value.</param>
    /// <param name="instruments">Instruments shown in the per-instrument section (Settings-visible).</param>
    /// <returns>Updated filter.</returns>
    public SuggestionFilterSettings WithGlobalType(SuggestionCategoryType type, bool enabled, IEnumerable<Instrument>? instruments = null)
    {
        var per = new SortedSet<string>(perInstrumentTypeOff, StringComparer.Ordinal);
        foreach (var instrument in instruments ?? InstrumentInfo.All) Set(per, PerKey(instrument, type), enabled);
        return new(instrumentOff, Toggle(globalTypeOff, type.Key(), enabled), per);
    }

    /// <summary>
    /// Toggles one instrument's row. Turning a row on re-enables the global switch; turning the last listed
    /// instrument's row off turns the global switch off too (web filter modal behavior).
    /// </summary>
    /// <param name="type">Family.</param>
    /// <param name="instrument">Row.</param>
    /// <param name="enabled">New value.</param>
    /// <param name="allInstruments">Every instrument shown in that section.</param>
    /// <returns>Updated filter.</returns>
    public SuggestionFilterSettings WithInstrumentType(SuggestionCategoryType type, Instrument instrument, bool enabled,
        IEnumerable<Instrument>? allInstruments = null)
    {
        var next = new SuggestionFilterSettings(instrumentOff, globalTypeOff, Toggle(perInstrumentTypeOff, PerKey(instrument, type), enabled));
        if (enabled) return new(next.instrumentOff, Toggle(next.globalTypeOff, type.Key(), true), next.perInstrumentTypeOff);
        return (allInstruments ?? InstrumentInfo.All).All(i => !next.IsTypeEnabled(type, i))
            ? new(next.instrumentOff, Toggle(next.globalTypeOff, type.Key(), false), next.perInstrumentTypeOff)
            : next;
    }

    private static SortedSet<string> Toggle(SortedSet<string> source, string key, bool enabled)
    {
        var copy = new SortedSet<string>(source, StringComparer.Ordinal);
        Set(copy, key, enabled);
        return copy;
    }

    private static void Set(SortedSet<string> offKeys, string key, bool enabled)
    {
        if (enabled) offKeys.Remove(key);
        else offKeys.Add(key);
    }
    #endregion

    #region Persistence
    /// <summary>Serializes to sorted JSON, or empty bytes for an untouched filter.</summary>
    /// <returns>UTF-8 JSON.</returns>
    public byte[] Encode()
    {
        if (!IsActive) return [];
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer))
        {
            writer.WriteStartObject();
            Write(writer, "globalTypeOff", globalTypeOff);
            Write(writer, "instrumentOff", instrumentOff);
            Write(writer, "perInstrumentTypeOff", perInstrumentTypeOff);
            writer.WriteEndObject();
        }
        return buffer.ToArray();

        static void Write(Utf8JsonWriter writer, string name, SortedSet<string> keys)
        {
            writer.WriteStartArray(name);
            foreach (var key in keys) writer.WriteStringValue(key);
            writer.WriteEndArray();
        }
    }

    /// <summary>Decodes saved bytes, falling back to <see cref="Default"/> for empty, oversized or corrupt data.</summary>
    /// <param name="data">Saved bytes.</param>
    /// <returns>A valid filter.</returns>
    public static SuggestionFilterSettings Decode(ReadOnlySpan<byte> data)
    {
        if (data.IsEmpty || data.Length > MaxBytes) return Default;
        try
        {
            var reader = new Utf8JsonReader(data);
            using var document = JsonDocument.ParseValue(ref reader);
            if (document.RootElement.ValueKind != JsonValueKind.Object) return Default;
            var validInstruments = InstrumentInfo.All.Select(i => i.ServiceId()).ToHashSet(StringComparer.Ordinal);
            var validTypes = SuggestionCategoryTypeInfo.All.Select(t => t.Key()).ToHashSet(StringComparer.Ordinal);
            var validPer = InstrumentInfo.All.SelectMany(i => SuggestionCategoryTypeInfo.All.Select(t => PerKey(i, t))).ToHashSet(StringComparer.Ordinal);
            return new SuggestionFilterSettings(
                Keys(document.RootElement, "instrumentOff", validInstruments),
                Keys(document.RootElement, "globalTypeOff", validTypes),
                Keys(document.RootElement, "perInstrumentTypeOff", validPer));
        }
        catch (JsonException)
        {
            return Default;
        }

        static IEnumerable<string> Keys(JsonElement root, string name, HashSet<string> valid)
        {
            if (!root.TryGetProperty(name, out var array) || array.ValueKind != JsonValueKind.Array) return [];
            return array.EnumerateArray()
                .Where(e => e.ValueKind == JsonValueKind.String && valid.Contains(e.GetString()!))
                .Select(e => e.GetString()!).ToList();
        }
    }
    #endregion

    #region Equality
    /// <inheritdoc/>
    public bool Equals(SuggestionFilterSettings? other) =>
        other is not null && instrumentOff.SetEquals(other.instrumentOff) && globalTypeOff.SetEquals(other.globalTypeOff) &&
        perInstrumentTypeOff.SetEquals(other.perInstrumentTypeOff);

    /// <inheritdoc/>
    public override bool Equals(object? obj) => Equals(obj as SuggestionFilterSettings);

    /// <inheritdoc/>
    public override int GetHashCode() => Encoding.UTF8.GetString(Encode()).GetHashCode(StringComparison.Ordinal);
    #endregion
}
#endregion

#region Category filtering
/// <summary>
/// Applies a filter and the current instrument visibility to generated categories (web
/// <c>shouldShowCategory</c> + <c>filterCategoryForInstruments</c> + the type equivalents, in one pass).
/// </summary>
public static class SuggestionCategoryFilter
{
    /// <summary>Filters one category, dropping it or trimming hidden-instrument rows from a mixed category.</summary>
    /// <param name="category">Generated category.</param>
    /// <param name="effectiveInstruments">Settings-visible charts intersected with the filter's instrument toggles.</param>
    /// <param name="filter">Saved filter.</param>
    /// <returns>The category (possibly trimmed), or <see langword="null"/> when hidden.</returns>
    public static SuggestionCategory? Visible(SuggestionCategory category, IReadOnlySet<Instrument> effectiveInstruments, SuggestionFilterSettings filter)
    {
        if (!filter.IsTypeEnabled(category.Type, category.Instrument)) return null;
        if (category.Instrument is { } instrument) return effectiveInstruments.Contains(instrument) ? category : null;
        var kept = category.Songs.Where(item => item.Instrument is not { } i ||
            (effectiveInstruments.Contains(i) && filter.IsTypeEnabled(category.Type, i))).ToList();
        if (kept.Count == 0) return null;
        return kept.Count == category.Songs.Count ? category : category with { Songs = kept };
    }
}
#endregion
