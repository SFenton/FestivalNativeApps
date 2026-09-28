using System.Globalization;
using System.Text.Json;

namespace Festival.Core.Data;

#region Notifications read
/// <summary>
/// Notifications read, kept outside <see cref="FestivalApiClient"/> (an extension rather than a partial class, so
/// coverlet attributes its lines to this file and the coverage gate sees it).
/// </summary>
public static class NotificationsApi
{
    /// <summary>Default and largest notification page sizes (service clamps to 1–200).</summary>
    public const int DefaultNotificationLimit = 50, MaxNotificationLimit = 200;

    /// <summary>
    /// Reads one player's improvement feed: <c>GET /api/player/{accountId}/notifications?limit=</c>. A pure, keyless,
    /// publication-classified read (one <c>SELECT</c>, <c>ImprovementNotificationService.GetPlayerNotifications</c>);
    /// an unknown account gets an empty envelope, not a 404. Never sends selected-profile headers.
    /// </summary>
    /// <param name="client">Service client.</param>
    /// <param name="accountId">Validated account.</param>
    /// <param name="limit">Rows, 1–200.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated envelope.</returns>
    /// <exception cref="FestivalApiException">Invalid parameters, transport or wire failures.</exception>
    public static Task<ImprovementNotificationsEnvelope> GetPlayerNotificationsAsync(
        this FestivalApiClient client, string accountId, int limit = DefaultNotificationLimit, CancellationToken cancellationToken = default)
    {
        if (!ProfileText.IsValidAccountId(accountId) || limit is < 1 or > MaxNotificationLimit)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        var url = ServiceEndpoints.Build(client.BaseUri, ["api", "player", accountId, "notifications"],
            [("limit", limit.ToString(CultureInfo.InvariantCulture))]);
        return ReadAsync(client, url, limit, cancellationToken);
    }

    /// <summary>Decodes and validates an envelope body.</summary>
    /// <param name="bytes">Body.</param>
    /// <param name="limit">Requested row cap.</param>
    /// <returns>Validated envelope.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    internal static ImprovementNotificationsEnvelope Decode(byte[] bytes, int limit)
    {
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

    /// <summary>Performs the pinned read.</summary>
    /// <param name="client">Client.</param>
    /// <param name="url">Endpoint.</param>
    /// <param name="limit">Row cap.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Envelope.</returns>
    private static async Task<ImprovementNotificationsEnvelope> ReadAsync(FestivalApiClient client, Uri url, int limit, CancellationToken cancellationToken) =>
        Decode(await client.ReadPinnedAsync(url, 4_000_000, cancellationToken).ConfigureAwait(false), limit);
}
#endregion
