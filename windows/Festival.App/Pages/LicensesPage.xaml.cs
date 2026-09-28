using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Pages;

#region Licenses page
/// <summary>
/// <c>/settings/licenses</c>: this app's own NuGet packages (generated <c>Assets/licenses.json</c>) and bundled assets.
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
            Content = new TextBlock { Text = row.Text, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono, Consolas") },
        });
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = row.Name,
            Content = body,
            CloseButtonText = "Close",
            DefaultButton = ContentDialogButton.Close,
            RequestedTheme = ElementTheme.Dark,
        };
        AutomationProperties.SetAutomationId(dialog, "fst.licenses.detail");
        await MainWindow.ShowDialogAsync(dialog);
    }
}
#endregion
