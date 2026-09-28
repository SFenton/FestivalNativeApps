using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Rival page states
/// <summary>Loading, failure (shared <see cref="ServiceStatusView"/>), empty and no-player states for a rival page.</summary>
public sealed partial class RivalPageStates : UserControl
{
    /// <summary>Page model.</summary>
    public static readonly DependencyProperty PageProperty = DependencyProperty.Register(
        nameof(Page), typeof(RivalPageViewModel), typeof(RivalPageStates), new PropertyMetadata(null));

    /// <summary>Creates the view.</summary>
    public RivalPageStates() => InitializeComponent();

    /// <summary>Page model.</summary>
    public RivalPageViewModel? Page
    {
        get => (RivalPageViewModel?)GetValue(PageProperty);
        set => SetValue(PageProperty, value);
    }

    /// <summary>Opens the title-bar profile picker.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnSelectPlayer(object sender, RoutedEventArgs e) => MainWindow.Instance?.OpenProfilePicker();
}
#endregion
