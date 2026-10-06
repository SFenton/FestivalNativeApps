using System.Text;
using System.Text.Json;

namespace Festival.Core.Tests;

public class WhatsNewTests
{
    private const string SampleDocument = """
        {"schema": 1, "platform": "windows", "version": "2610.01.04", "baseline": "2610.01.03", "extra": true,
         "entries": [
          {"version": "2610.01.04", "released": false, "items": ["Rivals refresh correctly.", "  ", 5]},
          {"version": "2610.01.03", "released": true, "items": ["The Item Shop badge is back.", "Songs load faster."]},
          {"version": "2610.01.02", "released": true, "items": []},
          {"version": "2610.01.01", "items": ["The first release."]}
         ]}
        """;

    [Fact]
    public void Decode_OneVersionSectionPerEntry()
    {
        var entries = Changelog.Decode(SampleDocument);
        Assert.Equal(["2610.01.04", "2610.01.03", "2610.01.01"], entries.Select(e => e.Version));
        Assert.Equal([false, true, true], entries.Select(e => e.Released));
        var section = Assert.Single(entries[0].Sections);
        Assert.Equal("Version 2610.01.04", section.DisplayTitle);
        Assert.Equal(["Rivals refresh correctly."], section.Items);
        Assert.StartsWith("[{\"sections\":[{\"title\":\"Version 2610.01.04\"", Changelog.CanonicalJson(entries));
    }

    [Fact]
    public void Decode_BoundsAndRejectsMalformedDocuments()
    {
        var many = string.Join(',', Enumerable.Range(0, 50).Select(i =>
            $$"""{"version":"2610.{{i}}{{new string('9', 40)}}","items":[{{string.Join(',', Enumerable.Repeat($"\"{new string('a', 2000)}\"", 60))}}]}"""));
        var entries = Changelog.Decode($$"""{"entries":[{{many}}]}""");
        Assert.Equal(Changelog.MaxEntries, entries.Count);
        Assert.Equal(Changelog.MaxItems, entries[0].Sections[0].Items.Count);
        Assert.Equal(Changelog.MaxItemLength, entries[0].Sections[0].Items[0].Length);
        Assert.Equal(32, entries[0].Version!.Length);
        foreach (var bad in new[] { "[]", "{}", "{\"entries\":{}}", "{\"entries\":[5]}", "{\"entries\":[{\"items\":[\"a\"]}]}" })
        {
            Assert.Throws<FormatException>(() => Changelog.Decode(bad));
        }
        Assert.ThrowsAny<JsonException>(() => Changelog.Decode("not json"));
        Assert.Empty(Changelog.Decode("{\"entries\":[{\"version\":\"\",\"items\":[\"a\"]},{\"version\":\"1\"}]}"));
    }

    [Fact]
    public void Load_FallsBackToEmptyAndReadsTheEmbeddedPlaceholder()
    {
        Assert.Empty(Changelog.Load(() => null));
        Assert.Empty(Changelog.Load(() => new MemoryStream("nope"u8.ToArray())));
        Assert.Empty(Changelog.Load(() => new MemoryStream("{}"u8.ToArray())));
        Assert.Empty(Changelog.Load(() => new MemoryStream(new byte[300 * 1024])));
        Assert.Equal(3, Changelog.Load(() => new MemoryStream(Encoding.UTF8.GetBytes(SampleDocument))).Count);
        var placeholder = Assert.Single(Changelog.Entries);
        Assert.Equal("2610.01.01", placeholder.Version);
        Assert.Equal(Changelog.Hash(Changelog.Entries), Changelog.CurrentHash);
    }

