using System.Reflection;
using Festival.Core.Domain;

[assembly: AssemblyMetadata(AppVersionInfo.GitShaMetadataKey, "ABCDEF0123456789")]

namespace Festival.Core.Tests;

public class AppVersionInfoTests
{
    [Theory]
    [InlineData("2610.01.01", "2610.01.01")]
    [InlineData("2610.01.01+76249dfed1412262", "2610.01.01")]
    [InlineData("  ", "0.1.0")]
    [InlineData(null, "0.1.0")]
    public void DisplayPrefersTheStampedReleaseVersion(string? informational, string expected) =>
        Assert.Equal(expected, AppVersionInfo.Display(informational, new Version(0, 1, 0, 0)));

    [Fact]
    public void DisplayIsEmptyWithoutAnyVersion() => Assert.Equal("", AppVersionInfo.Display(null, null));

    [Fact]
    public void DisplayReadsAnAssembly() =>
        Assert.False(string.IsNullOrWhiteSpace(AppVersionInfo.Display(typeof(AppVersionInfo).Assembly)));

    [Fact]
    public void StampedCommitAppendsItsFirstSevenCharacters() =>
        Assert.Equal("2610.01.01 · 42edc57", AppVersionInfo.WithCommit("2610.01.01", "42edc57a1b2c3d4e5f60718293a4b5c6d7e8f901"));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData("dev")]
    [InlineData("DEV")]
    [InlineData("$(SourceRevisionId)")]
    [InlineData("main")]
    public void MissingDevEmptyOrNonHexCommitsKeepTheVersionText(string? sha) =>
        Assert.Equal("0.1.0", AppVersionInfo.WithCommit("0.1.0", sha));

    [Fact]
    public void AnUnknownVersionStaysEmptySoSettingsShowsUnknown() =>
        Assert.Equal("", AppVersionInfo.WithCommit("", "42edc57"));

    [Theory]
    [InlineData("ABC12", "abc12")]
    [InlineData(" 42EDC57FF\n", "42edc57")]
    public void ShortAndUpperCaseShasAreNormalised(string raw, string expected) =>
        Assert.Equal(expected, AppVersionInfo.ShortCommit(raw));

    [Fact]
    public void SettingsTextKeepsTheDisplayVersionPrefix()
    {
        var assembly = typeof(AppVersionInfo).Assembly;
        Assert.StartsWith(AppVersionInfo.Display(assembly), AppVersionInfo.SettingsText(assembly), StringComparison.Ordinal);
    }

    [Fact]
    public void SettingsTextReadsTheStampedAssemblyMetadata()
    {
        var assembly = typeof(AppVersionInfoTests).Assembly;
        Assert.Equal(AppVersionInfo.Display(assembly) + " · abcdef0", AppVersionInfo.SettingsText(assembly));
    }
}
