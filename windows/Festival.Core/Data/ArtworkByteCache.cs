namespace Festival.Core.Data;

#region Artwork byte cache
/// <summary>
/// The one bounded, process-only album-art byte cache. Concurrent requests for the same URL share one
/// download; everything is dropped on a publication change. Art is never written to disk.
/// </summary>
public sealed class ArtworkByteCache
{
    private readonly Func<Uri, CancellationToken, Task<byte[]>> download;
    private readonly int maxEntries;
    private readonly long maxBytes;
    private readonly LinkedList<(Uri Url, byte[] Bytes)> order = new();
    private readonly Dictionary<Uri, LinkedListNode<(Uri Url, byte[] Bytes)>> map = [];
    private readonly Dictionary<Uri, Task<byte[]>> inFlight = [];
    private readonly Lock gate = new();
    private long bytes;
    private int generation;

    /// <summary>Creates the cache.</summary>
    /// <param name="download">Downloader, normally <see cref="FestivalApiClient.GetArtworkBytesAsync"/>.</param>
    /// <param name="maxEntries">Entry limit.</param>
    /// <param name="maxBytes">Byte limit.</param>
    public ArtworkByteCache(Func<Uri, CancellationToken, Task<byte[]>> download, int maxEntries = 96, long maxBytes = 24_000_000)
    {
        this.download = download;
        this.maxEntries = maxEntries;
        this.maxBytes = maxBytes;
    }

    /// <summary>Total cached bytes.</summary>
    public long Bytes
    {
        get { lock (gate) return bytes; }
    }

    /// <summary>Returns cached bytes or downloads them once.</summary>
    /// <param name="url">Artwork URL.</param>
    /// <param name="cancellationToken">Cancels only this caller's wait.</param>
    /// <returns>Image bytes.</returns>
    public async Task<byte[]> GetAsync(Uri url, CancellationToken cancellationToken = default)
    {
        Task<byte[]> task;
        int observed;
        lock (gate)
        {
            if (map.TryGetValue(url, out var node))
            {
                order.Remove(node);
                order.AddLast(node);
                return node.Value.Bytes;
            }
            observed = generation;
            if (!inFlight.TryGetValue(url, out task!))
            {
                task = download(url, CancellationToken.None);
                inFlight[url] = task;
            }
        }
        try
        {
            var data = await task.WaitAsync(cancellationToken).ConfigureAwait(false);
            lock (gate)
            {
                if (generation == observed) Remember(url, data);
            }
            return data;
        }
        finally
        {
            if (task.IsCompleted)
            {
                lock (gate)
                {
                    if (inFlight.TryGetValue(url, out var current) && current == task) inFlight.Remove(url);
                }
            }
        }
    }

    /// <summary>Drops all bytes (publication change or memory pressure).</summary>
    public void Clear()
    {
        lock (gate)
        {
            generation++;
            map.Clear();
            order.Clear();
            inFlight.Clear();
            bytes = 0;
        }
    }

    /// <summary>Stores bytes under the limits (caller holds the lock).</summary>
    /// <param name="url">Key.</param>
    /// <param name="data">Bytes.</param>
    private void Remember(Uri url, byte[] data)
    {
        if (map.ContainsKey(url) || data.Length > maxBytes) return;
        map[url] = order.AddLast((url, data));
        bytes += data.Length;
        while (map.Count > maxEntries || bytes > maxBytes)
        {
            var oldest = order.First!;
            order.RemoveFirst();
            map.Remove(oldest.Value.Url);
            bytes -= oldest.Value.Bytes.Length;
        }
    }
}
#endregion
