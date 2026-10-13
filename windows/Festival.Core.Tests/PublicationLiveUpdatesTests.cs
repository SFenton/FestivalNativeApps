using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using Festival.Core.Data;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

/// <summary>The live publication socket (issue #616, port of web <c>useAppWebSocket</c> and Apple #304).</summary>
public class PublicationLiveUpdatesTests
{
    private const string Changed = """{"type":"publication_changed","publicationId":8}""";
    private const string Snapshot = """{"type":"shop_snapshot","songs":[]}""";

    #region Message and backoff
    [Theory]
    [InlineData("""{"type":"publication_changed","publicationId":8}""", true, 8L)]
    [InlineData("""{"type":"publication_changed"}""", true, null)]
    [InlineData("""{"type":"publication_changed","publicationId":0}""", true, null)]
    [InlineData("""{"type":"publication_changed","publicationId":-3}""", true, null)]
    [InlineData("""{"type":"publication_changed","publicationId":1.5}""", true, null)]
    [InlineData("""{"type":"publication_changed","publicationId":"8"}""", true, null)]
    [InlineData("""{"type":"shop_snapshot","publicationId":8}""", false, null)]
    [InlineData("""{"type":"sync_progress"}""", false, null)]
    [InlineData("""{"type":7}""", false, null)]
    [InlineData("""["publication_changed"]""", false, null)]
    [InlineData("""not json""", false, null)]
    [InlineData("", false, null)]
    public void Parse_ActsOnlyOnPublicationChanged(string frame, bool changed, long? id)
    {
        var message = PublicationLiveMessage.Parse(Encoding.UTF8.GetBytes(frame));
        Assert.Equal(changed, message.IsPublicationChanged);
        Assert.Equal(id, message.PublicationId);
    }

    [Fact]
    public void Backoff_DoublesFromOneSecondToThirtyAndResets()
    {
        var backoff = new PublicationLiveBackoff();
        var delays = Enumerable.Range(0, 7).Select(_ => backoff.Next().TotalSeconds).ToArray();
        Assert.Equal([1, 2, 4, 8, 16, 30, 30], delays);
        backoff.Reset();
        Assert.Equal(TimeSpan.FromSeconds(1), backoff.Next());
        Assert.Equal(TimeSpan.FromSeconds(2), backoff.Next());
    }
    #endregion

    #region URL
    [Fact]
    public void LiveUpdatesUri_IsWssWithOnlyThePublicationId()
    {
        var api = new FakeService().Client();
        Assert.False(api.UsesLoopbackOrigin);
        Assert.Equal("wss://festivalscoretracker.com/api/ws?publicationId=7", api.LiveUpdatesUri(7).AbsoluteUri);
        Assert.Throws<FestivalApiException>(() => api.LiveUpdatesUri(0));
        Assert.Throws<FestivalApiException>(() => api.LiveUpdatesUri(-1));
    }

    [Fact]
    public void LiveUpdatesUri_UsesWsOnlyForALoopbackFixture()
    {
        var api = new FestivalApiClient(new RequestGate(new HttpClient()), new Uri("http://127.0.0.1:5123/"));
        Assert.True(api.UsesLoopbackOrigin);
        Assert.Equal("ws://127.0.0.1:5123/api/ws?publicationId=12", api.LiveUpdatesUri(12).AbsoluteUri);
        var custom = new FestivalApiClient(new RequestGate(new HttpClient()), new Uri("https://example.test:8443/"));
        Assert.Equal("wss://example.test:8443/api/ws?publicationId=3", custom.LiveUpdatesUri(3).AbsoluteUri);
    }

    [Fact]
    public void Connection_IsOffForLoopbackFixturesUnlessOptedIn()
    {
        var production = new FakeService().Client();
        var loopback = new FestivalApiClient(new RequestGate(new HttpClient()), new Uri("http://127.0.0.1:5123/"));
        Assert.True(PublicationLiveConnection.IsEnabled(production, _ => null));
        Assert.False(PublicationLiveConnection.IsEnabled(loopback, _ => null));
        Assert.False(PublicationLiveConnection.IsEnabled(loopback, _ => "0"));
        Assert.True(PublicationLiveConnection.IsEnabled(loopback,
            name => name == PublicationLiveConnection.LoopbackOptIn ? "1" : null));
    }
    #endregion

