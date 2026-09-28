using System.Text.Json;

namespace Festival.Core.Data;

#region Notification seen store
/// <summary>
/// Seen notification GUIDs per account (the native simplification of web <c>notificationSeenState.ts</c>): each account's
/// list is pruned to the IDs still in its latest feed plus the newest seen, bounded, and corrupt data reads as empty.
/// </summary>
/// <param name="blob">Backing blob (<c>notifications-seen.json</c> in the app).</param>
public sealed class NotificationSeenStore(IBlobStore blob)
{
    /// <summary>Most GUIDs kept per account.</summary>
    public const int MaxPerAccount = 400;

    /// <summary>Most accounts kept.</summary>
    public const int MaxAccounts = 20;

    /// <summary>Default file.</summary>
    public static string DefaultPath { get; } = Path.Combine(FileBlobStore.AppDataFolder, "notifications-seen.json");

    private readonly Lock gate = new();

    /// <summary>Seen GUIDs for an account.</summary>
    /// <param name="accountId">Account.</param>
    /// <returns>Seen set.</returns>
    public IReadOnlySet<string> Seen(string accountId)
    {
        lock (gate) return Decode(blob.Read()).TryGetValue(accountId, out var ids) ? ids.ToHashSet(StringComparer.Ordinal) : [];
    }

    /// <summary>Marks GUIDs seen (idempotent), keeping only IDs still in the current feed when given.</summary>
    /// <param name="accountId">Account.</param>
    /// <param name="ids">GUIDs to mark.</param>
    /// <param name="currentFeed">IDs in the latest feed, to prune expired ones; <see langword="null"/> keeps all.</param>
    public void MarkSeen(string accountId, IEnumerable<string> ids, IEnumerable<string>? currentFeed = null)
    {
        lock (gate)
        {
            var all = Decode(blob.Read());
            var existing = all.GetValueOrDefault(accountId) ?? [];
            var feed = currentFeed?.ToHashSet(StringComparer.Ordinal);
            var merged = existing.Concat(ids).Where(id => feed is null || feed.Contains(id)).Distinct(StringComparer.Ordinal).ToList();
            if (merged.Count > MaxPerAccount) merged = merged[^MaxPerAccount..];
            if (merged.SequenceEqual(existing)) return;
            // Rebuilt (not mutated) so insertion order stays "least recently marked first" for eviction.
            var next = all.Where(p => p.Key != accountId).Append(KeyValuePair.Create(accountId, merged))
                .TakeLast(MaxAccounts).ToDictionary();
            blob.Write(JsonSerializer.SerializeToUtf8Bytes(next, NotificationsJsonContext.Default.DictionaryStringListString));
        }
    }

    /// <summary>Decodes, dropping malformed entries.</summary>
    /// <param name="bytes">Stored bytes.</param>
    /// <returns>Account → GUIDs (insertion order = recency).</returns>
    private static Dictionary<string, List<string>> Decode(byte[]? bytes)
    {
        if (bytes is not { Length: > 0 and <= 512 * 1024 }) return [];
        try
        {
            var raw = JsonSerializer.Deserialize(bytes, NotificationsJsonContext.Default.DictionaryStringListString) ?? [];
            return raw.Where(p => ProfileText.IsValidAccountId(p.Key) && p.Value is not null)
                .ToDictionary(p => p.Key, p => p.Value.Where(id => id is { Length: > 0 and <= 64 }).ToList());
        }
        catch (JsonException)
        {
            return [];
        }
    }
}
#endregion
