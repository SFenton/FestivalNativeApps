using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Festival.Core.Domain;

#region Model
/// <summary>One titled group of changelog bullets (web <c>ChangelogSection</c>, <c>FortniteFestivalWeb/src/changelog.ts</c>).</summary>
/// <param name="Title">Heading as generated (e.g. "Version 2610.01.01").</param>
/// <param name="Items">Bullets in web order.</param>
public sealed record ChangelogSection(string Title, IReadOnlyList<string> Items)
{
    /// <summary>Native Title Case heading ("SONG DETAILS" → "Song Details").</summary>
    public string DisplayTitle => Changelog.TitleCase(Title);
}

/// <summary>One version's sections (web <c>ChangelogEntry</c>).</summary>
/// <param name="Sections">Sections in display order (one "Version X" section; drives the show-once hash).</param>
/// <param name="Version">Windows app version (<c>YYMM.DD.NN</c>), or <see langword="null"/> for unversioned data.</param>
/// <param name="Released">Whether the version reached the Store (the newest entry is the build itself).</param>
public sealed record ChangelogEntry(IReadOnlyList<ChangelogSection> Sections, string? Version = null, bool Released = true)
{
    /// <summary>The same notes grouped by page category (<c>groups</c>); empty for documents without it.</summary>
    public IReadOnlyList<ChangelogGroup> Groups { get; init; } = [];

    /// <summary>Tester notes of the unreleased built version (<c>testflight</c>), or <see langword="null"/>.</summary>
    public TesterNotes? Tester { get; init; }
}

/// <summary>
/// One page-category group of notes as <c>versioning.py groups_json</c> writes it: prefix stripped, groups already in the
/// web changelog's page order.
/// </summary>
/// <param name="Category">Page category ("Songs", "Item Shop", …), or <see langword="null"/> for uncategorized notes.</param>
/// <param name="Items">Bullets, word for word.</param>
public sealed record ChangelogGroup(string? Category, IReadOnlyList<string> Items)
{
    /// <summary>Heading of uncategorized notes (TestFlight "What to Test" wording).</summary>
    public const string Other = "Other";

    /// <summary>Heading above the bullets: the category, or "Other".</summary>
    public string DisplayTitle => Category ?? Other;

    /// <inheritdoc/>
    public bool Equals(ChangelogGroup? other) =>
        other is not null && Category == other.Category && Items.SequenceEqual(other.Items);

    /// <inheritdoc/>
    public override int GetHashCode() => HashCode.Combine(Category, Items.Count);
}

/// <summary>
/// The built version's tester notes (<c>testflight</c>): every note since the Store's latest release, grouped like
/// TestFlight "What to Test".
/// </summary>
/// <param name="Release">Newest released version compared with, or <see langword="null"/> before the first release.</param>
/// <param name="Groups">Category groups in display order.</param>
public sealed record TesterNotes(string? Release, IReadOnlyList<ChangelogGroup> Groups)
{
    /// <summary>Block heading, matching TestFlight's "Changes since release X" / "Changes so far".</summary>
    public string Title => Release is null ? "Changes So Far" : $"Changes Since Release {Release}";
}

/// <summary>One headed block of the What's New list: a version (or the tester list) and its groups.</summary>
/// <param name="Title">Block heading ("Version 2610.02.01", "Changes Since Release 2610.01.03").</param>
/// <param name="Groups">Non-empty groups in display order.</param>
public sealed record WhatsNewBlock(string Title, IReadOnlyList<ChangelogGroup> Groups)
{
    /// <summary>Whether groups get category headings: only when a note has a category (TestFlight's rule).</summary>
    public bool Headed => Groups.Any(group => group.Category is not null);
}

/// <summary>How this copy was installed, which picks the What's New notes (Apple <c>AppDistribution</c>, Android <c>InstallChannel</c>).</summary>
public enum InstallChannel
{
    /// <summary>Signed by the Microsoft Store: the release notes.</summary>
    Store,
    /// <summary>Anything else (unpackaged dev builds, sideloaded or developer-signed MSIX): the tester notes.</summary>
    Tester,
}

