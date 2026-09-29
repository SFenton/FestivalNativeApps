using System.Globalization;
using System.Text;

namespace Festival.Core.Domain;

#region Model
/// <summary>One titled group of changelog bullets (web <c>ChangelogSection</c>, <c>FortniteFestivalWeb/src/changelog.ts</c>).</summary>
/// <param name="Title">Heading exactly as the web data spells it (upper case).</param>
/// <param name="Items">Bullets in web order.</param>
public sealed record ChangelogSection(string Title, IReadOnlyList<string> Items)
{
    /// <summary>Native Title Case heading ("SONG DETAILS" → "Song Details").</summary>
    public string DisplayTitle => Changelog.TitleCase(Title);
}

/// <summary>One release's sections (web <c>ChangelogEntry</c>).</summary>
/// <param name="Sections">Sections in web order.</param>
public sealed record ChangelogEntry(IReadOnlyList<ChangelogSection> Sections);
#endregion

#region Catalogue
/// <summary>
/// The "What's New" changelog, copied verbatim from the web so its content hash equals the web's
/// <c>CURRENT_CHANGELOG_HASH</c> (<c>changelogHash.ts</c>); Apple's <c>Changelog.swift</c> holds the same data. Keep
/// <see cref="Entries"/> byte-identical to the web and update <see cref="WebHash"/> in the same commit.
/// </summary>
public static class Changelog
{
    /// <summary>Web release the entries were copied from.</summary>
    public const string WebVersion = "0.1.133";

    /// <summary>The web's precomputed hash for <see cref="Entries"/>.</summary>
    public const string WebHash = "-6p8bh3";

    /// <summary>Entries exactly as the web ships them.</summary>
    public static IReadOnlyList<ChangelogEntry> Entries { get; } =
    [
        new([
            new("ITEM SHOP", [
                "Newly released songs in the Item Shop have a gold pulse on Songs Page and Song Details.",
                "Songs in the Item Shop that aren't leaving tomorrow now have a green pulse, to match the gold/green/red styles of the instrument chips on Songs Page.",
            ]),
            new("MOBILE", [
                "FAB buttons and other dock buttons now animate in for a more visually pleasing experience.",
                "Fixed a bug in search modal where dismissing the keyboard after results show did not expand results view appropriately.",
            ]),
            new("SONG DETAILS", [
                "Fixed a bug where leaderboard ranks did not reflect the actual Epic leaderboard value in some cases.",
            ]),
            new("NOTIFICATIONS", [
                "Fixed a bug where notification alerts would reset when you re-open the web browser.",
                "Added support for switching profiles/bands and returning to a different profile/band and seeing the appropriate amount of unread notifications, instead of all of them.",
            ]),
            new("RIVALS", [
                "Improved performance when viewing a Rival for the first time.",
                "Improved availability of Rivals during scrape.",
            ]),
            new("LEADERBOARDS", [
                "Changed to instrument icons on combo leaderboards instead of \"Lead + ...\" text.",
                "Updated FAB dock on mobile to match other pages.",
            ]),
        ]),
    ];

    /// <summary>Hash of the current entries; What's New shows once per distinct hash.</summary>
    public static string CurrentHash => Hash(Entries);

    /// <summary>Minor words kept lower case after the first word of a heading.</summary>
    private static readonly HashSet<string> MinorWords =
        ["a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs"];

    /// <summary>Entries as natives show them: the deprecated Manual is never advertised; emptied sections are dropped.</summary>
    /// <param name="entries">Web-identical entries (defaults to <see cref="Entries"/>).</param>
    /// <returns>Displayable entries.</returns>
    public static IReadOnlyList<ChangelogEntry> DisplayEntries(IReadOnlyList<ChangelogEntry>? entries = null) =>
    [
        .. (entries ?? Entries)
            .Select(entry => new ChangelogEntry([
                .. entry.Sections
                    .Where(section => !MentionsManual(section.Title))
                    .Select(section => section with { Items = [.. section.Items.Where(item => !MentionsManual(item))] })
                    .Where(section => section.Items.Count > 0),
            ]))
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
    /// <returns><see langword="true"/> to present.</returns>
    public static bool IsPending(WhatsNewMode mode, string? seenHash, string currentHash) => mode switch
    {
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
