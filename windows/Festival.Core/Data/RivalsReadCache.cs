namespace Festival.Core.Data;

#region Rivals read cache
/// <summary>
/// Bounded, process-only cache of in-flight and completed Rivals reads, keyed by request. Concurrent callers share
/// one request (the hub's Common Rivals section reuses the per-instrument lists), completed values live for the
/// service's own <c>max-age</c> (120 s), and failures are never cached. Online-only: nothing touches disk.
/// While the service answers 503 for a public-read freeze (a detail it has no published copy of), the last good value
/// of the same request is served for up to <see cref="StaleGrace"/>, like the web, whose query cache keeps showing a
/// rival it already loaded when a refetch fails during publication (batch 7.13).
/// </summary>
/// <param name="time">Clock.</param>
/// <param name="lifetime">How long a completed read is reused.</param>
/// <param name="capacity">Entry limit; the oldest entry is evicted first.</param>
public sealed class RivalsReadCache(TimeProvider time, TimeSpan? lifetime = null, int capacity = 64)
{
    /// <summary>How long a last good value may stand in for a frozen read (web <c>REMOTE_DATA_GC_TIME_MS</c>, 10 min).</summary>
    public static readonly TimeSpan StaleGrace = TimeSpan.FromMinutes(10);

    private readonly TimeSpan lifetime = lifetime ?? TimeSpan.FromSeconds(120);
    private readonly Dictionary<string, (DateTimeOffset Created, Task Task)> entries = new(StringComparer.Ordinal);
    private readonly LinkedList<string> order = new();
    private readonly Dictionary<string, (DateTimeOffset Loaded, object? Value)> lastGood = new(StringComparer.Ordinal);
    private readonly LinkedList<string> lastGoodOrder = new();
    private readonly Lock gate = new();

    /// <summary>Number of entries (including in-flight reads).</summary>
    public int Count
    {
        get { lock (gate) return entries.Count; }
    }

    /// <summary>Returns a shared read for <paramref name="key"/>, starting it when absent or expired.</summary>
    /// <typeparam name="T">Result type.</typeparam>
    /// <param name="key">Request key (include the account and every parameter).</param>
    /// <param name="load">Starts the read; it runs uncancelled so other callers can share it.</param>
    /// <param name="cancellationToken">Cancels only this caller's wait.</param>
    /// <returns>The result.</returns>
    public async Task<T> GetAsync<T>(string key, Func<Task<T>> load, CancellationToken cancellationToken = default)
    {
        Task<T> task;
        lock (gate)
        {
            if (entries.TryGetValue(key, out var entry) && entry.Task is Task<T> existing &&
                (!existing.IsCompleted || time.GetUtcNow() - entry.Created < lifetime))
            {
                task = existing;
            }
            else
            {
                task = load();
                if (entries.ContainsKey(key)) order.Remove(key);
                entries[key] = (time.GetUtcNow(), task);
                order.AddLast(key);
                while (entries.Count > capacity)
                {
                    entries.Remove(order.First!.Value);
                    order.RemoveFirst();
                }
            }
        }
        T value;
        try
        {
            value = await task.WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (FestivalApiException error) when (task.IsFaulted && IsFrozen(error) && Stale<T>(key) is { } stale)
        {
            Forget(key, task);
            return stale.Item1;
        }
        catch (Exception) when (task.IsFaulted || task.IsCanceled)
        {
            Forget(key, task);
            throw;
        }
        Remember(key, value);
        return value;
    }

    /// <summary>Whether a failure is the service holding reads during publication or maintenance (HTTP 503).</summary>
    /// <param name="error">Failure.</param>
    /// <returns><see langword="true"/> for a freeze or an unavailable published response.</returns>
    private static bool IsFrozen(FestivalApiException error) =>
        error.Kind is FestivalApiErrorKind.PublicReadFrozen or FestivalApiErrorKind.Unavailable;

    /// <summary>The last good value for a key while it is within <see cref="StaleGrace"/>.</summary>
    /// <typeparam name="T">Result type.</typeparam>
    /// <param name="key">Request key.</param>
    /// <returns>The value in a box, or <see langword="null"/>.</returns>
    private Tuple<T>? Stale<T>(string key)
    {
        lock (gate)
        {
            return lastGood.TryGetValue(key, out var good) && good.Value is T value && time.GetUtcNow() - good.Loaded <= StaleGrace
                ? Tuple.Create(value) : null;
        }
    }

    /// <summary>Records a successful value as the freeze fallback for its key (bounded like the live entries).</summary>
    /// <typeparam name="T">Result type.</typeparam>
    /// <param name="key">Request key.</param>
    /// <param name="value">Value.</param>
    private void Remember<T>(string key, T value)
    {
        lock (gate)
        {
            if (lastGood.ContainsKey(key)) lastGoodOrder.Remove(key);
            lastGood[key] = (time.GetUtcNow(), value);
            lastGoodOrder.AddLast(key);
            while (lastGood.Count > capacity)
            {
                lastGood.Remove(lastGoodOrder.First!.Value);
                lastGoodOrder.RemoveFirst();
            }
        }
    }

    /// <summary>
    /// Drops every live entry (player switch or explicit refresh) so the next read goes to the service; last good values
    /// stay as the freeze fallback (keys carry the account, so they never apply to another player).
    /// </summary>
    public void Clear()
    {
        lock (gate)
        {
            entries.Clear();
            order.Clear();
        }
    }

    /// <summary>Removes a failed entry unless it was already replaced.</summary>
    /// <param name="key">Key.</param>
    /// <param name="task">Failed task.</param>
    private void Forget(string key, Task task)
    {
        lock (gate)
        {
            if (entries.TryGetValue(key, out var entry) && ReferenceEquals(entry.Task, task))
            {
                entries.Remove(key);
                order.Remove(key);
            }
        }
    }
}
#endregion
