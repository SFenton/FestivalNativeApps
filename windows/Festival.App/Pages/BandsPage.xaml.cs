using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Pages;

#region Bands without an ID
/// <summary>
/// <c>/bands</c> with no band ID: the web's "Band not found" state. Bands are reached from a player's Bands list or Band
/// Rankings (band search is blocked: its GET can write server state).
/// </summary>
public sealed partial class BandsPage : Page
{
    /// <summary>Creates the page.</summary>
    public BandsPage() => InitializeComponent();
}
#endregion