/// <summary>Install channel rules.</summary>
public static class InstallChannels
{
    /// <summary>
    /// Resolves the channel. Debug/automation launches honour <c>--distribution store|tester</c> or
    /// <c>FST_DEBUG_DISTRIBUTION</c>; otherwise only a Store signature (<c>Package.Current.SignatureKind</c>) means Store.
    /// </summary>
    /// <param name="args">Command-line arguments.</param>
    /// <param name="environment">Environment lookup.</param>
    /// <param name="hooksEnabled">Debug or automation launch.</param>
    /// <param name="signatureKind">
    /// Reads the package's <c>PackageSignatureKind</c> name; only called without an override. Throwing (no package
    /// identity) or <see langword="null"/> means not from the Store.
    /// </param>
    /// <returns>Channel.</returns>
    public static InstallChannel Resolve(IReadOnlyList<string> args, Func<string, string?> environment, bool hooksEnabled, Func<string?> signatureKind)
    {
        if (hooksEnabled)
        {
            string? value = null;
            for (var i = 0; i < args.Count; i++)
            {
                if (args[i].StartsWith("--distribution=", StringComparison.OrdinalIgnoreCase)) value = args[i]["--distribution=".Length..];
                else if (string.Equals(args[i], "--distribution", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Count) value = args[++i];
            }
            switch ((value ?? environment("FST_DEBUG_DISTRIBUTION"))?.Trim().ToLowerInvariant())
            {
                case "store": return InstallChannel.Store;
                case "tester" or "testflight": return InstallChannel.Tester;
            }
        }
        string? kind;
        try
        {
            kind = signatureKind();
        }
#pragma warning disable CA1031 // Any failure to read the package identity means "not from the Store".
        catch (Exception)
#pragma warning restore CA1031
        {
            kind = null;
        }
        return FromSignatureKind(kind);
    }

    /// <summary>Channel from a <c>PackageSignatureKind</c> name.</summary>
    /// <param name="signatureKind">"Store", "Developer", "Enterprise", "System", "None", or <see langword="null"/> when unpackaged.</param>
    /// <returns><see cref="InstallChannel.Store"/> only for a Store signature.</returns>
    public static InstallChannel FromSignatureKind(string? signatureKind) =>
        string.Equals(signatureKind?.Trim(), "Store", StringComparison.OrdinalIgnoreCase) ? InstallChannel.Store : InstallChannel.Tester;
}
#endregion

#region Catalogue
/// <summary>
/// The "What's New" changelog: one "Version YYMM.DD.NN" section per released Windows version plus the built one,
/// generated at release-build time by <c>tools/release/versioning.py whats-new</c> into the embedded
/// <c>WhatsNew.json</c> (Festival.Core). Content comes from <c>Release-Note-Windows</c>/<c>Release-Note</c> commit
/// trailers; see <c>.agents/workflow/release-machine.md</c>.
/// </summary>
public static class Changelog
{
    /// <summary>Embedded resource name of the generated document.</summary>
    public const string ResourceName = "WhatsNew.json";

    /// <summary>Most entries kept.</summary>
    public const int MaxEntries = 20;

    /// <summary>Most bullets kept per entry.</summary>
    public const int MaxItems = 40;

    /// <summary>Longest bullet kept, in characters.</summary>
    public const int MaxItemLength = 600;

    /// <summary>Most category groups kept per list (17 categories plus "Other", with headroom).</summary>
    public const int MaxGroups = 24;

    /// <summary>Longest category name kept.</summary>
    public const int MaxCategoryLength = 32;

    /// <summary>
    /// Most bullets kept in the tester list: every note since the latest release, which can exceed one version's
    /// <see cref="MaxItems"/>.
    /// </summary>
    public const int MaxTesterItems = 120;

    /// <summary>Longest version string kept.</summary>
    private const int MaxVersionLength = 32;

    /// <summary>Largest document read, in bytes.</summary>
    private const int MaxDocumentBytes = 256 * 1024;

    /// <summary>Entries bundled with the app (empty when the resource is missing or invalid).</summary>
    public static IReadOnlyList<ChangelogEntry> Entries { get; } = Load();

    /// <summary>Hash of the current entries; What's New shows once per distinct hash.</summary>
    public static string CurrentHash => Hash(Entries);