    [Fact]
    public void Hash_ChangesWithVersionsAndEmptyIsNeverPending()
    {
        var one = Changelog.Decode("""{"entries":[{"version":"2610.01.01","items":["a"]}]}""");
        var two = Changelog.Decode("""{"entries":[{"version":"2610.01.02","items":["a"]},{"version":"2610.01.01","items":["a"]}]}""");
        Assert.NotEqual(Changelog.Hash(one), Changelog.Hash(two));
        // JS: calculateChangelogHash([]) → "[]" → ((91*31)+93).toString(36).
        Assert.Equal(Changelog.Base36(91 * 31 + 93), Changelog.EmptyHash);
        Assert.False(WhatsNewGate.IsPending(WhatsNewMode.Force, null, Changelog.EmptyHash));
        Assert.False(WhatsNewGate.IsPending(WhatsNewMode.Normal, null, Changelog.EmptyHash));
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
        Assert.Equal(Changelog.Entries, Changelog.DisplayEntries(), new EntryComparer());
        var versioned = Changelog.DisplayEntries([new([new("Version 2610.01.02", ["Kept.", "Manual gone."])], "2610.01.02", false)]);
        var kept = Assert.Single(versioned);
        Assert.Equal(("2610.01.02", false), (kept.Version, kept.Released));
        Assert.Equal(["Kept."], kept.Sections[0].Items);
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

    private const string GroupedDocument = """
        {"schema": 1, "platform": "windows", "version": "2610.02.02", "baseline": "2610.01.03",
         "entries": [
          {"version": "2610.02.02", "released": false,
           "items": ["Songs: Rows load faster.", "Rivals: Lists refresh.", "A loose note."],
           "groups": [{"category": "Songs", "items": ["Rows load faster."]},
                      {"category": "Rivals", "items": ["Lists refresh.", "See the Manual."]},
                      {"category": null, "items": ["A loose note."]}, 5, {"category": "Bands", "items": []}],
           "testflight": {"since": "2610.02.01", "new": ["Songs: Rows load faster."], "release": "2610.01.03",
                          "vs_release": ["Songs: Rows load faster.", "Songs: Filter fixed.", "General: Polish."],
                          "groups": [{"category": "Songs", "items": ["Rows load faster.", "Filter fixed."]},
                                     {"category": "General", "items": ["Polish."]}]}},
          {"version": "2610.01.03", "released": true, "items": ["The first release."]}
         ]}
        """;

    [Fact]
    public void Decode_KeepsGroupsAndTesterNotesVerbatim()
    {
        var entries = Changelog.Decode(GroupedDocument);
        Assert.Equal(
            [new ChangelogGroup("Songs", ["Rows load faster."]), new ChangelogGroup("Rivals", ["Lists refresh.", "See the Manual."]), new ChangelogGroup(null, ["A loose note."])],
            entries[0].Groups);
        Assert.Equal("2610.01.03", entries[0].Tester!.Release);
        Assert.Equal([new ChangelogGroup("Songs", ["Rows load faster.", "Filter fixed."]), new ChangelogGroup("General", ["Polish."])], entries[0].Tester!.Groups);
        // No groups in the document: the flat items become one uncategorized group (never re-classified).
        Assert.Equal([new ChangelogGroup(null, ["The first release."])], entries[1].Groups);
        Assert.Null(entries[1].Tester);
        // The show-once hash still follows the release items only.
        Assert.Equal(Changelog.Hash([.. entries.Select(e => e with { Groups = [], Tester = null })]), Changelog.Hash(entries));
    }

    [Fact]
    public void Decode_TesterFallsBackToVsReleaseAndIsBounded()
    {
        var fallback = Changelog.Decode("""{"entries":[{"version":"1","items":["a"],"testflight":{"release":null,"vs_release":["Songs: x"," "]}}]}""")[0].Tester!;
        Assert.Null(fallback.Release);
        Assert.Equal([new ChangelogGroup(null, ["Songs: x"])], fallback.Groups);
        Assert.Equal("Changes So Far", fallback.Title);
        Assert.Null(Changelog.Decode("""{"entries":[{"version":"1","items":["a"],"testflight":{"vs_release":[]}}]}""")[0].Tester);
        Assert.Null(Changelog.Decode("""{"entries":[{"version":"1","items":["a"],"testflight":5}]}""")[0].Tester);
        var many = string.Join(',', Enumerable.Range(0, 30).Select(i =>
            $$"""{"category":"{{new string('C', 50)}}{{i}}","items":[{{string.Join(',', Enumerable.Repeat("\"n\"", 10))}}]}"""));
        var tester = Changelog.Decode($$$"""{"entries":[{"version":"1","items":["a"],"testflight":{"release":"{{{new string('9', 40)}}}","groups":[{{{many}}}]}}]}""")[0].Tester!;
        Assert.Equal(Changelog.MaxTesterItems, tester.Groups.Sum(g => g.Items.Count));
        Assert.True(tester.Groups.Count <= Changelog.MaxGroups);
        Assert.Equal(Changelog.MaxCategoryLength, tester.Groups[0].Category!.Length);
        Assert.Equal(32, tester.Release!.Length);
        using var document = JsonDocument.Parse("""{"groups":[{"category":"","items":["x"]},{"items":["y"]}]}""");
        Assert.Equal([new ChangelogGroup(null, ["x"])], Changelog.DecodeGroups(document.RootElement, 1));
    }

    [Fact]
    public void DisplayBlocks_PickTheChannelsNotesWithCategoryHeadings()
    {
        var entries = Changelog.Decode(GroupedDocument);
        var store = Changelog.DisplayBlocks(InstallChannel.Store, entries);
        Assert.Equal(["Version 2610.02.02", "Version 2610.01.03"], store.Select(b => b.Title));
        // Manual bullets are dropped; empty groups vanish; uncategorized notes come last under "Other".
        Assert.Equal(["Songs", "Rivals", "Other"], store[0].Groups.Select(g => g.DisplayTitle));
        Assert.Equal(["Lists refresh."], store[0].Groups[1].Items);
        Assert.True(store[0].Headed);
        Assert.False(store[1].Headed);
        var tester = Changelog.DisplayBlocks(InstallChannel.Tester, entries);
        Assert.Equal(["Changes Since Release 2610.01.03", "Version 2610.01.03"], tester.Select(b => b.Title));
        Assert.Equal(["Rows load faster.", "Filter fixed.", "Polish."], tester[0].Groups.SelectMany(g => g.Items));
        // Entries without groups (older documents, the placeholder) keep their release bullets for both channels.
        var placeholder = Assert.Single(Changelog.DisplayBlocks(InstallChannel.Tester));
        Assert.Equal("Version 2610.01.01", placeholder.Title);
        Assert.Equal([new ChangelogGroup(null, ["The first release of Festival Score Tracker for Windows."])], placeholder.Groups);
        ChangelogEntry[] manual = [new([new ChangelogSection("MANUAL", ["x"])]), new([new ChangelogSection("Version 1", ["Manual only."])])];
        Assert.Empty(Changelog.DisplayBlocks(InstallChannel.Store, manual));
    }

    [Fact]
    public void ResolveEntries_ReadsTheDebugDocumentOnlyWithHooks()
    {
        string? Env(string name) => name == Changelog.DocumentVariable ? " grouped.json " : null;
        Stream Open(string path) => path == "grouped.json"
            ? new MemoryStream(Encoding.UTF8.GetBytes(GroupedDocument))
            : throw new FileNotFoundException(path);
        Assert.Equal(["2610.02.02", "2610.01.03"], Changelog.ResolveEntries(Env, true, Open).Select(e => e.Version));
        Assert.Same(Changelog.Entries, Changelog.ResolveEntries(Env, false, Open));
        Assert.Same(Changelog.Entries, Changelog.ResolveEntries(_ => "  ", true, Open));
        // A missing, unreadable or invalid file means an empty changelog (never presented), not a crash.
        Assert.Empty(Changelog.ResolveEntries(_ => "missing.json", true, Open));
        Assert.Empty(Changelog.ResolveEntries(Env, true, _ => throw new UnauthorizedAccessException()));
        Assert.Empty(Changelog.ResolveEntries(Env, true, _ => new MemoryStream("{}"u8.ToArray())));
        Assert.Empty(Changelog.ResolveEntries(_ => Path.Combine(Path.GetTempPath(), $"fst-missing-{Guid.NewGuid():N}.json"), true));
        // The dialog (launch and Settings replay) presents only when there are blocks: an empty changelog has none on
        // either channel, and its hash is the never-pending EmptyHash.
        var empty = Changelog.ResolveEntries(_ => "missing.json", true, Open);
        Assert.Empty(Changelog.DisplayBlocks(InstallChannel.Store, empty));
        Assert.Empty(Changelog.DisplayBlocks(InstallChannel.Tester, empty));
        Assert.Equal(Changelog.EmptyHash, Changelog.Hash(empty));
    }

    [Fact]
    public void InstallChannel_StoreSignatureOnlyWithADebugOverride()
    {
        Assert.Equal(InstallChannel.Store, InstallChannels.FromSignatureKind("Store"));
        foreach (var other in new[] { null, "", "None", "Developer", "Enterprise", "System" })
        {
            Assert.Equal(InstallChannel.Tester, InstallChannels.FromSignatureKind(other));
        }
        string? NoEnvironment(string _) => null;
        Assert.Equal(InstallChannel.Store, InstallChannels.Resolve([], NoEnvironment, false, () => "Store"));
        // Unpackaged builds have no package identity: Package.Current throws.
        Assert.Equal(InstallChannel.Tester, InstallChannels.Resolve([], NoEnvironment, false, () => throw new InvalidOperationException("no identity")));
        Assert.Equal(InstallChannel.Tester, InstallChannels.Resolve(["--distribution", "tester"], NoEnvironment, true, () => "Store"));
        Assert.Equal(InstallChannel.Store, InstallChannels.Resolve(["--distribution=STORE"], NoEnvironment, true, () => null));
        Assert.Equal(InstallChannel.Store, InstallChannels.Resolve([], name => name == "FST_DEBUG_DISTRIBUTION" ? "store" : null, true, () => null));
        // Overrides are ignored outside Debug/automation launches; unknown values fall back to the signature.
        Assert.Equal(InstallChannel.Store, InstallChannels.Resolve(["--distribution", "tester"], NoEnvironment, false, () => "Store"));
        Assert.Equal(InstallChannel.Tester, InstallChannels.Resolve(["--distribution", "bogus"], NoEnvironment, true, () => "Developer"));
    }

    private sealed class EntryComparer : IEqualityComparer<ChangelogEntry>
    {
        public bool Equals(ChangelogEntry? x, ChangelogEntry? y) =>
            x is not null && y is not null && x.Version == y.Version && x.Released == y.Released &&
            Changelog.CanonicalJson([x]) == Changelog.CanonicalJson([y]);

        public int GetHashCode(ChangelogEntry obj) => Changelog.CanonicalJson([obj]).GetHashCode();
    }
}