    #region Loop
    [Fact]
    public async Task Run_PublicationChangedStartsTheNextRoundAtOnce()
    {
        var socket = new ScriptedSocket(["open", Snapshot, Changed], ["open"], ["fail"], ["hang"]);
        var ids = new Queue<long>([7, 8, 8, 8]);
        var delays = new List<TimeSpan>();
        using var cts = new CancellationTokenSource();
        var run = PublicationLiveUpdates.RunAsync(_ => Task.FromResult(ids.Count > 1 ? ids.Dequeue() : ids.Peek()),
            id => new Uri($"wss://festivalscoretracker.com/api/ws?publicationId={id}"), socket,
            (delay, _) => { delays.Add(delay); return Task.CompletedTask; }, cts.Token);
        await Async.Until(() => socket.ConnectCount == 4);
        await cts.CancelAsync();
        await run;
        Assert.Equal(["publicationId=7", "publicationId=8", "publicationId=8", "publicationId=8"],
            socket.Connected.Select(u => u.Query.TrimStart('?')));
        // The change reconnects with no wait; a server close after opening waits 1 s; the failure after it doubles.
        Assert.Equal([TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2)], delays);
    }

    [Fact]
    public async Task Run_FailuresBackOffAndTheRefreshFailureCountsToo()
    {
        var socket = new ScriptedSocket(["fail"], ["fail"], ["fail"], ["hang"]);
        var reads = 0;
        var delays = new List<TimeSpan>();
        using var cts = new CancellationTokenSource();
        var run = PublicationLiveUpdates.RunAsync(_ => ++reads == 2
                ? Task.FromException<long>(new FestivalApiException(FestivalApiErrorKind.Offline))
                : Task.FromResult(7L),
            id => new Uri($"wss://festivalscoretracker.com/api/ws?publicationId={id}"), socket,
            (delay, _) => { delays.Add(delay); return Task.CompletedTask; }, cts.Token);
        await Async.Until(() => socket.ConnectCount == 4);
        await cts.CancelAsync();
        await run;
        Assert.Equal([1, 2, 4, 8], delays.Select(d => d.TotalSeconds));
    }

    [Fact]
    public async Task Run_RepeatedChangeForTheSameGenerationWaits()
    {
        var socket = new ScriptedSocket(["open", Changed], ["open", Changed], ["open", Changed], ["hang"]);
        var delays = new List<TimeSpan>();
        using var cts = new CancellationTokenSource();
        var run = PublicationLiveUpdates.RunAsync(_ => Task.FromResult(7L),
            id => new Uri($"wss://festivalscoretracker.com/api/ws?publicationId={id}"), socket,
            (delay, _) => { delays.Add(delay); return Task.CompletedTask; }, cts.Token);
        await Async.Until(() => socket.ConnectCount == 4);
        await cts.CancelAsync();
        await run;
        // The first change reconnects at once; the same generation again backs off without resetting (no tight loop).
        Assert.Equal([1, 2], delays.Select(d => d.TotalSeconds));
    }

    [Fact]
    public async Task Run_CancellationDuringAWaitEndsTheLoop()
    {
        var socket = new ScriptedSocket(["fail"]);
        using var cts = new CancellationTokenSource();
        var run = PublicationLiveUpdates.RunAsync(_ => Task.FromResult(7L),
            id => new Uri($"wss://festivalscoretracker.com/api/ws?publicationId={id}"), socket,
            (delay, token) => Task.Delay(Timeout.InfiniteTimeSpan, token), cts.Token);
        await Async.Until(() => socket.ConnectCount == 1);
        await cts.CancelAsync();
        await run.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(1, socket.ConnectCount);
    }
    #endregion

    #region Connection
    [Fact]
    public async Task Connection_RereadsThePublicationOnConnectAndOnChange()
    {
        var service = new FakeService();
        var api = service.Client();
        await api.GetPublicationAsync();
        var changes = new List<long>();
        api.PublicationChanged += (_, id) => { lock (changes) changes.Add(id); };
        var socket = new ScriptedSocket(["open", Snapshot, "wait", Changed], ["open", "hang"]);
        using var live = new PublicationLiveConnection(api, socket, new FakeTimeProvider());
        Assert.False(live.IsActive);

        live.SetActive(true);
        live.SetActive(true);
        Assert.True(live.IsActive);
        await Async.Until(() => socket.ConnectCount == 1);
        Assert.Equal("wss://festivalscoretracker.com/api/ws?publicationId=7", socket.Connected[0].AbsoluteUri);
        Assert.Empty(changes);

        service.PublicationId = 8;
        socket.Release();
        await Async.Until(() => socket.ConnectCount == 2);
        Assert.Equal([8L], changes);
        Assert.Equal("wss://festivalscoretracker.com/api/ws?publicationId=8", socket.Connected[1].AbsoluteUri);
        // The first read, the connect-time read and the read after the change.
        Assert.Equal(3, service.Handler.To("/api/publication").Count());
        Assert.All(service.Handler.Requests, r => Assert.Equal(HttpMethod.Get, r.Method));

        live.SetActive(false);
        Assert.False(live.IsActive);
        await live.Loop!.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task Connection_ConnectTimeReadObservesANewerPublication()
    {
        var service = new FakeService();
        var api = service.Client();
        await api.GetPublicationAsync();
        var changes = new List<long>();
        api.PublicationChanged += (_, id) => { lock (changes) changes.Add(id); };
        service.PublicationId = 9;
        var socket = new ScriptedSocket(["open", "hang"]);
        using var live = new PublicationLiveConnection(api, socket, new FakeTimeProvider());
        live.SetActive(true);
        await Async.Until(() => socket.ConnectCount == 1);
        Assert.Equal([9L], changes);
        Assert.EndsWith("publicationId=9", socket.Connected[0].AbsoluteUri, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Connection_RestartRereadsAndReconnects_AndDisposeStopsForGood()
    {
        var service = new FakeService();
        var api = service.Client();
        var socket = new ScriptedSocket(["open", "hang"], ["open", "hang"]);
        var live = new PublicationLiveConnection(api, socket, new FakeTimeProvider());
        live.Restart();
        Assert.False(live.IsActive);
        live.SetActive(true);
        await Async.Until(() => socket.ConnectCount == 1);
        var first = live.Loop!;
        live.Restart();
        await first.WaitAsync(TimeSpan.FromSeconds(5));
        await Async.Until(() => socket.ConnectCount == 2);
        Assert.Equal(2, service.Handler.To("/api/publication").Count());
        live.Dispose();
        Assert.False(live.IsActive);
        live.SetActive(true);
        Assert.False(live.IsActive);
    }
    #endregion

    #region Production socket
    [Fact]
    public async Task ClientSocket_ReceivesFramesAndSendsNothingButAClose()
    {
        using var server = new LoopbackWebSocketServer();
        var serverRun = server.RunAsync([Snapshot, Changed]);
        var socket = new ClientWebSocketPublicationLiveSocket();
        var events = new List<PublicationSocketEvent>();
        await foreach (var item in socket.ConnectAsync(new Uri($"ws://127.0.0.1:{server.Port}/api/ws?publicationId=7"), CancellationToken.None))
        {
            events.Add(item);
            if (!item.Opened && PublicationLiveMessage.Parse(item.Frame.Span).IsPublicationChanged) break;
        }
        var (request, firstClientFrame) = await serverRun.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(events[0].Opened);
        Assert.Equal([Snapshot, Changed], events.Skip(1).Select(e => Encoding.UTF8.GetString(e.Frame.Span)));
        Assert.StartsWith("GET /api/ws?publicationId=7 HTTP/1.1", request, StringComparison.Ordinal);
        foreach (var header in new[] { "x-api-key", "cookie", "authorization", "x-fst-selected" })
            Assert.DoesNotContain(header, request, StringComparison.OrdinalIgnoreCase);
        // The only frame the client ever sends is the close handshake: no subscribe_sync, no keep-alive.
        Assert.Equal(WebSocketMessageType.Close, firstClientFrame);
    }

    [Fact]
    public async Task ClientSocket_ServerCloseEndsTheSequence()
    {
        using var server = new LoopbackWebSocketServer();
        var serverRun = server.RunAsync([Snapshot], closeAfterSend: true);
        var socket = new ClientWebSocketPublicationLiveSocket();
        var events = new List<PublicationSocketEvent>();
        await foreach (var item in socket.ConnectAsync(new Uri($"ws://127.0.0.1:{server.Port}/api/ws?publicationId=7"), CancellationToken.None))
            events.Add(item);
        await serverRun.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.Equal(2, events.Count);
    }

    [Fact]
    public async Task ClientSocket_RefusesAnInsecureRemoteUrl()
    {
        var socket = new ClientWebSocketPublicationLiveSocket();
        await Assert.ThrowsAsync<FestivalApiException>(async () =>
        {
            await foreach (var _ in socket.ConnectAsync(new Uri("ws://festivalscoretracker.com/api/ws?publicationId=7"), CancellationToken.None)) { }
        });
    }
    #endregion

    #region Fakes
    /// <summary>
    /// Socket whose rounds follow scripts: <c>open</c>, a JSON frame, <c>fail</c> (throws), <c>wait</c> (until
    /// <see cref="Release"/>) and <c>hang</c> (until cancelled). A script that runs out closes the connection.
    /// </summary>
    private sealed class ScriptedSocket(params string[][] rounds) : IPublicationLiveSocket
    {
        private readonly Queue<string[]> scripts = new(rounds);
        private readonly List<Uri> connected = [];
        private TaskCompletionSource released = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public IReadOnlyList<Uri> Connected
        {
            get
            {
                lock (connected) return [.. connected];
            }
        }

        public int ConnectCount
        {
            get
            {
                lock (connected) return connected.Count;
            }
        }

        public void Release() => released.TrySetResult();

        public async IAsyncEnumerable<PublicationSocketEvent> ConnectAsync(Uri uri, [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            string[] script;
            lock (connected)
            {
                connected.Add(uri);
                script = scripts.Count > 0 ? scripts.Dequeue() : ["hang"];
            }
            foreach (var step in script)
            {
                switch (step)
                {
                    case "open":
                        yield return PublicationSocketEvent.Open;
                        break;
                    case "fail":
                        throw new WebSocketException(WebSocketError.ConnectionClosedPrematurely);
                    case "wait":
                        await released.Task.WaitAsync(cancellationToken);
                        released = new(TaskCreationOptions.RunContinuationsAsynchronously);
                        break;
                    case "hang":
                        await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                        break;
                    default:
                        yield return PublicationSocketEvent.Message(Encoding.UTF8.GetBytes(step));
                        break;
                }
            }
        }
    }

    /// <summary>A one-connection loopback WebSocket server that records the handshake and the client's first frame.</summary>
    private sealed class LoopbackWebSocketServer : IDisposable
    {
        private readonly TcpListener listener = new(IPAddress.Loopback, 0);

        public LoopbackWebSocketServer() => listener.Start();

        public int Port => ((IPEndPoint)listener.LocalEndpoint).Port;

        public Task<(string Request, WebSocketMessageType FirstClientFrame)> RunAsync(string[] frames, bool closeAfterSend = false) => Task.Run(async () =>
        {
            using var client = await listener.AcceptTcpClientAsync();
            var stream = client.GetStream();
            var head = new List<byte>();
            while (head.Count < 4 || !(head[^4] == '\r' && head[^3] == '\n' && head[^2] == '\r' && head[^1] == '\n'))
            {
                var next = stream.ReadByte();
                if (next < 0) throw new IOException("Handshake ended early.");
                head.Add((byte)next);
            }
            var request = Encoding.ASCII.GetString([.. head]);
            var key = request.Split("\r\n").Single(l => l.StartsWith("Sec-WebSocket-Key:", StringComparison.OrdinalIgnoreCase))
                .Split(':', 2)[1].Trim();
            var accept = Convert.ToBase64String(SHA1.HashData(Encoding.ASCII.GetBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
            var response = Encoding.ASCII.GetBytes(
                $"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n");
            await stream.WriteAsync(response);
            using var ws = WebSocket.CreateFromStream(stream, new WebSocketCreationOptions { IsServer = true, KeepAliveInterval = TimeSpan.Zero });
            foreach (var frame in frames)
                await ws.SendAsync(Encoding.UTF8.GetBytes(frame), WebSocketMessageType.Text, true, CancellationToken.None);
            if (closeAfterSend)
            {
                await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);
                return (request, WebSocketMessageType.Close);
            }
            var buffer = new byte[4096];
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            var result = await ws.ReceiveAsync(buffer, timeout.Token);
            return (request, result.MessageType);
        });

        public void Dispose() => listener.Stop();
    }
    #endregion
}
