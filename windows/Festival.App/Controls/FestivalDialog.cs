using Festival.Core.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Festival dialog
/// <summary>
/// The one modal component every Festival dialog is built with (issue #23; Apple <c>FestivalSheetCloseItem</c>, Android
/// <c>FestivalModal</c>): a Fluent <see cref="ContentDialog"/> in the dark theme whose standard Close command
/// (<see cref="ContentDialog.CloseButtonText"/>, also Esc) dismisses it, with no custom close glyph or in-content button.
/// A lone command button spans the row (<see cref="DialogChrome.FullWidthSingleButton"/>), and
/// <see cref="ShowAsync"/> adds outside-click dismissal and shows one dialog at a time.
/// </summary>
public static class FestivalDialog
{
    /// <summary>Builds a dialog.</summary>
    /// <param name="root">Window XAML root.</param>
    /// <param name="title">Title.</param>
    /// <param name="content">Body (text or a control).</param>
    /// <param name="automationId">UI Automation ID of the dialog.</param>
    /// <param name="closeText">Close button text (Close, Cancel, Dismiss…); empty hides it (alerts with their own choices).</param>
    /// <param name="primaryText">Primary button text, or empty.</param>
    /// <param name="secondaryText">Secondary button text, or empty.</param>
    /// <param name="defaultButton">Button Enter activates.</param>
    /// <param name="closeAutomationId">Optional UI Automation ID for the Close button.</param>
    /// <returns>Dialog to pass to <see cref="ShowAsync"/>.</returns>
    public static ContentDialog Create(
        XamlRoot root,
        string title,
        object content,
        string automationId,
        string closeText = ModalCommands.Close,
        string primaryText = "",
        string secondaryText = "",
        ContentDialogButton defaultButton = ContentDialogButton.Close,
        string? closeAutomationId = null)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = title,
            Content = content,
            PrimaryButtonText = primaryText,
            SecondaryButtonText = secondaryText,
            CloseButtonText = closeText,
            DefaultButton = defaultButton,
            RequestedTheme = ElementTheme.Dark,
        };
        AutomationProperties.SetAutomationId(dialog, automationId);
        if (ModalCommands.SpansFullWidth(primaryText, secondaryText, closeText)) DialogChrome.FullWidthSingleButton(dialog);
        if (closeAutomationId is not null) DialogChrome.CloseButtonAutomationId(dialog, closeAutomationId);
        DialogChrome.CommandLabelsWithoutBackplate(dialog);
        return dialog;
    }

    /// <summary>Shows a dialog through the window's one-at-a-time gate, closing on a click outside it.</summary>
    /// <param name="dialog">Dialog from <see cref="Create"/>.</param>
    /// <returns>Result (<see cref="ContentDialogResult.None"/> for Close, Esc or an outside click).</returns>
    public static Task<ContentDialogResult> ShowAsync(ContentDialog dialog) => MainWindow.ShowDialogAsync(dialog);
}
#endregion
