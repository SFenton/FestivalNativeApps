namespace Festival.Core.Data;

#region Rivals read cache
/// <summary>
/// Bounded, process-only cache of in-flight and completed Rivals reads, keyed by request. Concurrent callers share
/// one request (the hub's Common Rivals section reuses the per-instrument lists), completed values live for the
/// service's own <c>max-age</c> (120 s), and failures are never cached. Online-only: nothing touches disk.
/// </summary>
/// <param name="time">Clock.</param>
/// <param name="lifetime">How long a completed read is reused.</param>
/// <param name="capacity">Entry limit; the oldest entry is evicted first.</param>
public sealed class RivalsReadCache(TimeProvider time, TimeSpan? lifetime = null, int capacity = 64)
{
    private readonly TimeSpan lifetime = lifetime ?? TimeSpan.FromSeconds(120);
    private readonly Dictionary<string, (DateTimeOffset Created, Task Task)> entries = new(StringComparer.Ordinal);
    private readonly LinkedList<string> order = new();
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
        try
        {
            return await task.WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception) when (task.IsFaulted || task.IsCanceled)
        {
            Forget(key, task);
            throw;
        }
    }

    /// <summary>Drops every entry (player switch or explicit refresh).</summary>
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
