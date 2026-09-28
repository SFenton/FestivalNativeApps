
namespace Festival.Core.Tests;

public class CacheAndEndpointTests
{
    private static readonly Uri Base = new("https://festivalscoretracker.com/");

    [Fact]
    public void ResponseCache_ScopesToPublicationAndEvictsLru()
    {
        var cache = new ResponseCache(maxEntries: 2, maxBytes: 10);
        cache.Store("a", new ResponseCache.Entry([1, 2], 1, "e"));
        Assert.NotNull(cache.Get("a", 1));
        Assert.Null(cache.Get("a", 2));
        Assert.Null(cache.Get("missing", 1));
        cache.Store("b", new ResponseCache.Entry([1], 1, null));
        cache.Get("a", 1);
        cache.Store("c", new ResponseCache.Entry([1], 1, null));
        Assert.Null(cache.Get("b", 1));
        Assert.NotNull(cache.Get("a", 1));
        cache.Store("a", new ResponseCache.Entry(new byte[10], 1, null));
        Assert.Equal(1, cache.Count);
        cache.Store("huge", new ResponseCache.Entry(new byte[11], 1, null));
        Assert.Null(cache.Get("huge", 1));
        cache.Clear();
        Assert.Equal(0, cache.Count);
    }

    [Fact]
    public async Task ArtworkCache_CoalescesAndBounds()
    {
        var calls = 0;
        var gate = new TaskCompletionSource<byte[]>();
        var cache = new ArtworkByteCache((_, _) => { calls++; return gate.Task; }, maxEntries: 2, maxBytes: 5);
        var url = new Uri("https://cdn2.unrealengine.com/a.jpg");
        var first = cache.GetAsync(url);
        var second = cache.GetAsync(url);
        gate.SetResult([1, 2]);
        Assert.Equal([1, 2], await first);
        Assert.Equal([1, 2], await second);
        Assert.Equal(1, calls);
        Assert.Equal([1, 2], await cache.GetAsync(url));
        Assert.Equal(1, calls);
        Assert.Equal(2, cache.Bytes);

        var sized = new ArtworkByteCache((u, _) => Task.FromResult(new byte[u.AbsolutePath.Length % 4 + 1]), maxEntries: 2, maxBytes: 5);
        await sized.GetAsync(new Uri("https://x/a"));
        await sized.GetAsync(new Uri("https://x/bb"));
        await sized.GetAsync(new Uri("https://x/ccc"));
        Assert.True(sized.Bytes <= 5);
        var huge = new ArtworkByteCache((_, _) => Task.FromResult(new byte[10]), maxBytes: 5);
        await huge.GetAsync(url);
        Assert.Equal(0, huge.Bytes);
    }

    [Fact]
    public async Task ArtworkCache_ClearDropsInFlightResults()
    {
        var gate = new TaskCompletionSource<byte[]>();
        var cache = new ArtworkByteCache((_, _) => gate.Task);
        var url = new Uri("https://cdn2.unrealengine.com/a.jpg");
        var pending = cache.GetAsync(url);
        cache.Clear();
        gate.SetResult([9]);
        Assert.Equal([9], await pending);
        Assert.Equal(0, cache.Bytes);
    }

    [Fact]
    public async Task ArtworkCache_FailuresAreNotCachedAndCancelOnlyWaiter()
    {
        var calls = 0;
        var cache = new ArtworkByteCache((_, _) => ++calls == 1 ? Task.FromException<byte[]>(new FestivalApiException(FestivalApiErrorKind.Offline)) : Task.FromResult(new byte[] { 1 }));
        var url = new Uri("https://cdn2.unrealengine.com/a.jpg");
        await Assert.ThrowsAsync<FestivalApiException>(() => cache.GetAsync(url));
        Assert.Equal([1], await cache.GetAsync(url));

        var never = new ArtworkByteCache((_, _) => new TaskCompletionSource<byte[]>().Task);
        using var cts = new CancellationTokenSource(20);
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => never.GetAsync(url, cts.Token));
    }

    [Fact]
    public void Endpoints_BuildEscapedUrls()
    {
        Assert.Equal("https://festivalscoretracker.com/api/publication", ServiceEndpoints.Publication(Base).AbsoluteUri);
        Assert.Equal("https://festivalscoretracker.com/api/songs", ServiceEndpoints.Songs(Base).AbsoluteUri);
        Assert.Equal("https://festivalscoretracker.com/api/leaderboard/a%20b/Solo_PeripheralDrums?top=25&offset=50&leeway=-1.5",
            ServiceEndpoints.Leaderboard(Base, "a b", Instrument.ProDrums, 25, 50, -1.5).AbsoluteUri);
        Assert.Equal("http://127.0.0.1:8765/api/account/search?q=a%20b&limit=3",
            ServiceEndpoints.AccountSearch(new Uri("http://127.0.0.1:8765/x/"), "a b", 3).AbsoluteUri);
    }

    [Theory]
    [InlineData("", 10, 0, null)]
    [InlineData("a/b", 10, 0, null)]
    [InlineData("a\\b", 10, 0, null)]
    [InlineData("..", 10, 0, null)]
    [InlineData("ok", 0, 0, null)]
    [InlineData("ok", 26, 0, null)]
    [InlineData("ok", 10, -1, null)]
    [InlineData("ok", 10, 0, 6.0)]
    [InlineData("ok", 10, 0, double.NaN)]
    public void Endpoints_RejectUnsafeLeaderboardArgs(string song, int top, int offset, double? leeway) =>
        Assert.Equal(FestivalApiErrorKind.InvalidResource,
            Assert.Throws<FestivalApiException>(() => ServiceEndpoints.Leaderboard(Base, song, Instrument.Lead, top, offset, leeway)).Kind);

    [Theory]
    [InlineData("a", 10)]
    [InlineData(" ab", 10)]
    [InlineData("ab", 0)]
    [InlineData("ab", 11)]
    [InlineData("a\u0001b", 10)]
    public void Endpoints_RejectUnsafeSearch(string query, int limit) =>
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.AccountSearch(Base, query, limit));

    [Theory]
    [InlineData("abc-DEF_123", true)]
    [InlineData("", false)]
    [InlineData(null, false)]
    [InlineData("a b", false)]
    [InlineData("a/b", false)]
    public void ProfileText_ValidatesAccountIds(string? id, bool valid) => Assert.Equal(valid, ProfileText.IsValidAccountId(id));

    [Fact]
    public void ProfileText_FlagsControlAndBidiCharacters()
    {
        Assert.False(ProfileText.ContainsUnsafeCharacter("Normal Name"));
        Assert.True(ProfileText.ContainsUnsafeCharacter("a\nb"));
        Assert.True(ProfileText.ContainsUnsafeCharacter("a" + (char)0x85));
        Assert.True(ProfileText.ContainsUnsafeCharacter("a" + (char)0x202E));
        Assert.True(ProfileText.ContainsUnsafeCharacter("a" + (char)0x2067));
        Assert.False(ProfileText.ContainsUnsafeCharacter("a" + (char)0x2030));
    }
}
