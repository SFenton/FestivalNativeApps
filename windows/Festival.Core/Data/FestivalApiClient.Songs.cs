namespace Festival.Core.Data;

#region Songs-lane reads
/// <summary>Item Shop and CHOpt path reads (publication-bound, keyless, bounded).</summary>
public sealed partial class FestivalApiClient
{
    /// <summary>Largest accepted Shop body.</summary>
    internal const int ShopByteLimit = 4_000_000;

    /// <summary>Largest accepted path JSON body.</summary>
    internal const int PathDataByteLimit = 8_000_000;

    /// <summary>Reads and validates the public Item Shop feed.</summary>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated offers.</returns>
    public Task<ShopResponse> GetShopAsync(CancellationToken cancellationToken = default) =>
        ReadParsedAsync(ServiceEndpoints.Shop(BaseUri), ShopByteLimit, ParseShop, cancellationToken);

    /// <summary>Reads and validates structured CHOpt path text for one chart and difficulty.</summary>
    /// <param name="songId">Catalogue song.</param>
    /// <param name="instrument">Path-capable chart (not Karaoke).</param>
    /// <param name="difficulty">Difficulty.</param>
    /// <param name="generationId">Catalogue <c>pathArtifactGenerationId</c>, if any.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated path data.</returns>
    public Task<SongPathData> GetPathDataAsync(
        string songId, Instrument instrument, PathDifficulty difficulty, string? generationId = null,
        CancellationToken cancellationToken = default) =>
        ReadParsedAsync(ServiceEndpoints.Path(BaseUri, songId, instrument, difficulty, text: true, generationId), PathDataByteLimit,
            bytes => ParsePathData(bytes, difficulty), cancellationToken);

    /// <summary>Reads a bounded CHOpt path PNG (validated before any decode).</summary>
    /// <param name="songId">Catalogue song.</param>
    /// <param name="instrument">Path-capable chart (not Karaoke).</param>
    /// <param name="difficulty">Difficulty.</param>
    /// <param name="generationId">Catalogue <c>pathArtifactGenerationId</c>, if any.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>PNG bytes with their validated pixel size.</returns>
    public Task<PathImage> GetPathImageAsync(
        string songId, Instrument instrument, PathDifficulty difficulty, string? generationId = null,
        CancellationToken cancellationToken = default) =>
        ReadParsedAsync(ServiceEndpoints.Path(BaseUri, songId, instrument, difficulty, text: false, generationId), PathImageValidation.MaxBytes,
            ParsePathImage, cancellationToken);

    /// <summary>Decodes and validates a Shop body.</summary>
    /// <param name="bytes">Body.</param>
    /// <returns>Validated feed.</returns>
    internal static ShopResponse ParseShop(byte[] bytes)
    {
        var shop = Decode(bytes, SongsJsonContext.Default.ShopResponse);
        shop.Validate();
        return shop;
    }

    /// <summary>Decodes and validates a path JSON body.</summary>
    /// <param name="bytes">Body.</param>
    /// <param name="difficulty">Requested difficulty.</param>
    /// <returns>Validated path.</returns>
    internal static SongPathData ParsePathData(byte[] bytes, PathDifficulty difficulty)
    {
        var path = Decode(bytes, SongsJsonContext.Default.SongPathData);
        path.Validate(difficulty);
        return path;
    }

    /// <summary>Validates a path PNG's header and size.</summary>
    /// <param name="bytes">Body.</param>
    /// <returns>Image with its pixel size.</returns>
    internal static PathImage ParsePathImage(byte[] bytes)
    {
        var (width, height) = PathImageValidation.Dimensions(bytes);
        return new PathImage(bytes, width, height);
    }

    /// <summary>Pinned read followed by a parse step.</summary>
    /// <typeparam name="T">Parsed type.</typeparam>
    /// <param name="url">Allowlisted URL.</param>
    /// <param name="maxBytes">Largest accepted body.</param>
    /// <param name="parse">Decode-and-validate step.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Parsed value.</returns>
    private async Task<T> ReadParsedAsync<T>(Uri url, int maxBytes, Func<byte[], T> parse, CancellationToken cancellationToken) =>
        parse(await ReadPinnedAsync(url, maxBytes, cancellationToken).ConfigureAwait(false));
}

/// <summary>A validated path PNG.</summary>
/// <param name="Bytes">PNG bytes.</param>
/// <param name="Width">Pixel width.</param>
/// <param name="Height">Pixel height.</param>
public sealed record PathImage(byte[] Bytes, int Width, int Height);
#endregion
