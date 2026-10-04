namespace Festival.Core.Tests;

/// <summary>The backdrop's UI Automation state names and dim visibility (issue #217).</summary>
public class ArtworkBackgroundStatusTests
{
    [Theory]
    [InlineData(ArtworkMode.Animated, true, false, "animated")]
    [InlineData(ArtworkMode.Static, true, false, "reduced-motion")]
    [InlineData(ArtworkMode.Paused, true, false, "not-visible")]
    [InlineData(ArtworkMode.Hidden, false, false, "save-data")]
    [InlineData(ArtworkMode.Hidden, true, true, "save-data")]
    [InlineData(ArtworkMode.Animated, false, false, "no-art")]
    [InlineData(ArtworkMode.Static, false, false, "no-art")]
    [InlineData(ArtworkMode.Paused, false, false, "no-art")]
    [InlineData(ArtworkMode.Animated, true, true, "song-cover")]
    [InlineData(ArtworkMode.Paused, true, true, "song-cover")]
    [InlineData(ArtworkMode.Static, true, true, "song-cover")]
    [InlineData(ArtworkMode.Paused, false, true, "no-art")]
    public void Status_NamesTheContractState(ArtworkMode mode, bool imageShown, bool showingSong, string expected) =>
        Assert.Equal(expected, ArtworkBackgroundStatus.Resolve(mode, imageShown, showingSong));

    [Theory]
    [InlineData(ArtworkMode.Animated, true, true)]
    [InlineData(ArtworkMode.Static, true, true)]
    [InlineData(ArtworkMode.Paused, true, true)]
    [InlineData(ArtworkMode.Animated, false, false)]
    [InlineData(ArtworkMode.Paused, false, false)]
    [InlineData(ArtworkMode.Hidden, true, false)]
    [InlineData(ArtworkMode.Hidden, false, false)]
    public void Dim_OnlyOverArt(ArtworkMode mode, bool imageShown, bool expected) =>
        Assert.Equal(expected, ArtworkBackgroundStatus.DimShown(mode, imageShown));

    [Fact]
    public void Status_NamesMatchTheProductContract()
    {
        var contract = File.ReadAllText(Path.Combine(RepoRoot(), "contracts", "product.json"));
        foreach (var state in new[]
        {
            ArtworkBackgroundStatus.NoArt, ArtworkBackgroundStatus.Animated, ArtworkBackgroundStatus.ReducedMotion,
            ArtworkBackgroundStatus.SaveData, ArtworkBackgroundStatus.NotVisible,
        })
            Assert.Contains($"\"{state}\"", contract);
    }

    private static string RepoRoot()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
            if (File.Exists(Path.Combine(dir.FullName, "contracts", "product.json"))) return dir.FullName;
        throw new DirectoryNotFoundException("contracts/product.json");
    }
}
