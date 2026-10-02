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
        body.Children.Add(new TextBlock { Text = $"{row.Subtitle} · {row.License}", Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"] });
        if (row.Url is { } url)
        {
            var link = new HyperlinkButton { Content = url.Host + url.AbsolutePath.TrimEnd('/'), NavigateUri = url, Padding = new Thickness(0) };
            AutomationProperties.SetName(link, $"Project page for {row.Name}");
            body.Children.Add(link);
        }
        body.Children.Add(new ScrollViewer
        {
            MaxHeight = 420,
            Content = new TextBlock { Text = row.Text, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono, Consolas"), FontSize = 12 },
        });
        // The standard Close button spans the command row, centred under the text (operator batch 6.17; issue #23
        // replaced the in-content Close button with the dialog's own).
        var dialog = Controls.FestivalDialog.Create(XamlRoot, $"{row.Name} · {row.License}", body, "fst.licenses.detail", closeAutomationId: "fst.licenses.detail.close");
        await Controls.FestivalDialog.ShowAsync(dialog);
        if (sender is Control origin) origin.Focus(FocusState.Programmatic);
    }
}
#endregion