    /// <summary>Hash of an empty changelog; an empty changelog is never presented.</summary>
    public static string EmptyHash { get; } = Hash([]);

    /// <summary>
    /// Debug/automation variable naming a <c>WhatsNew.json</c> file to show instead of the embedded one, so UI
    /// Automation can reach the grouped and tester states the checked-in placeholder lacks.
    /// </summary>
    public const string DocumentVariable = "FST_DEBUG_WHATS_NEW_FILE";

    /// <summary>
    /// The entries this launch shows: <see cref="Entries"/>, or in Debug/automation launches the document named by
    /// <see cref="DocumentVariable"/> (decoded with the same bounds; an unreadable or invalid file means no entries).
    /// </summary>
    /// <param name="environment">Environment lookup.</param>
    /// <param name="hooksEnabled">Debug or automation launch.</param>
    /// <param name="openFile">Opens a file for reading (defaults to <see cref="File.OpenRead(string)"/>).</param>
    /// <returns>Entries, newest first.</returns>
    public static IReadOnlyList<ChangelogEntry> ResolveEntries(Func<string, string?> environment, bool hooksEnabled, Func<string, Stream>? openFile = null)
    {
        var path = hooksEnabled ? environment(DocumentVariable)?.Trim() : null;
        if (string.IsNullOrEmpty(path)) return Entries;
        try
        {
            return Load(() => (openFile ?? File.OpenRead)(path));
        }
        catch (Exception error) when (error is UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return [];
        }
    }

    /// <summary>Loads and decodes the generated document; any failure yields no entries.</summary>
    /// <param name="open">Stream factory (defaults to the embedded resource).</param>
    /// <returns>Entries, newest first.</returns>
    public static IReadOnlyList<ChangelogEntry> Load(Func<Stream?>? open = null)
    {
        try
        {
            using var stream = (open ?? (() => typeof(Changelog).Assembly.GetManifestResourceStream(ResourceName)))();
            if (stream is null) return [];
            using var buffer = new MemoryStream();
            stream.CopyTo(buffer);
            return buffer.Length > MaxDocumentBytes ? [] : Decode(Encoding.UTF8.GetString(buffer.ToArray()));
        }
        catch (Exception error) when (error is JsonException or FormatException or IOException)
        {
            return [];
        }
    }

    /// <summary>
    /// Decodes <c>{"entries":[{"version":"2610.01.02","released":true,"items":["…"],"groups":[…],"testflight":{…}}]}</c>,
    /// bounded to <see cref="MaxEntries"/> entries, <see cref="MaxItems"/> bullets and <see cref="MaxItemLength"/> characters;
    /// versions without bullets are skipped. <c>groups</c> and <c>testflight.groups</c> are used as written
    /// (<c>versioning.py</c> owns the categories); without them the flat <c>items</c>/<c>vs_release</c> become one
    /// uncategorized group.
    /// </summary>
    /// <param name="text">JSON document.</param>
    /// <returns>Entries, one "Version X" section each.</returns>
    /// <exception cref="FormatException">The document is not the expected shape.</exception>
    /// <exception cref="JsonException">The text is not JSON.</exception>
    public static IReadOnlyList<ChangelogEntry> Decode(string text)
    {
        using var document = JsonDocument.Parse(text);
        if (document.RootElement.ValueKind != JsonValueKind.Object ||
            !document.RootElement.TryGetProperty("entries", out var list) || list.ValueKind != JsonValueKind.Array)
        {
            throw new FormatException("missing entries");
        }
        var entries = new List<ChangelogEntry>();
        foreach (var entry in list.EnumerateArray().Take(MaxEntries))
        {
            if (entry.ValueKind != JsonValueKind.Object ||
                !entry.TryGetProperty("version", out var versionElement) || versionElement.ValueKind != JsonValueKind.String)
            {
                throw new FormatException("entry without version");
            }
            var version = versionElement.GetString()!;
            if (version.Length > MaxVersionLength) version = version[..MaxVersionLength];
            var released = !entry.TryGetProperty("released", out var releasedElement) || releasedElement.ValueKind != JsonValueKind.False;
            List<string> items = [.. Strings(entry, "items").Take(MaxItems)];
            if (version.Length == 0 || items.Count == 0) continue;
            var groups = DecodeGroups(entry, MaxItems);
            entries.Add(new ChangelogEntry([new ChangelogSection($"Version {version}", items)], version, released)
            {
                Groups = groups.Count > 0 ? groups : [new ChangelogGroup(null, items)],
                Tester = entry.TryGetProperty("testflight", out var tester) && tester.ValueKind == JsonValueKind.Object ? DecodeTester(tester) : null,
            });
        }
        return entries;
    }

