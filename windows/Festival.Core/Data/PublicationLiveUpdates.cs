using System.Buffers;
using System.Globalization;
using System.Net.WebSockets;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace Festival.Core.Data;

#region Message
/// <summary>
/// One server message on the public <c>/api/ws</c> socket, reduced to what the app acts on. The web's
/// <c>useAppWebSocket.ts</c> holds one anonymous socket to <c>/api/ws?publicationId=N</c> and re-reads
/// <c>/api/publication</c> when the server sends <c>{"type":"publication_changed"}</c>. Everything else (the
/// <c>shop_snapshot</c> sent on connect, Shop rotation, account sync messages an anonymous socket never receives) is
/// ignored; the app keeps reading the Item Shop over HTTPS. Same reduction as Apple <c>PublicationLiveMessage</c> (#304).
/// </summary>
/// <param name="IsPublicationChanged">Whether the frame is a <c>publication_changed</c> object.</param>
/// <param name="PublicationId">The positive generation the server named, if any.</param>
public readonly record struct PublicationLiveMessage(bool IsPublicationChanged, long? PublicationId)
{
    /// <summary>Decodes one frame without trusting its shape.</summary>
    /// <param name="frame">UTF-8 JSON frame bytes.</param>
    /// <returns>A publication change, or a message that is ignored.</returns>
    public static PublicationLiveMessage Parse(ReadOnlySpan<byte> frame)
    {
        try
        {
            var reader = new Utf8JsonReader(frame);
            using var document = JsonDocument.ParseValue(ref reader);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("type", out var type) ||
                type.ValueKind != JsonValueKind.String || type.GetString() != "publication_changed")
                return default;
            long? id = root.TryGetProperty("publicationId", out var value) && value.ValueKind == JsonValueKind.Number &&
                       value.TryGetInt64(out var number) && number > 0 ? number : null;
            return new PublicationLiveMessage(true, id);
        }
        catch (JsonException)
        {
            return default;
        }
    }
}
#endregion

#region Backoff
/// <summary>Reconnect delays matching the web socket: 1 s, doubling, at most 30 s; reset once a connection opens.</summary>
public struct PublicationLiveBackoff
{
    /// <summary>First reconnect delay (web <c>RECONNECT_BASE_MS</c>).</summary>
    public static readonly TimeSpan Initial = TimeSpan.FromSeconds(1);

    /// <summary>Longest reconnect delay (web <c>RECONNECT_MAX_MS</c>).</summary>
    public static readonly TimeSpan Maximum = TimeSpan.FromSeconds(30);

    private TimeSpan nextDelay;

    /// <summary>The delay before the next attempt; the one after it doubles, up to <see cref="Maximum"/>.</summary>
    /// <returns>The current delay.</returns>
    public TimeSpan Next()
    {
        var delay = nextDelay == TimeSpan.Zero ? Initial : nextDelay;
        nextDelay = delay * 2 > Maximum ? Maximum : delay * 2;
        return delay;
    }

    /// <summary>A connection opened: the next failure retries after <see cref="Initial"/> again.</summary>
    public void Reset() => nextDelay = Initial;
}
#endregion

#region Socket
/// <summary>What a live socket reports to <see cref="PublicationLiveUpdates.RunAsync"/>.</summary>
/// <param name="Opened">Whether this is the handshake-completed event (otherwise a frame).</param>
/// <param name="Frame">One complete text or binary frame.</param>
public readonly record struct PublicationSocketEvent(bool Opened, ReadOnlyMemory<byte> Frame)
{
    /// <summary>The WebSocket handshake completed.</summary>
    public static PublicationSocketEvent Open { get; } = new(true, ReadOnlyMemory<byte>.Empty);

    /// <summary>One frame.</summary>
    /// <param name="frame">Frame bytes.</param>
    /// <returns>Event.</returns>
    public static PublicationSocketEvent Message(ReadOnlyMemory<byte> frame) => new(false, frame);
}

/// <summary>Opens the public live socket. Injectable so the loop is testable without a network.</summary>
public interface IPublicationLiveSocket
{
    /// <summary>
    /// Connects and reports events until the server closes (the sequence ends) or the connection fails (it throws).
    /// Cancelling, or disposing the enumerator, closes the socket.
    /// </summary>
    /// <param name="uri">The <c>wss://…/api/ws?publicationId=N</c> URL.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The connection's events.</returns>
    IAsyncEnumerable<PublicationSocketEvent> ConnectAsync(Uri uri, CancellationToken cancellationToken);
}

/// <summary>
/// The production socket: a <see cref="ClientWebSocket"/> that only receives. It sends no data frames and no custom
/// headers, cookies or credentials: never an <c>X-API-Key</c>, never a selected-profile header and never
/// <c>subscribe_sync</c>, which binds a socket to an account. Like a browser it sends no keep-alive frames of its own (it
/// still answers the server's pings). The service registers an anonymous connection in memory only
/// (<c>.agents/platforms/service-safety.md</c>, <c>/api/ws</c>).
/// </summary>
public sealed class ClientWebSocketPublicationLiveSocket : IPublicationLiveSocket
{
    /// <summary>Largest accepted frame: the connect-time <c>shop_snapshot</c> is ~35 KB today, with room for a larger Shop.</summary>
    public const int MaximumMessageSize = 8_000_000;

