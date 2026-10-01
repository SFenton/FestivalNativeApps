using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Festival.Core.Domain;

#region Model
/// <summary>One titled group of changelog bullets (web <c>ChangelogSection</c>, <c>FortniteFestivalWeb/src/changelog.ts</c>).</summary>
/// <param name="Title">Heading as generated (e.g. "Version 2610.01").</param>
/// <param name="Items">Bullets in web order.</param>
public sealed record ChangelogSection(string Title, IReadOnlyList<string> Items)
{
    /// <summary>Native Title Case heading ("SONG DETAILS" → "Song Details").</summary>
    public string DisplayTitle => Changelog.TitleCase(Title);
}

/// <summary>One version's sections (web <c>ChangelogEntry</c>).</summary>
/// <param name="Sections">Sections in display order.</param>
/// <param name="Version">Windows app version (<c>YYMM.NN</c>), or <see langword="null"/> for unversioned data.</param>
/// <param name="Released">Whether the version reached the Store (the newest entry is the build itself).</param>
public sealed record ChangelogEntry(IReadOnlyList<ChangelogSection> Sections, string? Version = null, bool Released = true);
#endregion

#region Catalogue
/// <summary>
/// The "What's New" changelog: one "Version YYMM.NN" section per released Windows version plus the built one,
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
    /// Decodes <c>{"entries":[{"version":"2610.02","released":true,"items":["…"]}]}</c>, bounded to
    /// <see cref="MaxEntries"/> entries, <see cref="MaxItems"/> bullets and <see cref="MaxItemLength"/> characters;
    /// versions without bullets are skipped.
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
            List<string> items = entry.TryGetProperty("items", out var itemsElement) && itemsElement.ValueKind == JsonValueKind.Array
                ? [.. itemsElement.EnumerateArray()
                    .Where(item => item.ValueKind == JsonValueKind.String)
                    .Select(item => item.GetString()!.Trim())
                    .Select(item => item.Length > MaxItemLength ? item[..MaxItemLength] : item)
                    .Where(item => item.Length > 0)
                    .Take(MaxItems)]
                : [];
            if (version.Length == 0 || items.Count == 0) continue;
            entries.Add(new ChangelogEntry([new ChangelogSection($"Version {version}", items)], version, released));
        }
        return entries;
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
