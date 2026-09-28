using System.Globalization;
using System.Text.Json;

namespace Festival.Core.Data;

#region Notifications read
public sealed partial class FestivalApiClient
{
    /// <summary>Default and largest notification page sizes (service clamps to 1–200).</summary>
    public const int DefaultNotificationLimit = 50, MaxNotificationLimit = 200;

    /// <summary>
    /// Reads one player's improvement feed: <c>GET /api/player/{accountId}/notifications?limit=</c>. A pure, keyless,
    /// publication-classified read (one <c>SELECT</c>, <c>ImprovementNotificationService.GetPlayerNotifications</c>);
    /// an unknown account gets an empty envelope, not a 404. Never sends selected-profile headers.
    /// </summary>
    /// <param name="accountId">Validated account.</param>
    /// <param name="limit">Rows, 1–200.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated envelope.</returns>
    /// <exception cref="FestivalApiException">Invalid parameters, transport or wire failures.</exception>
    public async Task<ImprovementNotificationsEnvelope> GetPlayerNotificationsAsync(
        string accountId, int limit = DefaultNotificationLimit, CancellationToken cancellationToken = default)
    {
        if (!ProfileText.IsValidAccountId(accountId) || limit is < 1 or > MaxNotificationLimit)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        var url = ServiceEndpoints.Build(BaseUri, ["api", "player", accountId, "notifications"],
            [("limit", limit.ToString(CultureInfo.InvariantCulture))]);
        var bytes = await ReadPinnedAsync(url, 4_000_000, cancellationToken).ConfigureAwait(false);
        ImprovementNotificationsEnvelope envelope;
        try
        {
            envelope = JsonSerializer.Deserialize(bytes, NotificationsJsonContext.Default.ImprovementNotificationsEnvelope)
                ?? throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        }
        catch (JsonException error)
        {
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse, inner: error);
        }
        envelope.Validate(limit);
        return envelope;
    }
}
#endregion