    /// <summary>How long a close handshake may take before the socket is aborted.</summary>
    private static readonly TimeSpan CloseTimeout = TimeSpan.FromSeconds(2);

    /// <inheritdoc />
    public async IAsyncEnumerable<PublicationSocketEvent> ConnectAsync(Uri uri,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        if (uri.Scheme != "wss" && !(uri.Scheme == "ws" && uri.IsLoopback))
            throw new FestivalApiException(FestivalApiErrorKind.InsecureBaseUrl);
        using var socket = new ClientWebSocket();
        socket.Options.KeepAliveInterval = TimeSpan.Zero;
        socket.Options.Cookies = null;
        socket.Options.UseDefaultCredentials = false;
        await socket.ConnectAsync(uri, cancellationToken).ConfigureAwait(false);
        try
        {
            yield return PublicationSocketEvent.Open;
            var buffer = new ArrayBufferWriter<byte>(16 * 1024);
            while (true)
            {
                buffer.Clear();
                ValueWebSocketReceiveResult result;
                do
                {
                    if (buffer.WrittenCount >= MaximumMessageSize) throw new WebSocketException(WebSocketError.Faulted);
                    result = await socket.ReceiveAsync(buffer.GetMemory(16 * 1024), cancellationToken).ConfigureAwait(false);
                    if (result.MessageType == WebSocketMessageType.Close) yield break;
                    buffer.Advance(result.Count);
                }
                while (!result.EndOfMessage);
                yield return PublicationSocketEvent.Message(buffer.WrittenMemory.ToArray());
            }
        }
        finally
        {
            await CloseQuietlyAsync(socket).ConfigureAwait(false);
        }
    }

    /// <summary>Ends the connection with a "going away" close, or aborts it when the handshake can't finish.</summary>
    /// <param name="socket">Socket.</param>
    /// <returns>Close task.</returns>
    private static async Task CloseQuietlyAsync(ClientWebSocket socket)
    {
        if (socket.State is not (WebSocketState.Open or WebSocketState.CloseReceived))
        {
            socket.Abort();
            return;
        }
        using var timeout = new CancellationTokenSource(CloseTimeout);
        try
        {
            await socket.CloseOutputAsync(WebSocketCloseStatus.EndpointUnavailable, null, timeout.Token).ConfigureAwait(false);
        }
        catch (Exception error) when (error is WebSocketException or OperationCanceledException or ObjectDisposedException)
        {
            socket.Abort();
        }
    }
}
#endregion

#region URL
public sealed partial class FestivalApiClient
{
    /// <summary>Whether this client reads a loopback fixture server rather than the public service.</summary>
    public bool UsesLoopbackOrigin => BaseUri.IsLoopback;

    /// <summary>
    /// The public live socket for this client's origin: <c>wss</c> for HTTPS, <c>ws</c> only for a loopback fixture server.
    /// The query carries only the generation the app shows.
    /// </summary>
    /// <param name="publicationId">Current generation.</param>
    /// <returns><c>…/api/ws?publicationId=N</c>.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public Uri LiveUpdatesUri(long publicationId)
    {
        if (publicationId <= 0) throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        var scheme = BaseUri.Scheme switch
        {
            "https" => "wss",
            "http" when UsesLoopbackOrigin => "ws",
            _ => throw new FestivalApiException(FestivalApiErrorKind.InvalidResource),
        };
        var http = ServiceEndpoints.Build(BaseUri, ["api", "ws"],
            [("publicationId", publicationId.ToString(CultureInfo.InvariantCulture))]);
        return new UriBuilder(http) { Scheme = scheme, Port = http.IsDefaultPort ? -1 : http.Port }.Uri;
    }
}
#endregion

