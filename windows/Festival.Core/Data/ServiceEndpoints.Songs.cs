namespace Festival.Core.Data;

#region Songs-lane endpoints
/// <summary>Item Shop and CHOpt path URLs.</summary>
public static partial class ServiceEndpoints
{
    /// <summary><c>GET /api/shop</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <returns>Endpoint URL.</returns>
    public static Uri Shop(Uri baseUri) => Build(baseUri, ["api", "shop"]);

    /// <summary><c>GET /api/paths/{song}/{instrument}/{difficulty}[/data][?generationId=]</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="songId">Catalogue song ID.</param>
    /// <param name="instrument">Path-capable chart (Karaoke has no paths).</param>
    /// <param name="difficulty">Difficulty.</param>
    /// <param name="text"><see langword="true"/> for the structured <c>/data</c> JSON, otherwise the PNG.</param>
    /// <param name="generationId">Optional artifact revision (1–200 safe characters).</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri Path(Uri baseUri, string songId, Instrument instrument, PathDifficulty difficulty, bool text, string? generationId = null)
    {
        RequireSegment(songId);
        if (!instrument.HasPaths() || !Enum.IsDefined(difficulty) ||
            (generationId is not null && (generationId.Length is 0 or > 200 || ProfileText.ContainsUnsafeCharacter(generationId))))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        string[] segments = text
            ? ["api", "paths", songId, instrument.ServiceId(), difficulty.WireName(), "data"]
            : ["api", "paths", songId, instrument.ServiceId(), difficulty.WireName()];
        return Build(baseUri, segments, generationId is null ? null : [("generationId", generationId)]);
    }
}
#endregion
