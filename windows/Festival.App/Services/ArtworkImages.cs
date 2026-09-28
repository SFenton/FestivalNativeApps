using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;

namespace Festival.App.Services;

#region Artwork images
/// <summary>
/// Decodes album art for rows and headers at display size, backed by the session's bounded byte cache
/// and a small decoded-thumbnail LRU. Nothing is written to disk (no <c>UriSource</c>, which would use the
/// system HTTP cache).
/// </summary>
internal static class ArtworkImages
{
    private const int MaxDecoded = 160;
    private static readonly LinkedList<(string Key, BitmapImage Image)> Order = new();
    private static readonly Dictionary<string, LinkedListNode<(string Key, BitmapImage Image)>> Map = [];

    /// <summary>Drops decoded images (publication change).</summary>
    public static void Clear()
    {
        Map.Clear();
        Order.Clear();
    }

    /// <summary>Loads and decodes art for a song reference at a pixel width. UI thread only.</summary>
    /// <param name="raw">Song <c>albumArt</c>.</param>
    /// <param name="decodeWidth">Decode width in physical pixels.</param>
    /// <param name="cancellationToken">Cancellation when the row is recycled.</param>
    /// <returns>Image, or <see langword="null"/> when absent or failed (logged, never substituted).</returns>
    public static async Task<BitmapImage?> LoadAsync(string? raw, int decodeWidth, CancellationToken cancellationToken)
    {
        var session = App.Session;
        if (session.Api.ArtworkUri(raw) is not { } url) return null;
        var key = $"{url.AbsoluteUri}@{decodeWidth}";
        if (Map.TryGetValue(key, out var node))
        {
            Order.Remove(node);
            Order.AddLast(node);
            return node.Value.Image;
        }
        try
        {
            var bytes = await session.Artwork.GetAsync(url, cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            var image = new BitmapImage { DecodePixelWidth = decodeWidth, DecodePixelType = DecodePixelType.Physical };
            using var stream = new InMemoryRandomAccessStream();
            await stream.WriteAsync(bytes.AsBuffer());
            stream.Seek(0);
            await image.SetSourceAsync(stream);
            Remember(key, image);
            return image;
        }
        catch (Exception error) when (error is FestivalApiException or OperationCanceledException or System.Runtime.InteropServices.COMException)
        {
            if (error is not OperationCanceledException) System.Diagnostics.Debug.WriteLine($"Artwork failed: {error.Message}");
            return null;
        }
    }

    /// <summary>Stores a decoded image under the LRU limit.</summary>
    /// <param name="key">URL and size.</param>
    /// <param name="image">Decoded image.</param>
    private static void Remember(string key, BitmapImage image)
    {
        if (Map.ContainsKey(key)) return;
        Map[key] = Order.AddLast((key, image));
        while (Map.Count > MaxDecoded)
        {
            Map.Remove(Order.First!.Value.Key);
            Order.RemoveFirst();
        }
    }
}
#endregion
