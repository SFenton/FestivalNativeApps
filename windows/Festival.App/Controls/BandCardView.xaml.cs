using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Band card
/// <summary>
/// Renders a <see cref="PlayerBandCardViewModel"/>; invoking it opens Band Detail, or raises
/// <see cref="RouteRequested"/> when a host (global search) owns the navigation. Standalone on Player Bands and Search;
/// a separated row of its group card on the profile (<see cref="PlayerBandCardViewModel.IsGroupedRow"/>).
/// </summary>
public sealed partial class BandCardView : UserControl, ISeparatedRow
{
    /// <summary>Bound card.</summary>
    public static readonly DependencyProperty CardProperty = DependencyProperty.Register(
        nameof(Card), typeof(PlayerBandCardViewModel), typeof(BandCardView), new PropertyMetadata(null, (d, _) => ((BandCardView)d).OnCardChanged()));

    /// <summary>Creates the card.</summary>
    public BandCardView() => InitializeComponent();

    /// <summary>Card to render.</summary>
    public PlayerBandCardViewModel? Card
    {
        get => (PlayerBandCardViewModel?)GetValue(CardProperty);
        set => SetValue(CardProperty, value);
    }

    /// <inheritdoc />
    public bool ShowSeparator { set => RowSeparator.Visibility = value ? Visibility.Visible : Visibility.Collapsed; }

    /// <summary>
    /// Re-binds and switches between the standalone card (own surface, 8 epx corners) and a row of a group card: no
    /// surface, the control corner radius (4 epx, concentric inside the card's 8 epx corner and 4 epx padding) and
    /// 12 epx side padding so the content keeps the standalone 16 epx inset from the card edge (issue #596).
    /// </summary>
    private void OnCardChanged()
    {
        var grouped = Card?.IsGroupedRow == true;
        Surface.Visibility = grouped ? Visibility.Collapsed : Visibility.Visible;
        CardButton.CornerRadius = grouped ? (CornerRadius)Application.Current.Resources["ControlCornerRadius"] : new CornerRadius(8);
        CardButton.Padding = grouped ? new Thickness(12) : new Thickness(16, 12, 16, 12);
        Bindings.Update();
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
