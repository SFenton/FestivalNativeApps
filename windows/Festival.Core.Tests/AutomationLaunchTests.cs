namespace Festival.Core.Tests;

public class AutomationLaunchTests
{
    private const string Folder = @"C:\app";
    private static readonly string Marker = Path.Combine(Folder, AutomationLaunch.MarkerFileName);

    [Theory]
    [InlineData(new[] { "--automation" }, null, true)]
    [InlineData(new[] { "--AUTOMATION" }, null, true)]
    [InlineData(new string[0], "1", true)]
    [InlineData(new string[0], " 1 ", true)]
    [InlineData(new string[0], "0", false)]
    [InlineData(new string[0], null, false)]
    [InlineData(new[] { "--automation-x" }, "true", false)]
    public void IsRequested_FlagOrVariable(string[] args, string? variable, bool expected) =>
        Assert.Equal(expected, AutomationLaunch.IsRequested(args, name => name == AutomationLaunch.Variable ? variable : null));

    [Fact]
    public void Debug_HonoursRequestWithoutMarker()
    {
        Assert.True(AutomationLaunch.Resolve(true, ["--automation"], _ => null, Folder, _ => false));
        Assert.False(AutomationLaunch.Resolve(true, [], _ => null, Folder, _ => true));
    }

    [Fact]
    public void Release_RequiresMarkerNextToExecutable()
    {
        Func<string, string?> env = name => name == AutomationLaunch.Variable ? "1" : null;
        Assert.False(AutomationLaunch.Resolve(false, [], env, Folder, _ => false));
        Assert.False(AutomationLaunch.Resolve(false, [], env, Folder, path => path != Marker));
        Assert.True(AutomationLaunch.Resolve(false, [], env, Folder, path => path == Marker));
        // A marker alone never turns automation on.
        Assert.False(AutomationLaunch.Resolve(false, [], _ => null, Folder, _ => true));
    }

    [Fact]
    public void LaunchOptions_AcceptsAutomationFlagWithoutConsumingNextArgument()
    {
        var options = LaunchOptions.Parse(["--automation", "--tab", "settings"], _ => null);
        Assert.Equal(AppSection.Settings, options.Tab);
        Assert.Empty(options.Warnings);
    }

    [Fact]
    public void FirstRun_DefaultsOffForHookedLaunchesButExplicitFlagWins()
    {
        Assert.Equal(FirstRunMode.Off, FirstRunModeParser.Parse(["--automation"], _ => null, debugBuild: true));
        Assert.Equal(FirstRunMode.Force, FirstRunModeParser.Parse(["--automation", "--first-run=force"], _ => null, debugBuild: true));
        Assert.Equal(FirstRunMode.Normal, FirstRunModeParser.Parse([], _ => null, debugBuild: false));
    }
}
