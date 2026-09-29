using Festival.App.Pages;

namespace Festival.App;

#region Player stat links
/// <summary>Entry point for player-page stat links that open Songs with a saved filter preset (web <c>navigateToSongs</c>).</summary>
public sealed partial class MainWindow
{
    /// <summary>
    /// Shows the Songs root after a player-page preset was written to the saved Songs sort/filter, clearing the Songs
    /// search like the web's <c>setQuery('')</c> so the preset is not narrowed by an old query.
    /// </summary>
    public void ShowFilteredSongs()
    {
        ShowSongsRoot();
        if (frames.TryGetValue(AppSection.Songs, out var frame) && frame.Content is SongsPage songs)
            songs.ViewModel.SearchText = "";
    }
}
#endregion
