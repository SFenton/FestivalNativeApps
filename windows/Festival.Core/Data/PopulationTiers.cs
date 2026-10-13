using System.Text.Json;
using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Population tiers
/// <summary>
/// One chart's precomputed filtered-population curve from <c>/api/songs</c> (<c>populationTiers[chart]</c>, wire
/// <c>{bc, t: [{l, t}]}</c>): how many entries remain at each invalid-score leeway. Stored as parallel primitive arrays
/// because the catalogue carries thousands of changepoints (Android <c>PopulationTiers</c>).
/// </summary>
[JsonConverter(typeof(PopulationTiersConverter))]
public sealed class PopulationTiers
{
    /// <summary>Creates a curve.</summary>
    /// <param name="baseCount">Entries always under the threshold band (<c>bc</c>).</param>
    /// <param name="leeways">Changepoint leeways, ascending (<c>t[].l</c>).</param>
    /// <param name="totals">Filtered totals at each changepoint (<c>t[].t</c>).</param>
    public PopulationTiers(int baseCount, double[] leeways, int[] totals)
    {
        BaseCount = baseCount;
        Leeways = leeways;
        Totals = totals;
    }

    /// <summary>Entries always under the threshold band (<c>bc</c>).</summary>
    public int BaseCount { get; }

    /// <summary>Changepoint leeways, ascending.</summary>
    public IReadOnlyList<double> Leeways { get; }

    /// <summary>Filtered totals at each changepoint.</summary>
    public IReadOnlyList<int> Totals { get; }

    /// <summary>Placeholder for an unreadable curve (<see cref="IsWellFormed"/> is <see langword="false"/>).</summary>
    internal static PopulationTiers Invalid { get; } = new(-1, [], []);

    /// <summary>Whether counts are non-negative and leeways finite and ascending.</summary>
    public bool IsWellFormed
    {
        get
        {
            if (BaseCount < 0 || Leeways.Count != Totals.Count) return false;
            for (var i = 0; i < Leeways.Count; i++)
            {
                if (Totals[i] < 0 || !double.IsFinite(Leeways[i]) || (i > 0 && Leeways[i - 1] > Leeways[i])) return false;
            }
            return true;
        }
    }

    /// <summary>Filtered population at a leeway (web <c>getFilteredTotal</c>): the last changepoint at or below it, else <see cref="BaseCount"/>.</summary>
    /// <param name="leeway">Leeway percent.</param>
    /// <returns>Filtered total.</returns>
    public int Total(double leeway)
    {
        var result = BaseCount;
        for (var i = 0; i < Leeways.Count && Leeways[i] <= leeway; i++) result = Totals[i];
        return result;
    }
}

/// <summary>
/// Reads the compact wire into primitive arrays. A malformed curve reads as <see cref="PopulationTiers.Invalid"/>
/// (never used) instead of failing the whole catalogue. Writing exists for tests and fixtures.
/// </summary>
public sealed class PopulationTiersConverter : JsonConverter<PopulationTiers>
{
    /// <inheritdoc />
    public override PopulationTiers? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null) return null;
        using var document = JsonDocument.ParseValue(ref reader);
        return Parse(document.RootElement) ?? PopulationTiers.Invalid;
    }

    /// <summary>Parses one curve.</summary>
    /// <param name="element">Wire object.</param>
    /// <returns>Curve, or <see langword="null"/> when malformed.</returns>
    private static PopulationTiers? Parse(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object) return null;
        var baseCount = 0;
        if (element.TryGetProperty("bc", out var bc) && (bc.ValueKind != JsonValueKind.Number || !bc.TryGetInt32(out baseCount))) return null;
        if (!element.TryGetProperty("t", out var tiers)) return new(baseCount, [], []);
        if (tiers.ValueKind != JsonValueKind.Array) return null;
        var count = tiers.GetArrayLength();
        var leeways = new double[count];
        var totals = new int[count];
        var i = 0;
        foreach (var tier in tiers.EnumerateArray())
        {
            if (tier.ValueKind != JsonValueKind.Object ||
                !tier.TryGetProperty("l", out var l) || l.ValueKind != JsonValueKind.Number || !l.TryGetDouble(out leeways[i]) ||
                !tier.TryGetProperty("t", out var t) || t.ValueKind != JsonValueKind.Number || !t.TryGetInt32(out totals[i])) return null;
            i++;
        }
        return new(baseCount, leeways, totals);
    }

    /// <inheritdoc />
    public override void Write(Utf8JsonWriter writer, PopulationTiers value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        writer.WriteNumber("bc", value.BaseCount);
        writer.WriteStartArray("t");
        for (var i = 0; i < value.Leeways.Count; i++)
        {
            writer.WriteStartObject();
            writer.WriteNumber("l", value.Leeways[i]);
            writer.WriteNumber("t", value.Totals[i]);
            writer.WriteEndObject();
        }
        writer.WriteEndArray();
        writer.WriteEndObject();
    }
}
#endregion
