using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Pages;

#region Licenses page
/// <summary>
/// <c>/settings/licenses</c>: this app's own third-party NuGet packages (generated <c>Assets/licenses.json</c>) in one card.
/// A row opens the full text in a ContentDialog, which returns focus to the row when closed. No network.
/// </summary>
public sealed partial class LicensesPage : Page
{
    /// <summary>Creates the page.</summary>
    public LicensesPage()
    {
        ViewModel = new LicensesViewModel(LicenseManifest.Parse(ReadManifest()));
        InitializeComponent();
    }

    /// <summary>Page model.</summary>
    public LicensesViewModel ViewModel { get; }

    /// <summary>Windows text size (read on each row resize, so a text-size change re-lays rows as they re-measure).</summary>
    private readonly Windows.UI.ViewManagement.UISettings uiSettings = new();

    /// <summary>Reads the bundled manifest.</summary>
    /// <returns>Bytes or <see langword="null"/>.</returns>
    private static byte[]? ReadManifest()
    {
        try
        {
            return File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Assets", "licenses.json"));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>Shows a license's full text.</summary>
    /// <param name="sender">Row button.</param>
    /// <param name="e">Unused.</param>
    private async void OnRowClick(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: LicenseRowViewModel row }) return;
        var body = new StackPanel { Spacing = 12, MaxWidth = 560 };
        body.Children.Add(new TextBlock { Text = row.DetailCaption, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"] });
        if (row.Url is { } url)
        {
            // After the text in Tab order (the text opens focused), though shown above it like Android and iOS.
            var link = new HyperlinkButton { Content = row.LinkText, NavigateUri = url, Padding = new Thickness(0), TabIndex = 2 };
            AutomationProperties.SetName(link, row.LinkAccessibleName);
            AutomationProperties.SetAutomationId(link, "fst.licenses.detail.link");
            body.Children.Add(link);
        }
        // A named tab stop that opens focused, so arrow and Page keys scroll long terms (issue #215: the text was
        // unreachable from the keyboard); capped to the window so a short window keeps the Close row on screen.
        var text = new ScrollViewer
        {
            MaxHeight = Festival.Core.Domain.LicenseRowLayout.DetailTextHeight(XamlRoot.Size.Height),
            IsTabStop = true,
            TabIndex = 1,
            // Inset so the focus rectangle and the scrollbar don't cover the first and last glyphs.
            Content = new TextBlock { Text = row.Text, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, Margin = new Thickness(8, 4, 16, 4), FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono, Consolas"), FontSize = 12 },
        };
        AutomationProperties.SetAutomationId(text, "fst.licenses.detail.text");
        AutomationProperties.SetName(text, row.TextAccessibleName);
        body.Children.Add(text);
        // The standard Close button spans the command row, centred under the text (operator batch 6.17; issue #23
        // replaced the in-content Close button with the dialog's own).
        var dialog = Controls.FestivalDialog.Create(XamlRoot, row.DetailTitle, body, "fst.licenses.detail", closeAutomationId: "fst.licenses.detail.close");
        dialog.Opened += (_, _) => text.Focus(FocusState.Programmatic);
        await Controls.FestivalDialog.ShowAsync(dialog);
        if (sender is Control origin) origin.Focus(FocusState.Programmatic);
    }

    /// <summary>Moves a row's license badge under the name when the row is narrow for the text size, and back.</summary>
    /// <param name="sender">Row content grid (name panel, badge, chevron).</param>
    /// <param name="e">New size.</param>
    private void OnRowContentSizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (sender is not Grid grid || grid.Children.Count < 2 || grid.Children[1] is not Border badge) return;
        var stacked = Festival.Core.Domain.LicenseRowLayout.StacksBadge(e.NewSize.Width, uiSettings.TextScaleFactor);
        if (Grid.GetRow(badge) == (stacked ? 1 : 0)) return;
        Grid.SetRow(badge, stacked ? 1 : 0);
        Grid.SetColumn(badge, stacked ? 0 : 1);
        Grid.SetRowSpan(badge, stacked ? 1 : 2);
        badge.HorizontalAlignment = stacked ? HorizontalAlignment.Left : HorizontalAlignment.Stretch;
        badge.MaxWidth = stacked ? double.PositiveInfinity : 220;
        badge.Margin = stacked ? new Thickness(0, 4, 0, 0) : new Thickness(0);
    }
}
#endregion
