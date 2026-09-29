namespace Festival.Core.Data;

#region Service info reads
/// <summary>
/// Operational, unpinned reads used by Settings. Both are pure (see <c>.agents/platforms/service-safety.md</c>):
/// <c>/api/service-info</c> runs one <c>SELECT</c> plus in-process progress; <c>/api/version</c> reads assembly metadata.
/// Neither is publication-bound, so neither sends the pin header nor answers a freeze 503.
/// </summary>
public sealed partial class FestivalApiClient
{
    /// <summary>Reads live scrape, worker and publication state for the Service Info card.</summary>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Decoded state plus any freeze header.</returns>
    /// <exception cref="FestivalApiException">Transport, status or a body without <c>currentUpdate.status</c>.</exception>
    public async Task<ServiceInfoSnapshot> GetServiceInfoAsync(CancellationToken cancellationToken = default)
    {
        using var request = RequestGate.CreateGet(ServiceEndpoints.Build(BaseUri, ["api", "service-info"]));
        var response = await gate.SendAsync(request, 1_000_000, cancellationToken).ConfigureAwait(false);
        RequestGate.MapStatus(response, acceptsSyncing: false);
        var info = Decode(response.Body, ServiceInfoJsonContext.Default.ServiceInfo);
        if (info.CurrentUpdate?.Status is not { Length: > 0 })
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse, response.Status);
        return new ServiceInfoSnapshot(info, response.Header(ServiceFreezeReason.Header));
    }

    /// <summary>Reads the service build version for Settings → Version.</summary>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Short printable version string.</returns>
    /// <exception cref="FestivalApiException">Transport, status, or an empty, oversized or non-printable value.</exception>
    public async Task<string> GetServiceVersionAsync(CancellationToken cancellationToken = default)
    {
        using var request = RequestGate.CreateGet(ServiceEndpoints.Build(BaseUri, ["api", "version"]));
        var response = await gate.SendAsync(request, 16_000, cancellationToken).ConfigureAwait(false);
        RequestGate.MapStatus(response, acceptsSyncing: false);
        var value = Decode(response.Body, ServiceInfoJsonContext.Default.ServiceVersionBody).Version?.Trim() ?? "";
        if (value.Length is 0 or > 64 || value.Any(c => c is < ' ' or > '~'))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse, response.Status);
        return value;
    }
}
#endregion