    /// <summary>Bounded, trimmed, non-empty strings of an array property (non-strings skipped).</summary>
    /// <param name="parent">Object holding the property.</param>
    /// <param name="name">Property name.</param>
    /// <returns>Strings of at most <see cref="MaxItemLength"/> characters.</returns>
    private static IEnumerable<string> Strings(JsonElement parent, string name) =>
        parent.TryGetProperty(name, out var array) && array.ValueKind == JsonValueKind.Array
            ? array.EnumerateArray()
                .Where(item => item.ValueKind == JsonValueKind.String)
                .Select(item => item.GetString()!.Trim())
                .Select(item => item.Length > MaxItemLength ? item[..MaxItemLength] : item)
                .Where(item => item.Length > 0)
            : [];

    /// <summary>Decodes a <c>groups</c> array (<c>[{category, items}]</c>) in order; malformed groups are skipped.</summary>
    /// <param name="parent">Object holding <c>groups</c>.</param>
    /// <param name="limit">Most bullets kept across all groups.</param>
    /// <returns>Non-empty groups, bounded by <see cref="MaxGroups"/> and <paramref name="limit"/>.</returns>
    public static IReadOnlyList<ChangelogGroup> DecodeGroups(JsonElement parent, int limit)
    {
        var groups = new List<ChangelogGroup>();
        if (!parent.TryGetProperty("groups", out var array) || array.ValueKind != JsonValueKind.Array) return groups;
        var budget = limit;
        foreach (var group in array.EnumerateArray())
        {
            if (budget <= 0 || groups.Count >= MaxGroups) break;
            if (group.ValueKind != JsonValueKind.Object) continue;
            string? category = group.TryGetProperty("category", out var name) && name.ValueKind == JsonValueKind.String ? name.GetString()!.Trim() : null;
            if (category is { Length: > MaxCategoryLength }) category = category[..MaxCategoryLength];
            if (category is { Length: 0 }) category = null;
            List<string> items = [.. Strings(group, "items").Take(budget)];
            budget -= items.Count;
            if (items.Count > 0) groups.Add(new ChangelogGroup(category, items));
        }
        return groups;
    }

    /// <summary>Decodes the <c>testflight</c> block (<c>{since, new, release, vs_release, groups}</c>).</summary>
    /// <param name="block">The block.</param>
    /// <returns>Tester notes, or <see langword="null"/> when it lists nothing.</returns>
    private static TesterNotes? DecodeTester(JsonElement block)
    {
        string? release = block.TryGetProperty("release", out var value) && value.ValueKind == JsonValueKind.String ? value.GetString()!.Trim() : null;
        if (release is { Length: > MaxVersionLength }) release = release[..MaxVersionLength];
        if (release is { Length: 0 }) release = null;
        var groups = DecodeGroups(block, MaxTesterItems);
        if (groups.Count == 0)
        {
            List<string> flat = [.. Strings(block, "vs_release").Take(MaxTesterItems)];
            if (flat.Count > 0) groups = [new ChangelogGroup(null, flat)];
        }
        return groups.Count > 0 ? new TesterNotes(release, groups) : null;
    }

