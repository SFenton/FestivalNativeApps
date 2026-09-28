using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Band card
/// <summary>Renders a <see cref="PlayerBandCardViewModel"/>; invoking it opens Band Detail.</summary>
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

    /// <summary>Opens Band Detail with the safe type/team-key lookup.</summary>
    /// <param name="sender">Card button.</param>
    /// <param name="e">Unused.</param>
    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (Card is { } card) MainWindow.Instance?.Navigate(card.Route);
    }
}
#endregion
