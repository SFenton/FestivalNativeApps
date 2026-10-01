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
}
