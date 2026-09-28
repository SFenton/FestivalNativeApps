using Festival.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App;

#region Songs screen
/// <summary>Read-only Songs list with native virtualized ListView.</summary>
public sealed partial class SongsPage : Page
{
    /// <summary>Creates a Songs page bound to injectable state.</summary>
    /// <param name="state">Screen state.</param>
    public SongsPage(SongsState state)
    {
        InitializeComponent();
        DataContext = state;
    }

    /// <summary>Fetches the currently published songs on explicit user action.</summary>
    /// <param name="sender">Refresh button.</param>
    /// <param name="args">Click details.</param>
    private async void OnRefresh(object sender, RoutedEventArgs args) =>
        await ((SongsState)DataContext).RefreshAsync();
#endregion
}
