using Festival.Core.Domain;

namespace Festival.Core.Tests;

public class KeyboardShortcutsTests
{
    [Fact]
    public void For_NumbersVisibleSectionsInPaneOrder_AndSettingsUsesCtrlComma()
    {
        var shortcuts = KeyboardShortcuts.For(AppSections.Visible(hasPlayer: true));
        Assert.Equal([AppSection.Songs, AppSection.Suggestions, AppSection.Statistics, AppSection.Rivals, AppSection.Leaderboards, AppSection.Shop, AppSection.Settings],
            shortcuts.Select(s => s.Section));
        Assert.Equal([1, 2, 3, 4, 5, 6, null], shortcuts.Select(s => s.Digit));
        Assert.Equal("Songs (Ctrl+1)", shortcuts[0].ToolTip);
        Assert.Equal("Item Shop (Ctrl+6)", shortcuts[5].ToolTip);
        Assert.Equal("Settings (Ctrl+,)", shortcuts[^1].ToolTip);
    }

    [Fact]
    public void For_AnonymousWithoutShop_RenumbersAndKeepsAccessKeys()
    {
        var shortcuts = KeyboardShortcuts.For(AppSections.Visible(hasPlayer: false, hideShop: true));
        Assert.Equal(["Songs (Ctrl+1)", "Leaderboards (Ctrl+2)", "Settings (Ctrl+,)"], shortcuts.Select(s => s.ToolTip));
        Assert.Equal(["S", "L", "E"], shortcuts.Select(s => s.AccessKey));
    }

    [Fact]
    public void AccessKeys_AreUniqueSingleLetters()
    {
        var keys = Enum.GetValues<AppSection>().Select(KeyboardShortcuts.AccessKey).ToList();
        Assert.Equal(keys.Count, keys.Distinct().Count());
        Assert.All(keys, k => Assert.Matches("^[A-Z]$", k));
        Assert.Equal(0xBC, KeyboardShortcuts.CommaKey);
    }

    [Theory]
    [InlineData(AppSection.Songs, AppSection.Leaderboards, true, false, true)]
    [InlineData(AppSection.Songs, AppSection.Statistics, true, false, true)]
    [InlineData(AppSection.Leaderboards, AppSection.Leaderboards, true, false, false)]
    [InlineData(AppSection.Songs, AppSection.Leaderboards, false, false, false)]
    [InlineData(AppSection.Songs, AppSection.Leaderboards, true, true, false)]
    [InlineData(AppSection.Songs, AppSection.Settings, true, false, false)]
    [InlineData(AppSection.Settings, AppSection.Songs, true, false, false)]
    public void PaneFocus_RedirectsOnlyEntryFromOutsideWithinTheSameGroup(
        AppSection target, AppSection selected, bool keyboardOrPaneOpen, bool fromInsidePane, bool expected)
    {
        Assert.Equal(expected, PaneFocus.ShouldRedirect(target, selected, keyboardOrPaneOpen, fromInsidePane));
    }
}
