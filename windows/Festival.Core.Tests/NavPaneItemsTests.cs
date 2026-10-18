namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #672: the shell creates one pane item per section once and only collapses the hidden ones. Removing a
/// <c>NavigationViewItem</c> leaves its SplitView DisplayMode callback live, and the next adaptive narrow to Compact
/// (after a player deselect or reselect changed the sections) can fail natively on it and end the process
/// (microsoft/microsoft-ui-xaml#10757).
/// </summary>
public class NavPaneItemsTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    [Fact]
    public void ShellNeverRemovesPaneItems()
    {
        var shell = File.ReadAllText(Path.Combine(AppRoot, "MainWindow.xaml.cs"))
            + File.ReadAllText(Path.Combine(AppRoot, "MainWindow.Accessibility.cs"));
        Assert.DoesNotContain("MenuItems.Clear(", shell, StringComparison.Ordinal);
        Assert.DoesNotContain("MenuItems.Remove", shell, StringComparison.Ordinal);
        Assert.Contains("item.Visibility = ", shell, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(false, false)]
    [InlineData(false, true)]
    [InlineData(true, false)]
    [InlineData(true, true)]
    public void VisibleSectionsAreAnOrderedSubsetOfTheFullPane(bool hasPlayer, bool hideShop)
    {
        var full = AppSections.Visible(hasPlayer: true);
        var visible = AppSections.Visible(hasPlayer, hideShop);
        Assert.Equal(visible, full.Where(visible.Contains));
    }
}
