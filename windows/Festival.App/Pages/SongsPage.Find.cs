namespace Festival.App.Pages;

#region Page find
/// <summary>Ctrl+F on Songs focuses the page's own filter box (global search stays on Ctrl+E).</summary>
public sealed partial class SongsPage : IPageFind
{
    /// <inheritdoc />
    public bool FocusFind() => MainWindow.FocusAndSelect(SearchBox);
}
#endregion