    /// <summary>
    /// The What's New list for an install channel: one block per entry, newest first. Tester installs see the built
    /// version's tester list (every note since the latest release, like TestFlight "What to Test") in place of its
    /// release block; Store installs never do. Manual mentions are dropped (see <see cref="DisplayEntries"/>).
    /// </summary>
    /// <param name="channel">How this copy was installed.</param>
    /// <param name="entries">Entries (defaults to <see cref="Entries"/>).</param>
    /// <returns>Non-empty blocks.</returns>
    public static IReadOnlyList<WhatsNewBlock> DisplayBlocks(InstallChannel channel, IReadOnlyList<ChangelogEntry>? entries = null)
    {
        var blocks = new List<WhatsNewBlock>();
        foreach (var entry in entries ?? Entries)
        {
            var tester = channel == InstallChannel.Tester ? entry.Tester : null;
            if (tester is null && (entry.Sections.Count == 0 || entry.Sections.All(section => MentionsManual(section.Title)))) continue;
            var title = tester?.Title ?? entry.Sections[0].DisplayTitle;
            var source = tester?.Groups ?? (entry.Groups.Count > 0 ? entry.Groups : [.. entry.Sections.Select(section => new ChangelogGroup(null, section.Items))]);
            List<ChangelogGroup> groups =
            [
                .. source
                    .Select(group => group with { Items = [.. group.Items.Where(item => !MentionsManual(item))] })
                    .Where(group => group.Items.Count > 0),
            ];
            if (groups.Count > 0) blocks.Add(new WhatsNewBlock(title, groups));
        }
        return blocks;
    }

    /// <summary>Minor words kept lower case after the first word of a heading.</summary>
    private static readonly HashSet<string> MinorWords =
        ["a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs"];

    /// <summary>Entries as natives show them: the deprecated Manual is never advertised; emptied sections are dropped.</summary>
    /// <param name="entries">Entries (defaults to <see cref="Entries"/>).</param>
    /// <returns>Displayable entries.</returns>
    public static IReadOnlyList<ChangelogEntry> DisplayEntries(IReadOnlyList<ChangelogEntry>? entries = null) =>
    [
        .. (entries ?? Entries)
            .Select(entry => entry with { Sections = [
                .. entry.Sections
                    .Where(section => !MentionsManual(section.Title))
                    .Select(section => section with { Items = [.. section.Items.Where(item => !MentionsManual(item))] })
                    .Where(section => section.Items.Count > 0),
            ] })
            .Where(entry => entry.Sections.Count > 0),
    ];

    /// <summary>Whether text names the in-app Manual as a whole word, any case.</summary>
    /// <param name="text">Heading or bullet.</param>
    /// <returns><see langword="true"/> when it mentions "manual".</returns>
    public static bool MentionsManual(string text) =>
        new string([.. text.ToLowerInvariant().Select(c => char.IsLetter(c) ? c : ' ')])
            .Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains("manual");

    /// <summary>Title Case with minor words lower case after the first.</summary>
    /// <param name="text">Heading.</param>
    /// <returns>Title Case heading.</returns>
    public static string TitleCase(string text) => string.Join(' ',
        text.ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries).Select((word, index) =>
            index > 0 && MinorWords.Contains(word) ? word : char.ToUpperInvariant(word[0]) + word[1..]));

    /// <summary>
    /// The web's <c>calculateChangelogHash</c>: 32-bit <c>((h &lt;&lt; 5) - h) + code</c> over the UTF-16 units of
    /// <c>JSON.stringify(entries)</c>, printed in signed base 36.
    /// </summary>
    /// <param name="entries">Entries.</param>
    /// <returns>Hash identical to the web's for identical data.</returns>
    public static string Hash(IReadOnlyList<ChangelogEntry> entries)
    {
        var value = 0;
        foreach (var unit in CanonicalJson(entries))
        {
            unchecked { value = (value << 5) - value + unit; }
        }
        return Base36(value);
    }

    /// <summary>Signed base-36 like JavaScript's <c>Number.prototype.toString(36)</c>.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Digits with a leading minus for negatives.</returns>
    public static string Base36(int value)
    {
        if (value == 0) return "0";
        var magnitude = Math.Abs((long)value);
        var digits = new StringBuilder();
        while (magnitude > 0)
        {
            digits.Insert(0, "0123456789abcdefghijklmnopqrstuvwxyz"[(int)(magnitude % 36)]);
            magnitude /= 36;
        }
        return (value < 0 ? "-" : "") + digits;
    }

