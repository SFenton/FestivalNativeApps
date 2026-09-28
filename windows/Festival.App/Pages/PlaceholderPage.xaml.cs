using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Placeholder page
/// <summary>Stand-in for sections and routes that are typed but not yet ported.</summary>
public sealed partial class PlaceholderPage : Page
{
    /// <summary>Creates the page.</summary>
    public PlaceholderPage() => InitializeComponent();

    /// <inheritdoc />
    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        switch (e.Parameter)
        {
            case AppSection section:
                TitleText.Text = section.Label();
                PathText.Text = "/" + section.ToString().ToLowerInvariant();
                break;
            case AppRoute route:
                TitleText.Text = Title(route);
                PathText.Text = route.ToPath();
                break;
        }
    }

    /// <summary>Title Case heading for a route.</summary>
    /// <param name="route">Route.</param>
    /// <returns>Heading.</returns>
    private static string Title(AppRoute route) => route switch
    {
        AppRoute.SongLeaderboard board => $"{board.Instrument.Label()} Leaderboard",
        AppRoute.PlayerHistory => "Score History",
        AppRoute.SongBandLeaderboard => "Band Leaderboard",
        AppRoute.Player or AppRoute.RivalDetail => "Player",
        AppRoute.PlayerBands or AppRoute.Bands or AppRoute.Band => "Bands",
        AppRoute.FullRankings or AppRoute.BandRankings or AppRoute.Leaderboards => "Leaderboards",
        AppRoute.Rivalry or AppRoute.AllRivals or AppRoute.Rivals or AppRoute.Compete => "Rivals",
        AppRoute.Shop => "Item Shop",
        AppRoute.Licenses => "Licenses",
        _ => route.Section.Label(),
    };
}
#endregion
