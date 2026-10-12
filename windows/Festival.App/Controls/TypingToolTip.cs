using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

/// <summary>
/// Suspends a search box's hint tooltip (e.g. "Search songs, players and bands (Ctrl+E)") while the user types in it,
/// so the hint never covers the suggestion list or results (issue #571).
/// </summary>
/// <remarks>
/// Keyboard focus opens the hint after WinUI's show delay, and typing that starts before the delay ends does not cancel
/// it: the hint then opened over the open suggestion list and its windowed <c>PopupHost</c> stayed in the UI Automation
/// tree. From the first typed character (or the suggestion list opening) until focus leaves the box, the hint is closed
/// and removed, so neither the pending keyboard open nor a pointer hover can show it; it returns for the next focus.
/// </remarks>
public static class TypingToolTip
{
    /// <summary>Suspends <paramref name="box"/>'s tooltip from user input until focus leaves it.</summary>
    /// <param name="box">A search box whose tooltip is a hint (set in XAML or code before this call).</param>
    public static void SuspendWhileTyping(AutoSuggestBox box)
    {
        object? hint = null;
        // Own the hint so an open one can be closed (ToolTipService keeps the ToolTip it builds for plain content).
        if (ToolTipService.GetToolTip(box) is { } initial and not ToolTip) CollapsedToolTip.Set(box, initial);
        void Suspend()
        {
            if (ToolTipService.GetToolTip(box) is not { } tip) return;
            hint = tip;
            CollapsedToolTip.Set(box, null);
        }
        box.TextChanged += (_, args) =>
        {
            if (args.Reason == AutoSuggestionBoxTextChangeReason.UserInput) Suspend();
        };
        box.RegisterPropertyChangedCallback(AutoSuggestBox.IsSuggestionListOpenProperty, (_, _) =>
        {
            if (box.IsSuggestionListOpen) Suspend();
        });
        box.LostFocus += (_, _) =>
        {
            // LostFocus bubbles from the inner TextBox; restore only once focus has left the box entirely.
            if (hint is null || CollapsedToolTip.HasFocusWithin(box)) return;
            CollapsedToolTip.Set(box, hint);
            hint = null;
        };
    }
}