    /// <summary><c>JSON.stringify</c> of the entries (no whitespace; key order sections → title, items).</summary>
    /// <param name="entries">Entries.</param>
    /// <returns>Compact JSON.</returns>
    public static string CanonicalJson(IReadOnlyList<ChangelogEntry> entries) =>
        "[" + string.Join(',', entries.Select(entry =>
            "{\"sections\":[" + string.Join(',', entry.Sections.Select(section =>
                "{\"title\":" + JsonString(section.Title) + ",\"items\":[" + string.Join(',', section.Items.Select(JsonString)) + "]}")) + "]}")) + "]";

    /// <summary>Quotes a string the way <c>JSON.stringify</c> does.</summary>
    /// <param name="text">Raw text.</param>
    /// <returns>JSON string literal.</returns>
    public static string JsonString(string text)
    {
        var builder = new StringBuilder("\"");
        foreach (var c in text)
        {
            builder.Append(c switch
            {
                '"' => "\\\"",
                '\\' => "\\\\",
                '\n' => "\\n",
                '\r' => "\\r",
                '\t' => "\\t",
                '\b' => "\\b",
                '\f' => "\\f",
                < ' ' => "\\u" + ((int)c).ToString("x4", CultureInfo.InvariantCulture),
                _ => c.ToString(),
            });
        }
        return builder.Append('"').ToString();
    }
}
#endregion

#region Launch mode
/// <summary>How the launch What's New dialog behaves (<c>--whats-new off|on|fresh|force</c>, <c>FST_DEBUG_WHATS_NEW</c>).</summary>
public enum WhatsNewMode
{
    /// <summary>Show when the stored hash differs (Release default, <c>on</c>).</summary>
    Normal,
    /// <summary>Never show automatically (Debug/automation default); Settings replay still works.</summary>
    Off,
    /// <summary>Forget the stored dismissal once, then behave as <see cref="Normal"/>.</summary>
    Fresh,
    /// <summary>Show on every launch.</summary>
    Force,
}

/// <summary>What's New launch rules (web <c>App.tsx</c>: <c>hasNewChangelog &amp;&amp; !changelogDismissed</c>).</summary>
public static class WhatsNewGate
{
    /// <summary>Resolves the mode; the flag wins over the environment.</summary>
    /// <param name="args">Command-line arguments.</param>
    /// <param name="environment">Environment lookup (hooks-enabled launches only).</param>
    /// <param name="debugBuild">Debug or automation launch (unset means <see cref="WhatsNewMode.Off"/>).</param>
    /// <returns>Mode.</returns>
    public static WhatsNewMode Parse(IReadOnlyList<string> args, Func<string, string?> environment, bool debugBuild)
    {
        string? value = null;
        for (var i = 0; i < args.Count; i++)
        {
            if (args[i].StartsWith("--whats-new=", StringComparison.OrdinalIgnoreCase)) value = args[i]["--whats-new=".Length..];
            else if (string.Equals(args[i], "--whats-new", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Count) value = args[++i];
        }
        value ??= environment("FST_DEBUG_WHATS_NEW");
        return value?.Trim().ToLowerInvariant() switch
        {
            "on" => WhatsNewMode.Normal,
            "off" => WhatsNewMode.Off,
            "fresh" => WhatsNewMode.Fresh,
            "force" => WhatsNewMode.Force,
            _ => debugBuild ? WhatsNewMode.Off : WhatsNewMode.Normal,
        };
    }

    /// <summary>Whether this launch owes the dialog.</summary>
    /// <param name="mode">Mode (after any <see cref="WhatsNewMode.Fresh"/> reset).</param>
    /// <param name="seenHash">Stored dismissal hash, or <see langword="null"/>.</param>
    /// <param name="currentHash">Current changelog hash.</param>
    /// <returns><see langword="true"/> to present; an empty changelog is never presented.</returns>
    public static bool IsPending(WhatsNewMode mode, string? seenHash, string currentHash) => mode switch
    {
        _ when currentHash == Changelog.EmptyHash => false,
        WhatsNewMode.Off => false,
        WhatsNewMode.Force => true,
        _ => seenHash != currentHash,
    };

    /// <summary>Dialog title, e.g. "What's New · 1.0.0".</summary>
    /// <param name="version">App version (omitted when empty).</param>
    /// <returns>Title.</returns>
    public static string Title(string version) => version.Length == 0 ? "What's New" : $"What's New · {version}";
}
#endregion