#region Loop
/// <summary>The live publication loop, like the web's <c>useAppWebSocket</c> and Apple <c>PublicationLiveUpdates</c>.</summary>
public static class PublicationLiveUpdates
{
    /// <summary>
    /// Keeps a live socket open until <paramref name="cancellationToken"/> is cancelled. Each round re-reads the
    /// publication (<paramref name="refresh"/>, which also lets the app observe a new generation), then connects with that
    /// generation. A <c>publication_changed</c> message starts the next round at once, so the app refreshes with no user
    /// action. A closed or failed connection waits <see cref="PublicationLiveBackoff"/> first (reset after a connection that
    /// opened). A second <c>publication_changed</c> for a generation that did not advance also waits, without resetting the
    /// backoff, so a misbehaving server cannot cause a tight loop.
    /// </summary>
    /// <param name="refresh">Re-reads <c>/api/publication</c> and returns the observed generation.</param>
    /// <param name="uri">Builds the socket URL for a generation.</param>
    /// <param name="socket">Opens the socket.</param>
    /// <param name="delay">Waits between attempts; throws when cancelled.</param>
    /// <param name="cancellationToken">Stops the loop.</param>
    /// <returns>A task that completes once cancelled.</returns>
    public static async Task RunAsync(Func<CancellationToken, Task<long>> refresh, Func<long, Uri> uri,
        IPublicationLiveSocket socket, Func<TimeSpan, CancellationToken, Task> delay, CancellationToken cancellationToken)
    {
        var backoff = new PublicationLiveBackoff();
        long? lastChanged = null;
        while (!cancellationToken.IsCancellationRequested)
        {
            long? publicationId = null;
            var opened = false;
            var changed = false;
            try
            {
                var current = await refresh(cancellationToken).ConfigureAwait(false);
                publicationId = current;
                cancellationToken.ThrowIfCancellationRequested();
                await foreach (var item in socket.ConnectAsync(uri(current), cancellationToken).ConfigureAwait(false))
                {
                    if (item.Opened) opened = true;
                    else if (PublicationLiveMessage.Parse(item.Frame.Span).IsPublicationChanged) changed = true;
                    if (changed) break;
                }
            }
            catch (Exception) when (!cancellationToken.IsCancellationRequested)
            {
                // A failed read or connection ends this round; the backoff below spaces the retry.
            }
            catch (Exception)
            {
                return;
            }
            if (cancellationToken.IsCancellationRequested) return;
            var repeated = changed && publicationId is not null && lastChanged == publicationId;
            lastChanged = changed ? publicationId : null;
            if (changed && !repeated)
            {
                backoff.Reset();
                continue;
            }
            if (opened && !repeated) backoff.Reset();
            try
            {
                await delay(backoff.Next(), cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }
}
#endregion

#region Connection
/// <summary>
/// The app's one live publication connection. The window holds it active while it is shown (web: while the document
/// is visible; Apple: while a scene is active) and releases it when hidden, minimized or closed; activating again starts
/// a fresh round, which re-reads the publication first (web resume recovery). A new generation reaches pages through
/// <see cref="FestivalApiClient.PublicationChanged"/>. Disabled for a loopback fixture origin unless a test opts in,
/// like Apple <c>PublicationLiveConnection</c>.
/// </summary>
public sealed class PublicationLiveConnection : IDisposable
{
    /// <summary>Launch-environment switch that turns the socket on for a loopback fixture origin (<c>1</c>).</summary>
    public const string LoopbackOptIn = "FST_LIVE_PUBLICATION_UPDATES";

    private readonly FestivalApiClient api;
    private readonly IPublicationLiveSocket socket;
    private readonly TimeProvider time;
    private readonly object gate = new();
    private CancellationTokenSource? running;
    private bool disposed;

    /// <summary>Creates an inactive connection.</summary>
    /// <param name="api">Public client (its publication reads drive the app).</param>
    /// <param name="socket">Socket factory.</param>
    /// <param name="time">Clock for reconnect delays.</param>
    public PublicationLiveConnection(FestivalApiClient api, IPublicationLiveSocket socket, TimeProvider? time = null)
    {
        this.api = api;
        this.socket = socket;
        this.time = time ?? TimeProvider.System;
    }

    /// <summary>Whether a live connection should run for <paramref name="api"/>'s origin.</summary>
    /// <param name="api">Public client.</param>
    /// <param name="environment">Launch environment (empty outside Debug and automation launches).</param>
    /// <returns><see langword="false"/> for a loopback fixture origin without <see cref="LoopbackOptIn"/>.</returns>
    public static bool IsEnabled(FestivalApiClient api, Func<string, string?> environment) =>
        !api.UsesLoopbackOrigin || environment(LoopbackOptIn) == "1";

    /// <summary>Whether the loop is running.</summary>
    public bool IsActive
    {
        get
        {
            lock (gate) return running is not null;
        }
    }

    /// <summary>The running loop, for tests.</summary>
    internal Task? Loop { get; private set; }

    /// <summary>Starts or stops the loop. Starting while running does nothing.</summary>
    /// <param name="active">Whether the app is in the foreground.</param>
    public void SetActive(bool active)
    {
        lock (gate)
        {
            if (disposed || active == (running is not null)) return;
            if (!active)
            {
                StopLocked();
                return;
            }
            var cts = new CancellationTokenSource();
            running = cts;
            Loop = Task.Run(() => PublicationLiveUpdates.RunAsync(
                async token => (await api.GetPublicationAsync(force: true, token).ConfigureAwait(false)).PublicationId,
                api.LiveUpdatesUri, socket, (wait, token) => Task.Delay(wait, time, token), cts.Token));
        }
    }

    /// <summary>
    /// Starts a fresh round now when running (the network came back): re-reads the publication and reconnects without
    /// waiting out the backoff, like the web's <c>online</c> recovery.
    /// </summary>
    public void Restart()
    {
        lock (gate)
        {
            if (running is null) return;
            StopLocked();
        }
        SetActive(true);
    }

    /// <inheritdoc />
    public void Dispose()
    {
        lock (gate)
        {
            StopLocked();
            disposed = true;
        }
    }

    /// <summary>Cancels the running loop (caller holds the lock).</summary>
    private void StopLocked()
    {
        // Not disposed: the cancelled loop may still be registering its last wait on this token.
        running?.Cancel();
        running = null;
    }
}
#endregion
