using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Festival.App.Services;

namespace Festival.App.Pages;

#region Statistics page
/// <summary>Statistics section root: follows the selected player and resets when it changes.</summary>
public sealed partial class StatisticsPage : Page
{
    private PlayerProfileViewModel? model;

    /// <summary>Creates the page.</summary>
    public StatisticsPage() => InitializeComponent();

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        model?.Dispose();
        model = new PlayerProfileViewModel(App.Session, accountId: null);
        Profile.Bind(model);
        var profile = model;
        ScreenReader.Attach(this, [profile], () => profile.IsLoading,
            () => profile.ShowContent ? $"{profile.DisplayName}, statistics" : null, "Loading statistics");
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
