using System.Text;

namespace Festival.Core.Tests;

public class WhatsNewTests
{
    [Fact]
    public void Hash_MatchesTheWebsPrecomputedHash()
    {
        Assert.Equal(Changelog.WebHash, Changelog.CurrentHash);
        Assert.StartsWith("[{\"sections\":[{\"title\":\"ITEM SHOP\",\"items\":[\"Newly released", Changelog.CanonicalJson(Changelog.Entries));
    }

    [Theory]
    [InlineData(0, "0")]
    [InlineData(35, "z")]
    [InlineData(36, "10")]
    [InlineData(-36, "-10")]
    [InlineData(int.MinValue, "-zik0zk")]
    public void Base36_LikeJavaScript(int value, string expected) => Assert.Equal(expected, Changelog.Base36(value));

    [Fact]
    public void JsonString_EscapesLikeJsonStringify() =>
        Assert.Equal("\"a\\\"b\\\\c\\n\\r\\t\\b\\f\\u0001é\"", Changelog.JsonString("a\"b\\c\n\r\t\b\f\u0001é"));

    [Fact]
    public void DisplayEntries_DropManualAndEmptySections()
    {
        IReadOnlyList<ChangelogEntry> entries =
        [
            new([new("APP MANUAL", ["x"]), new("SONGS", ["Open the manual.", "Keep me."]), new("OTHER", ["Manually sorted."])]),
            new([new("MANUAL", ["Only manual."])]),
        ];
        var shown = Changelog.DisplayEntries(entries);
        var entry = Assert.Single(shown);
        Assert.Equal(["SONGS", "OTHER"], entry.Sections.Select(s => s.Title));
        Assert.Equal(["Keep me."], entry.Sections[0].Items);
        Assert.Equal(Changelog.Entries[0].Sections.Count, Changelog.DisplayEntries()[0].Sections.Count);
    }

    [Theory]
    [InlineData("SONG DETAILS", "Song Details")]
    [InlineData("ITEM SHOP", "Item Shop")]
    [InlineData("THE STATE OF THE APP", "The State of the App")]
    public void TitleCase_KeepsMinorWordsLower(string heading, string expected) =>
        Assert.Equal(expected, new ChangelogSection(heading, ["x"]).DisplayTitle);

    [Theory]
    [InlineData(new string[0], null, true, WhatsNewMode.Off)]
    [InlineData(new string[0], null, false, WhatsNewMode.Normal)]
    [InlineData(new[] { "--whats-new=force" }, "off", true, WhatsNewMode.Force)]
    [InlineData(new[] { "--whats-new", "fresh" }, null, true, WhatsNewMode.Fresh)]
    [InlineData(new string[0], "on", true, WhatsNewMode.Normal)]
    [InlineData(new string[0], " OFF ", false, WhatsNewMode.Off)]
    [InlineData(new string[0], "bogus", false, WhatsNewMode.Normal)]
    public void Parse_FlagWinsOverEnvironment(string[] args, string? env, bool debug, WhatsNewMode expected) =>
        Assert.Equal(expected, WhatsNewGate.Parse(args, _ => env, debug));

    [Theory]
    [InlineData(WhatsNewMode.Off, null, false)]
    [InlineData(WhatsNewMode.Normal, null, true)]
    [InlineData(WhatsNewMode.Normal, "h", false)]
    [InlineData(WhatsNewMode.Fresh, "old", true)]
    [InlineData(WhatsNewMode.Force, "h", true)]
    public void IsPending_OncePerChangelog(WhatsNewMode mode, string? seen, bool pending) =>
        Assert.Equal(pending, WhatsNewGate.IsPending(mode, seen, "h"));

    [Fact]
    public void Title_IncludesVersion()
    {
        Assert.Equal("What's New · 1.2.3", WhatsNewGate.Title("1.2.3"));
        Assert.Equal("What's New", WhatsNewGate.Title(""));
    }

    [Fact]
    public void SeenStore_RoundTripsAndRejectsBadBlobs()
    {
        var blob = new MemoryBlobStore();
        var store = new ChangelogSeenStore(blob);
        Assert.Null(store.SeenHash());
        store.MarkSeen(new string('v', 80), Changelog.CurrentHash);
        Assert.Equal(Changelog.CurrentHash, store.SeenHash());
        Assert.Contains("\"version\":\"" + new string('v', 64) + "\"", Encoding.UTF8.GetString(blob.Read()!));
        store.Reset();
        Assert.Null(store.SeenHash());
        foreach (var bad in new[] { "not json", "[]", "{\"hash\":\"\",\"version\":\"1\"}", "{\"hash\":5,\"version\":\"1\"}",
                     "{\"hash\":\"h\"}", "{\"hash\":\"" + new string('h', 33) + "\",\"version\":\"1\"}" })
        {
            blob.Write(Encoding.UTF8.GetBytes(bad));
            Assert.Null(store.SeenHash());
        }
        blob.Write(new byte[ChangelogSeenStore.MaxBytes + 1]);
        Assert.Null(store.SeenHash());
        Assert.EndsWith("whats-new.json", ChangelogSeenStore.DefaultPath);
    }
}
