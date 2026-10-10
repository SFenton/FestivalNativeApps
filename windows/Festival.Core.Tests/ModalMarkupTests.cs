using System.Text.RegularExpressions;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issues #23/#239: every Windows modal is built by the one shared <c>FestivalDialog</c> factory (a Fluent
/// ContentDialog whose standard Close command dismisses it) and shown through the window's one-at-a-time gate, so no
/// page can bring back a hand-made dialog or a custom close glyph. The live check is <c>tools/windows/journeys/a11y-modals.json</c>.
/// </summary>
public class ModalMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    #region Helpers

    /// <summary>App sources with the given extension, excluding build output.</summary>
    /// <param name="extension">File extension such as <c>.cs</c>.</param>
    /// <returns>Path relative to Festival.App (forward slashes) and text, per file.</returns>
    private static List<(string Path, string Text)> Sources(string extension) =>
        Directory.EnumerateFiles(AppRoot, "*" + extension, SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(AppRoot, path).Replace('\\', '/'))
            .Where(path => !path.StartsWith("bin/", StringComparison.Ordinal) && !path.StartsWith("obj/", StringComparison.Ordinal))
            .Select(path => (path, File.ReadAllText(Path.Combine(AppRoot, path))))
            .ToList();

    /// <summary>Files whose text matches a pattern.</summary>
    /// <param name="extension">File extension.</param>
    /// <param name="pattern">Regular expression.</param>
    /// <returns>Sorted relative paths.</returns>
    private static List<string> Matching(string extension, string pattern) =>
        Sources(extension).Where(file => Regex.IsMatch(file.Text, pattern)).Select(file => file.Path).Order().ToList();

    #endregion

    [Fact]
    public void Sources_AreFound() => Assert.Contains(Sources(".cs"), file => file.Path == "Controls/FestivalDialog.cs");

    [Fact]
    public void ContentDialogs_AreOnlyCreatedByFestivalDialog() =>
        Assert.Equal(["Controls/FestivalDialog.cs"], Matching(".cs", @"new\s+ContentDialog\b"));

    [Fact]
    public void Xaml_DeclaresNoContentDialog() => Assert.Empty(Matching(".xaml", @"<ContentDialog\b"));

    [Fact]
    public void Dialogs_AreOnlyShownThroughTheWindowGate() =>
        Assert.Equal(["MainWindow.Settings.cs"], Matching(".cs", @"\.ShowAsync\(\s*\)"));

    [Theory]
    [InlineData("Controls/FeedbackDialog.cs")]
    [InlineData("Controls/FirstRunCarousel.xaml.cs")]
    [InlineData("Controls/PlayerProfileView.xaml.cs")]
    [InlineData("Controls/PrivacyPolicyDialog.cs")]
    [InlineData("Controls/SongPathsView.xaml.cs")]
    [InlineData("MainWindow.WhatsNew.cs")]
    [InlineData("Pages/LicensesPage.xaml.cs")]
    [InlineData("Pages/SettingsPage.xaml.cs")]
    public void EveryModal_UsesTheSharedFactory(string file)
    {
        var text = Sources(".cs").Single(source => source.Path == file).Text;
        Assert.Contains("FestivalDialog.Create(", text, StringComparison.Ordinal);
        Assert.DoesNotContain("new ContentDialog", text, StringComparison.Ordinal);
    }

    [Fact]
    public void ModalCallers_AreAllListed()
    {
        // A new modal must be added to EveryModal_UsesTheSharedFactory (and tools/windows/journeys/a11y-modals.json).
        var callers = Matching(".cs", @"FestivalDialog\.Create\(").Where(path => path != "Controls/FestivalDialog.cs");
        Assert.Equal(
            ["Controls/FeedbackDialog.cs", "Controls/FirstRunCarousel.xaml.cs", "Controls/PlayerProfileView.xaml.cs",
             "Controls/PrivacyPolicyDialog.cs", "Controls/SongPathsView.xaml.cs", "MainWindow.WhatsNew.cs",
             "Pages/LicensesPage.xaml.cs", "Pages/SettingsPage.xaml.cs"],
            callers);
    }

    /// <summary>
    /// Modal-shell R5 (#420): ContentDialog's template ContentScrollViewer never scrolls vertically, so each body that
    /// can outgrow the window at large text or in a short window owns its ScrollViewer under the fixed title and commands.
    /// </summary>
    /// <param name="file">Source that builds the dialog body.</param>
    [Theory]
    [InlineData("Controls/FeedbackDialog.cs")]
    [InlineData("Controls/FirstRunCarousel.xaml")]
    [InlineData("Controls/PrivacyPolicyDialog.cs")]
    [InlineData("Controls/SongPathsView.xaml")]
    [InlineData("MainWindow.WhatsNew.cs")]
    public void TallModalBodies_OwnTheirScroller(string file)
    {
        var text = Sources(Path.GetExtension(file)).Single(source => source.Path == file).Text;
        Assert.Matches(@"<ScrollViewer\b|new\s+ScrollViewer\b", text);
    }

    [Fact]
    public void FirstRunBody_ScrollsVerticallyOnly()
    {
        var text = Sources(".xaml").Single(source => source.Path == "Controls/FirstRunCarousel.xaml").Text;
        Assert.Matches(@"<ScrollViewer\s+x:Name=""Body""[^>]*VerticalScrollBarVisibility=""Auto""", text);
        Assert.Matches(@"<ScrollViewer\s+x:Name=""Body""[^>]*HorizontalScrollBarVisibility=""Disabled""", text);
        Assert.Contains(@"AutomationProperties.AutomationId=""fst.first-run.body""", text, StringComparison.Ordinal);
    }

    [Fact]
    public void TemplateContentScroller_IsNeverReachedInto() =>
        Assert.Empty(Sources(".cs").Concat(Sources(".xaml"))
            .Where(file => file.Text.Contains("\"ContentScrollViewer\"", StringComparison.Ordinal))
            .Select(file => file.Path));

    [Fact]
    public void FestivalDialog_ClosesWithTheStandardCommand()
    {
        var text = Sources(".cs").Single(source => source.Path == "Controls/FestivalDialog.cs").Text;
        Assert.Contains("CloseButtonText = closeText", text, StringComparison.Ordinal);
        Assert.Contains("string closeText = ModalCommands.Close", text, StringComparison.Ordinal);
    }

    [Fact]
    public void TextBoxGuidance_Wraps()
    {
        // Issue #239: a string Description is one unwrapped line that clipped the Feedback guidance at compact and 200% text.
        Assert.Empty(Matching(".cs", @"\bDescription\s*=\s*(help|""|\$"")"));
        Assert.Empty(Matching(".xaml", @"<TextBox\b[^>]*\bDescription="""));
        var feedback = Sources(".cs").Single(source => source.Path == "Controls/FeedbackDialog.cs").Text;
        Assert.Matches(@"Description\s*=\s*new TextBlock \{[^}]*TextWrapping\.WrapWholeWords", feedback);
        // Issue #236: the field labels clipped the same way.
        Assert.Matches(@"Header\s*=\s*new TextBlock \{[^}]*TextWrapping\.WrapWholeWords", feedback);
    }

    [Fact]
    public void Commands_KeepTheMinimumTouchTarget()
    {
        // Issue #400: the template's 32 epx command buttons missed taps just above or below the label.
        var factory = Sources(".cs").Single(source => source.Path == "Controls/FestivalDialog.cs").Text;
        Assert.Contains("DialogChrome.CommandTargets(dialog);", factory, StringComparison.Ordinal);
        var chrome = Sources(".cs").Single(source => source.Path == "Controls/DialogChrome.cs").Text;
        Assert.Contains(@"TryGetValue(""FSTMinTargetSize""", chrome, StringComparison.Ordinal);
        Assert.Contains("button.MinHeight = size;", chrome, StringComparison.Ordinal);
        Assert.Contains("internal const double MinTargetSize = 40;", chrome, StringComparison.Ordinal);
    }

    [Fact]
    public void CommandLabels_DropTheContrastBackplate()
    {
        // Issue #239: under Desert/Night sky the default button's label sat on a Window-coloured box inside its Highlight fill.
        var factory = Sources(".cs").Single(source => source.Path == "Controls/FestivalDialog.cs").Text;
        Assert.Contains("DialogChrome.CommandLabelsWithoutBackplate(dialog);", factory, StringComparison.Ordinal);
        var chrome = Sources(".cs").Single(source => source.Path == "Controls/DialogChrome.cs").Text;
        Assert.Contains(@"[""PrimaryButton"", ""SecondaryButton"", ""CloseButton""]", chrome, StringComparison.Ordinal);
        Assert.Contains("HighContrastAdjustment = ElementHighContrastAdjustment.None", chrome, StringComparison.Ordinal);
        var carousel = Sources(".cs").Single(source => source.Path == "Controls/FirstRunCarousel.xaml.cs").Text;
        Assert.Contains("DialogChrome.WithoutBackplate(Pips);", carousel, StringComparison.Ordinal);
    }
}
