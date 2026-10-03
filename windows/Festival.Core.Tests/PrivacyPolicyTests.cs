using System.Text;
using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>Settings → Privacy Policy (issue #98): the shared contract parses, validates and links consistently.</summary>
public sealed class PrivacyPolicyTests
{
    private static byte[] Utf8(string json) => Encoding.UTF8.GetBytes(json);

    [Fact]
    public void SharedContract_ParsesEverySectionInOrder()
    {
        var policy = PrivacyPolicy.Parse(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "fixtures", PrivacyPolicy.AssetFileName)));

        Assert.Equal("Privacy Policy", policy.Title);
        Assert.Equal("2026-10-03", policy.EffectiveDate);
        Assert.Equal("Effective October 3, 2026", policy.EffectiveDateText);
        Assert.False(policy.IsEmpty);
        Assert.Equal(
            ["overview", "information-collected", "how-used", "public-game-data", "third-parties", "retention", "your-rights", "children", "security", "changes", "contact"],
            policy.Sections.Select(s => s.Id));
        Assert.All(policy.Sections, s => Assert.NotEmpty(s.Blocks));
        Assert.Contains(policy.Sections.SelectMany(s => s.Blocks), b => b.IsBullets && b.Items.Count > 0);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("{not json")]
    [InlineData("""{"schema":2,"title":"Future","sections":[{"id":"a","title":"A","blocks":[{"kind":"paragraph","text":"x"}]}]}""")]
    [InlineData("null")]
    public void MissingMalformedOrUnsupported_YieldsEmptyTitledPolicy(string? json)
    {
        var policy = PrivacyPolicy.Parse(json is null ? null : Utf8(json));

        Assert.True(policy.IsEmpty);
        Assert.Equal(PrivacyPolicy.DefaultTitle, policy.Title);
        Assert.Equal("", policy.EffectiveDateText);
    }

    [Fact]
    public void Oversized_IsRejected()
    {
        var policy = PrivacyPolicy.Parse(new byte[1_000_001]);

        Assert.True(policy.IsEmpty);
        Assert.Equal(PrivacyPolicy.DefaultTitle, policy.Title);
    }

    [Fact]
    public void InvalidContent_IsDroppedAndBlankTitleDefaults()
    {
        const string json = """
            {"schema":1,"title":" ","effectiveDateText":"Effective now","sections":[
              {"id":"keep","title":"Keep","blocks":[
                {"kind":"paragraph","text":"Hello"},
                {"kind":"paragraph","text":"  "},
                {"kind":"table","text":"ignored"},
                {"kind":"bullets","items":["One"," ","Two"]},
                {"kind":"bullets","items":[]}
              ]},
              {"id":"untitled","title":"","blocks":[{"kind":"paragraph","text":"x"}]},
              {"id":"empty","title":"Empty","blocks":[{"kind":"paragraph","text":""}]}
            ]}
            """;

        var policy = PrivacyPolicy.Parse(Utf8(json));

        Assert.Equal(PrivacyPolicy.DefaultTitle, policy.Title);
        Assert.Equal("Effective now", policy.EffectiveDateText);
        var section = Assert.Single(policy.Sections);
        Assert.Equal("keep", section.Id);
        Assert.Equal(
            [
                new PrivacyPolicyBlock { Kind = PrivacyPolicyBlock.Paragraph, Text = "Hello" },
                new PrivacyPolicyBlock { Kind = PrivacyPolicyBlock.Bullets, Items = ["One", "Two"] },
            ],
            section.Blocks);
    }

    [Fact]
    public void Runs_LinksHttpsAndKeepsTrailingPunctuationPlain()
    {
        var runs = PrivacyPolicy.Runs("Open https://github.com/SFenton/FestivalNativeApps/issues. Or http://plain.example, then https://a.example/x).");

        Assert.Equal(
            [
                ("Open ", null),
                ("https://github.com/SFenton/FestivalNativeApps/issues", new Uri("https://github.com/SFenton/FestivalNativeApps/issues")),
                (". Or http://plain.example, then ", null),
                ("https://a.example/x", new Uri("https://a.example/x")),
                (").", null),
            ],
            runs);
        Assert.Equal("Open https://github.com/SFenton/FestivalNativeApps/issues. Or http://plain.example, then https://a.example/x).", string.Concat(runs.Select(r => r.Text)));
    }

    [Theory]
    [InlineData("")]
    [InlineData("No links here.")]
    [InlineData("Bare https:// is not a link")]
    public void Runs_WithoutLinks_IsPlain(string text)
    {
        var runs = PrivacyPolicy.Runs(text);

        Assert.All(runs, r => Assert.Null(r.Link));
        Assert.Equal(text, string.Concat(runs.Select(r => r.Text)));
    }
}
