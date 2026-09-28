using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Festival.App.Services;

namespace Festival.App.Pages;

#region Player profile page
/// <summary>Player page for <see cref="AppRoute.Player"/>; viewing never selects.</summary>
public sealed partial class PlayerProfilePage : Page
{
    private PlayerProfileViewModel? model;

    /// <summary>Creates the page.</summary>
    public PlayerProfilePage() => InitializeComponent();

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        model?.Dispose();
        var route = (AppRoute.Player)e.Parameter;
        model = new PlayerProfileViewModel(App.Session, route.AccountId, route.DisplayName);
        Profile.Bind(model);
        var profile = model;
        ScreenReader.Attach(this, [profile], () => profile.IsLoading,
            () => profile.ShowContent ? $"{profile.DisplayName}, {profile.Subtitle}" : null, "Loading profile");
        await model.LoadCommand.ExecuteAsync(null);
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        model?.Dispose();
        model = null;
    }
}
#endregion
