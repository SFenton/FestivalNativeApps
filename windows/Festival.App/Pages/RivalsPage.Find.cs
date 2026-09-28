using Microsoft.UI.Xaml;

namespace Festival.App.Pages;

#region Page find
/// <summary>Ctrl+F on Rivals focuses Find Rival (global search stays on Ctrl+E).</summary>
public sealed partial class RivalsPage : IPageFind
{
    /// <inheritdoc />
    public bool FocusFind()
    {
        if (FindRivalBox.Visibility != Visibility.Visible) return false;
        return MainWindow.FocusAndSelect(FindRivalBox);
    }
}
#endregion
