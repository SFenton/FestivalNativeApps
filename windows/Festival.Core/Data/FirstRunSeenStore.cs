using System.Text.Json;

namespace Festival.Core.Data;

#region First-run seen store
/// <summary>
/// Bounded, validated first-run seen-state (web <c>loadSeenSlides</c>/<c>saveSeenSlides</c>). An unparsable or
/// oversized blob recovers to empty; individually malformed records are dropped while the rest are kept.
/// </summary>
/// <param name="blob">Backing blob (<c>first-run.json</c> in the app, memory in tests).</param>
public sealed class FirstRunSeenStore(IBlobStore blob)
{
    /// <summary>Most records kept; the oldest <c>seenAt</c> are evicted first (well above the ~42 real slides).</summary>
    public const int MaxRecords = 500;

    /// <summary>Largest accepted blob.</summary>
    public const int MaxBytes = 256 * 1024;

    /// <summary>Default file.</summary>
    public static string DefaultPath { get; } = Path.Combine(FileBlobStore.AppDataFolder, "first-run.json");

    private readonly Lock gate = new();

    /// <summary>Reads validated seen-state.</summary>
    /// <returns>Slide ID → record.</returns>
    public IReadOnlyDictionary<string, FirstRunSeenRecord> Load()
    {
        lock (gate) return Decode(blob.Read());
    }

    /// <summary>Replaces the seen-state (bounded before writing).</summary>
    /// <param name="storage">New state.</param>
    public void Save(IReadOnlyDictionary<string, FirstRunSeenRecord> storage)
    {
        lock (gate) blob.Write(Encode(Bounded(storage)));
    }

    /// <summary>Marks every displayed slide seen at once.</summary>
    /// <param name="slides">Slides that were shown.</param>
    /// <param name="now">Timestamp.</param>
    public void MarkSeen(IEnumerable<FirstRunSlide> slides, DateTimeOffset now)
    {
        var list = slides.ToList();
        if (list.Count == 0) return;
        lock (gate)
        {
            var storage = new Dictionary<string, FirstRunSeenRecord>(Decode(blob.Read()));
            foreach (var slide in list) storage[slide.Id] = FirstRunSlideEvaluator.SeenRecord(slide, now);
            blob.Write(Encode(Bounded(storage)));
        }
    }

    /// <summary>Forgets one page's slides (before a Settings replay, web <c>resetPage</c>).</summary>
    /// <param name="slideIds">The page's slide IDs.</param>
    public void ResetPage(IEnumerable<string> slideIds)
    {
        var ids = slideIds.ToList();
        if (ids.Count == 0) return;
        lock (gate)
        {
            var storage = new Dictionary<string, FirstRunSeenRecord>(Decode(blob.Read()));
            foreach (var id in ids) storage.Remove(id);
            blob.Write(Encode(storage));
        }
    }

    /// <summary>Forgets everything (web <c>resetAll</c>; no UI yet, as on the web).</summary>
    public void ResetAll()
    {
        lock (gate) blob.Write(null);
    }

    /// <summary>Decodes, dropping malformed records; any top-level failure is empty.</summary>
    /// <param name="bytes">Stored bytes.</param>
    /// <returns>Validated state.</returns>
    internal static Dictionary<string, FirstRunSeenRecord> Decode(byte[]? bytes)
    {
        if (bytes is not { Length: > 0 and <= MaxBytes }) return [];
        try
        {
            var raw = JsonSerializer.Deserialize(bytes, FirstRunJsonContext.Default.DictionaryStringFirstRunSeenRecord);
            return raw?.Where(p => p.Key is { Length: > 0 and <= 200 } && p.Value is { IsValid: true })
                .ToDictionary(p => p.Key, p => p.Value) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    /// <summary>Encodes with ordinal key order for stable files.</summary>
    /// <param name="storage">State.</param>
    /// <returns>JSON bytes.</returns>
    internal static byte[] Encode(IReadOnlyDictionary<string, FirstRunSeenRecord> storage)
    {
        var sorted = new SortedDictionary<string, FirstRunSeenRecord>(storage.ToDictionary(), StringComparer.Ordinal);
        return JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, FirstRunSeenRecord>(sorted), FirstRunJsonContext.Default.DictionaryStringFirstRunSeenRecord);
    }

    /// <summary>Caps the record count, keeping the most recently seen.</summary>
    /// <param name="storage">Candidate state.</param>
    /// <returns>At most <see cref="MaxRecords"/> records.</returns>
    private static IReadOnlyDictionary<string, FirstRunSeenRecord> Bounded(IReadOnlyDictionary<string, FirstRunSeenRecord> storage) =>
        storage.Count <= MaxRecords ? storage
            : storage.OrderByDescending(p => p.Value.SeenAt).Take(MaxRecords).ToDictionary(p => p.Key, p => p.Value);
}
#endregion
