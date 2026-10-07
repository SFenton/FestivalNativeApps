using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Band card
/// <summary>
/// Renders a <see cref="PlayerBandCardViewModel"/>; invoking it opens Band Detail, or raises
/// <see cref="RouteRequested"/> when a host (global search) owns the navigation.
/// </summary>
public sealed partial class BandCardView : UserControl
{
    /// <summary>Bound card.</summary>
    public static readonly DependencyProperty CardProperty = DependencyProperty.Register(
        nameof(Card), typeof(PlayerBandCardViewModel), typeof(BandCardView), new PropertyMetadata(null, (d, _) => ((BandCardView)d).Bindings.Update()));

    /// <summary>Creates the card.</summary>
    public BandCardView() => InitializeComponent();

    /// <summary>Card to render.</summary>
    public PlayerBandCardViewModel? Card
    {
        get => (PlayerBandCardViewModel?)GetValue(CardProperty);
        set => SetValue(CardProperty, value);
    }

    /// <summary>
    /// Raised instead of the default push when handled by a host: global search closes itself before opening the band
    /// (<c>MainWindow.OpenSearchRoute</c>). Player Bands consumers leave it unset and keep the plain push.
    /// </summary>
    public event EventHandler<AppRoute>? RouteRequested;

    /// <summary>Opens Band Detail with the safe type/team-key lookup (through the host when it handles the request).</summary>
    /// <param name="sender">Card button.</param>
    /// <param name="e">Unused.</param>
    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (Card is not { } card) return;
        if (RouteRequested is { } host) host(this, card.Route);
        else MainWindow.Instance?.Navigate(card.Route);
    }
}
#endregion
