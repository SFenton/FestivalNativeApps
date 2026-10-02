using Festival.Core.Domain;

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

    [Theory]
    [InlineData("2610.01.02", "42EDC57a1b2c3d4e5f60718293a4b5c6d7e8f901", "2610.01.02 · 42edc57")]
    [InlineData("2610.01.02", " abcdef0 ", "2610.01.02 · abcdef0")]
    [InlineData("0.1.0", null, "0.1.0")]
    [InlineData("0.1.0", "", "0.1.0")]
    [InlineData("0.1.0", "dev", "0.1.0")]
    [InlineData("0.1.0", "abc12", "0.1.0")]
    [InlineData("0.1.0", "$(FstGitSha)", "0.1.0")]
    [InlineData("", "abcdef0123", "abcdef0")]
    public void SettingsTextAppendsTheShortCommit(string display, string? sha, string expected) =>
        Assert.Equal(expected, AppVersionInfo.SettingsText(display, sha));

    [Fact]
    public void BuildStampsTheCheckedOutCommit()
    {
        // windows/Directory.Build.targets stamps FSTGitSHA into every assembly built from a git checkout.
        var text = AppVersionInfo.SettingsText(typeof(AppVersionInfo).Assembly);
        var sha = typeof(AppVersionInfo).Assembly.GetCustomAttributes(typeof(System.Reflection.AssemblyMetadataAttribute), false)
            .Cast<System.Reflection.AssemblyMetadataAttribute>().FirstOrDefault(a => a.Key == AppVersionInfo.GitShaKey)?.Value;
        Assert.NotNull(sha);
        Assert.Equal($"{AppVersionInfo.Display(typeof(AppVersionInfo).Assembly)} · {sha![..7].ToLowerInvariant()}", text);
    }
}
