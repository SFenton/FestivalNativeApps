using System.Xml.Linq;
using Xunit;

namespace Festival.Core.Tests;

#region UI automation scaffold
/// <summary>Static UI shell checks; interactive UIA and screenshots remain separate gates.</summary>
public sealed class UiMarkupTests
{
    /// <summary>Verifies that native navigation and named UIA entry points remain available.</summary>
    [Fact]
    public void ShellUsesNativeNavigationWithDiscoverablePages()
    {
        var shell = XDocument.Load("MainWindow.xaml");
        XNamespace ui = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        Assert.Single(shell.Descendants(ui + "NavigationView"));
        Assert.Single(shell.Descendants(ui + "NavigationViewItem"),
            item => (string?)item.Attribute("Tag") == "songs");
        Assert.Equal("True", (string?)shell.Descendants(ui + "NavigationView")
            .Single().Attribute("IsSettingsVisible"));
        Assert.Contains("fst.shell.navigation", File.ReadAllText("MainWindow.xaml"));
        Assert.Contains("fst.songs.difficulty-meter", File.ReadAllText("SongsPage.xaml"));
        Assert.Contains("fst.settings.connection-mode", File.ReadAllText("SettingsPage.xaml"));
    }

    /// <summary>Verifies the native meter has seven distinct bars in the declared 62 by 20 area.</summary>
    [Fact]
    public void DifficultyMeterHasSevenBars()
    {
        var meter = XDocument.Load("DifficultyMeter.xaml");
        XNamespace ui = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        var stack = meter.Descendants(ui + "StackPanel").Single();
        Assert.Equal("62", (string?)stack.Attribute("Width"));
        Assert.Equal("20", (string?)stack.Attribute("Height"));
        Assert.Equal(7, stack.Elements(ui + "Rectangle").Count());
    }
}
#endregion
