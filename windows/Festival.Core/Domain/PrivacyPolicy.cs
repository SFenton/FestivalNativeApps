using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Festival.Core.Domain;

#region Policy
/// <summary>One block of policy body text: a paragraph (<see cref="Text"/>) or a bullet list (<see cref="Items"/>).</summary>
public sealed record PrivacyPolicyBlock
{
    /// <summary>Wire <c>kind</c> of a paragraph.</summary>
    public const string Paragraph = "paragraph";

    /// <summary>Wire <c>kind</c> of a bullet list.</summary>
    public const string Bullets = "bullets";

    /// <summary><see cref="Paragraph"/> or <see cref="Bullets"/>.</summary>
    [JsonPropertyName("kind")] public string Kind { get; init; } = "";
    /// <summary>Paragraph text.</summary>
    [JsonPropertyName("text")] public string Text { get; init; } = "";
    /// <summary>Bullet items, in order.</summary>
    [JsonPropertyName("items")] public List<string> Items { get; init; } = [];

    /// <summary>Whether this is a bullet list.</summary>
    [JsonIgnore] public bool IsBullets => Kind == Bullets;

    /// <inheritdoc />
    public bool Equals(PrivacyPolicyBlock? other) =>
        other is not null && Kind == other.Kind && Text == other.Text && Items.SequenceEqual(other.Items);

    /// <inheritdoc />
    public override int GetHashCode() => HashCode.Combine(Kind, Text, Items.Count);
}

/// <summary>One titled policy section.</summary>
public sealed record PrivacyPolicySection
{
    /// <summary>Stable ID (UI Automation suffix).</summary>
    [JsonPropertyName("id")] public string Id { get; init; } = "";
    /// <summary>Heading.</summary>
    [JsonPropertyName("title")] public string Title { get; init; } = "";
    /// <summary>Body.</summary>
    [JsonPropertyName("blocks")] public List<PrivacyPolicyBlock> Blocks { get; init; } = [];
}

/// <summary>
/// The Privacy Policy (issue #98). The app bundles the shared <c>contracts/privacy-policy.json</c> itself (linked as
/// <c>Assets\privacy-policy.json</c>), so the wording matches every other client.
/// </summary>
public sealed partial record PrivacyPolicy
{
    /// <summary>Supported contract schema.</summary>
    public const int SupportedSchema = 1;

    /// <summary>Title used when the file cannot be read (never blank).</summary>
    public const string DefaultTitle = "Privacy Policy";

    /// <summary>Bundled file name under <c>Assets</c>.</summary>
    public const string AssetFileName = "privacy-policy.json";

    /// <summary>Contract schema version.</summary>
    [JsonPropertyName("schema")] public int Schema { get; init; }
    /// <summary>Dialog title.</summary>
    [JsonPropertyName("title")] public string Title { get; init; } = "";
    /// <summary>ISO date the policy took effect.</summary>
    [JsonPropertyName("effectiveDate")] public string EffectiveDate { get; init; } = "";
    /// <summary>Display form of <see cref="EffectiveDate"/>.</summary>
    [JsonPropertyName("effectiveDateText")] public string EffectiveDateText { get; init; } = "";
    /// <summary>Sections in reading order.</summary>
    [JsonPropertyName("sections")] public List<PrivacyPolicySection> Sections { get; init; } = [];

    /// <summary>Whether there is no content to show.</summary>
    [JsonIgnore] public bool IsEmpty => Sections.Count == 0;

    /// <summary>
    /// Parses and validates the policy: unknown block kinds, blank paragraphs, blank bullet items, and sections without a
    /// title or any remaining block are dropped. Malformed, oversized or missing bytes, or an unsupported schema, yield an
    /// empty policy titled <see cref="DefaultTitle"/>.
    /// </summary>
    /// <param name="bytes">File bytes, or <see langword="null"/> when missing.</param>
    /// <returns>Policy.</returns>
    public static PrivacyPolicy Parse(byte[]? bytes)
    {
        var empty = new PrivacyPolicy { Schema = SupportedSchema, Title = DefaultTitle };
        if (bytes is not { Length: > 0 and <= 1_000_000 }) return empty;
        PrivacyPolicy? decoded;
        try
        {
            decoded = JsonSerializer.Deserialize(bytes, PrivacyPolicyJsonContext.Default.PrivacyPolicy);
        }
        catch (JsonException)
        {
            return empty;
        }
        if (decoded is null || decoded.Schema != SupportedSchema) return empty;
        var sections = new List<PrivacyPolicySection>();
        foreach (var section in decoded.Sections ?? [])
        {
            if (section is null || string.IsNullOrWhiteSpace(section.Title)) continue;
            var blocks = new List<PrivacyPolicyBlock>();
            foreach (var block in section.Blocks ?? [])
            {
                if (block?.Kind == PrivacyPolicyBlock.Paragraph && !string.IsNullOrWhiteSpace(block.Text))
                {
                    blocks.Add(new PrivacyPolicyBlock { Kind = PrivacyPolicyBlock.Paragraph, Text = block.Text });
                }
                else if (block?.Kind == PrivacyPolicyBlock.Bullets)
                {
                    var items = (block.Items ?? []).Where(i => !string.IsNullOrWhiteSpace(i)).ToList();
                    if (items.Count > 0) blocks.Add(new PrivacyPolicyBlock { Kind = PrivacyPolicyBlock.Bullets, Items = items });
                }
            }
            if (blocks.Count > 0) sections.Add(section with { Id = section.Id ?? "", Blocks = blocks });
        }
        return decoded with
        {
            Title = string.IsNullOrWhiteSpace(decoded.Title) ? DefaultTitle : decoded.Title,
            EffectiveDate = decoded.EffectiveDate ?? "",
            EffectiveDateText = decoded.EffectiveDateText ?? "",
            Sections = sections,
        };
    }

    /// <summary>
    /// Splits a line of policy text into plain and HTTPS-link runs so the UI can make links activatable. Trailing
    /// sentence punctuation (<c>. , ; : )</c>) stays plain text.
    /// </summary>
    /// <param name="text">Paragraph or bullet text.</param>
    /// <returns>Runs in order; <c>Link</c> is the absolute URI of a link run, otherwise <see langword="null"/>.</returns>
    public static IReadOnlyList<(string Text, Uri? Link)> Runs(string text)
    {
        var runs = new List<(string, Uri?)>();
        var cursor = 0;
        foreach (Match match in UrlPattern().Matches(text))
        {
            var url = match.Value.TrimEnd('.', ',', ';', ':', ')');
            if (url.Length <= "https://".Length || !Uri.TryCreate(url, UriKind.Absolute, out var uri)) continue;
            if (match.Index > cursor) runs.Add((text[cursor..match.Index], null));
            runs.Add((url, uri));
            cursor = match.Index + url.Length;
        }
        if (cursor < text.Length) runs.Add((text[cursor..], null));
        return runs;
    }

    [GeneratedRegex(@"https://\S+")]
    private static partial Regex UrlPattern();
}
#endregion
