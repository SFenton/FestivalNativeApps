using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

// Issue #23: the command-row rules shared by every Windows modal dialog.
public class ModalCommandsTests
{
    [Theory]
    [InlineData("", "", "", 0)]
    [InlineData("", "", "Close", 1)]
    [InlineData("Reset", "", "Cancel", 2)]
    [InlineData("Next", "Back", "Close", 3)]
    [InlineData("OK", "Don't Show Again", "", 2)]
    [InlineData(null, "  ", "Dismiss", 1)]
    public void Count_IgnoresHiddenButtons(string? primary, string? secondary, string? close, int expected) =>
        Assert.Equal(expected, ModalCommands.Count(primary, secondary, close));

    [Theory]
    [InlineData("", "", "Close", true)]
    [InlineData("Done", "", "", true)]
    [InlineData("Reset", "", "Cancel", false)]
    [InlineData("", "", "", false)]
    public void SpansFullWidth_OnlyForOneButton(string primary, string secondary, string close, bool expected) =>
        Assert.Equal(expected, ModalCommands.SpansFullWidth(primary, secondary, close));

    [Fact]
    public void Close_IsTheStandardLabel() => Assert.Equal("Close", ModalCommands.Close);
}