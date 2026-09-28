namespace Festival.Core.Domain;

#region Random source
/// <summary>Pluggable random source so generator tests can force deterministic output.</summary>
public interface ISuggestionRng
{
    /// <summary>Returns a value in [0, 1).</summary>
    /// <returns>Next uniform double.</returns>
    double NextDouble();

    /// <summary>Returns a value in [0, <paramref name="maxExclusive"/>), or 0 for a non-positive bound.</summary>
    /// <param name="maxExclusive">Exclusive upper bound.</param>
    /// <returns>Next integer.</returns>
    int NextInt(int maxExclusive);
}

/// <summary>
/// Mulberry32, the seeded PRNG the web and Apple generators use, ported bit-for-bit with 32-bit
/// wrapping arithmetic so a fixed seed reproduces the same shuffle order on every platform.
/// </summary>
/// <param name="seed">Any 32-bit value.</param>
public sealed class SeededSuggestionRng(uint seed) : ISuggestionRng
{
    private uint state = seed;

    /// <inheritdoc/>
    public double NextDouble()
    {
        unchecked
        {
            state += 0x6D2B79F5;
            var t1 = (state ^ (state >> 15)) * (state | 1);
            var t2 = (t1 + ((t1 ^ (t1 >> 7)) * (t1 | 61))) ^ t1;
            return (t2 ^ (t2 >> 14)) / 4_294_967_296.0;
        }
    }

    /// <inheritdoc/>
    public int NextInt(int maxExclusive) => maxExclusive > 0 ? (int)(NextDouble() * maxExclusive) : 0;
}
#endregion
