namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #652 (split-panes R7 owner-approved Windows variant): pages no longer host their own fixed-width detail
/// columns; the shell's <c>OnDemandSplitHost</c> opens the iPad/Duo split set beside the list on demand, and Back closes
/// the trailing pane before the section's stack pops.
/// </summary>
public class OnDemandSplitMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    /// <summary>Reads an app source file.</summary>
    /// <param name="parts">Path below Festival.App.</param>
    /// <returns>Text.</returns>
    private static string Read(params string[] parts) => File.ReadAllText(Path.Combine([AppRoot, .. parts]));

    [Theory]
    [InlineData("SongsPage")]
    [InlineData("AllRivalsPage")]
    [InlineData("LeaderboardsFullRankingsPage")]
    [InlineData("LeaderboardsBandRankingsPage")]
    public void PagesHaveNoOwnDetailColumn(string page)
    {
        var markup = Read("Pages", page + ".xaml");
        var code = Read("Pages", page + ".xaml.cs");
        Assert.DoesNotContain("DetailFrame", markup, StringComparison.Ordinal);
        Assert.DoesNotContain("detail-pane", markup, StringComparison.Ordinal);
        Assert.DoesNotContain("SplitWidth", code, StringComparison.Ordinal);
        Assert.DoesNotContain("ApplySplit", code, StringComparison.Ordinal);
    }

    [Fact]
    public void SongsAlwaysPushesSongDetail()
    {
        var code = Read("Pages", "SongsPage.xaml.cs");
        var click = code[code.IndexOf("private void OnSongClick", StringComparison.Ordinal)..];
        click = click[..click.IndexOf("\n    }", StringComparison.Ordinal)];
        Assert.Contains("MainWindow.Instance?.Navigate(", click, StringComparison.Ordinal);
        Assert.DoesNotContain("split", click, StringComparison.Ordinal);
    }

    [Fact]
    public void RowsNoLongerAskAPageToShowTheirRoute()
    {
        Assert.DoesNotContain("IRouteHost", Read("MainWindow.xaml.cs"), StringComparison.Ordinal);
        var row = Read("Controls", "LeaderboardEntryRow.xaml.cs");
        Assert.DoesNotContain("IRouteHost", row, StringComparison.Ordinal);
        Assert.DoesNotContain("IsCurrent =", row, StringComparison.Ordinal);
    }

    [Fact]
    public void ShellRoutesThroughTheSplitAndClosesThePaneFirst()
    {
        var shell = Read("MainWindow.xaml.cs");
        Assert.Contains("split.Decide(route)", shell, StringComparison.Ordinal);
        Assert.Contains("FrameHost.Children.Add(splits[section])", shell, StringComparison.Ordinal);
        var back = shell[shell.IndexOf("private bool GoBack()", StringComparison.Ordinal)..];
        Assert.True(back.IndexOf("TryGoBack() == true", StringComparison.Ordinal) < back.IndexOf("frame.GoBack()", StringComparison.Ordinal));
    }

    [Fact]
    public void HostSplitsInEqualHalvesWithAnAccessibleClose()
    {
        var host = Read("Controls", "OnDemandSplitHost.cs");
        Assert.Contains("public bool AllowsSplit => AllowsSplitAt(ActualWidth);", host, StringComparison.Ordinal);
        Assert.Contains("OnDemandSplitPolicy.AllowsSplit(width, TextScale)", host, StringComparison.Ordinal);
        Assert.Contains("new GridLength(1, GridUnitType.Star)", host, StringComparison.Ordinal);
        Assert.Contains("\"fst.split.close\"", host, StringComparison.Ordinal);
        Assert.Contains("SetName(close, \"Close\")", host, StringComparison.Ordinal);
        Assert.Contains("Width = 40", host, StringComparison.Ordinal);
        Assert.Contains("AccessibilityView.Raw", host, StringComparison.Ordinal);
    }
}
