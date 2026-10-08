using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Dialog chrome
/// <summary>
/// Adjustments to Fluent <see cref="ContentDialog"/> chrome shared by the app's modals (operator batch 6.7 / 6.14):
/// a click or tap on the dimmed backdrop dismisses the dialog like Esc (the web's modals close on an outside click), and
/// a dialog with one button shows it full width, centred, instead of in the template's right-hand half.
/// </summary>
public static class DialogChrome
{
    /// <summary>Closes the dialog when the smoke layer outside it is pressed (result <see cref="ContentDialogResult.None"/>).</summary>
    /// <param name="dialog">Dialog, before it is shown.</param>
    public static void LightDismiss(ContentDialog dialog)
    {
        // Hooked as soon as the template exists (Loaded), not on Opened: on a slow cold start a click could land during
        // the opening transition and find no handler yet.
        var hooked = false;
        void Hook()
        {
            if (hooked || Find(dialog, "SmokeLayerBackground") is not UIElement smoke) return;
            hooked = true;
            smoke.PointerPressed += (_, e) =>
            {
                e.Handled = true;
                dialog.Hide();
            };
        }
        dialog.Loaded += (_, _) => Hook();
        dialog.Opened += (_, _) => Hook();
    }

    /// <summary>
    /// Lets the one visible command button span the whole command row: the template's two-column row otherwise leaves a
    /// lone button in the right half. Only column widths change (the template's visual states set placement, not widths).
    /// </summary>
    /// <param name="dialog">Dialog with a single command button, before it is shown.</param>
    public static void FullWidthSingleButton(ContentDialog dialog) => dialog.Loaded += (_, _) =>
    {
        foreach (var name in new[] { "PrimaryColumn", "FirstSpacer", "SecondaryColumn", "SecondSpacer" })
            if (Find(dialog, name) is ColumnDefinition column) column.Width = new GridLength(0);
    };

    /// <summary>Gives the template's Close button a stable UI Automation ID once the template exists.</summary>
    /// <param name="dialog">Dialog, before it is shown.</param>
    /// <param name="automationId">Automation ID.</param>
    public static void CloseButtonAutomationId(ContentDialog dialog, string automationId) => dialog.Loaded += (_, _) =>
    {
        if (Find(dialog, "CloseButton") is Button close) Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(close, automationId);
    };

    /// <summary>
    /// Keeps the dialog surface out of the window's caption band (issue #244). The window extends its content into the
    /// title bar, so a tall dialog (large text, short window) otherwise grows to the full window height. Its top edge then
    /// sits in the title bar's drag region under the window's own minimize/maximize/close buttons, whose small "×" reads as
    /// the dialog's close but quits the app. Equal top and bottom margins keep short dialogs centred, and a taller body
    /// scrolls in the template's own content scroller.
    /// </summary>
    /// <param name="dialog">Dialog, before it is shown.</param>
    /// <param name="captionHeight">Title bar height in effective pixels.</param>
    public static void ClearOfTitleBar(ContentDialog dialog, double captionHeight) => dialog.Loaded += (_, _) =>
    {
        if (captionHeight > 0 && Find(dialog, "BackgroundElement") is FrameworkElement surface)
            surface.Margin = new Thickness(0, captionHeight, 0, captionHeight);
    };

    /// <summary>
    /// Drops WinUI's automatic high-contrast text backplate from the command buttons' labels. The template already draws
    /// them in system colour pairs (ButtonText on ButtonFace, HighlightText on Highlight for the default button), so the
    /// adjustment only painted a Window-coloured box inside the default button's Highlight fill
    /// (precedent: <c>LeaderboardEntryRow</c>, Shop badges, Songs Filter). Without a contrast theme the setting has no effect.
    /// </summary>
    /// <param name="dialog">Dialog, before it is shown.</param>
    public static void CommandLabelsWithoutBackplate(ContentDialog dialog)
    {
        void Apply()
        {
            foreach (var name in CommandButtons)
                if (Find(dialog, name) is Button button) WithoutBackplate(button);
        }
        dialog.Loaded += (_, _) => Apply();
        dialog.Opened += (_, _) => Apply();
    }

    /// <summary>
    /// Gives every command button Fluent's 40 epx minimum touch target (<c>FSTMinTargetSize</c>, issues #72 and #400), like
    /// the app's other action buttons: the template's buttons are 32 epx tall, so a tap just above or below the label
    /// missed Close. Larger text still grows them.
    /// </summary>
    /// <param name="dialog">Dialog, before it is shown.</param>
    public static void CommandTargets(ContentDialog dialog)
    {
        var size = Application.Current?.Resources.TryGetValue("FSTMinTargetSize", out var value) == true && value is double d
            ? d
            : MinTargetSize;
        void Apply()
        {
            foreach (var name in CommandButtons)
                if (Find(dialog, name) is Button button) button.MinHeight = size;
        }
        dialog.Loaded += (_, _) => Apply();
        dialog.Opened += (_, _) => Apply();
    }

    /// <summary>Fallback for <c>FSTMinTargetSize</c> (Styles.xaml) when the app resources are not loaded.</summary>
    internal const double MinTargetSize = 40;

    /// <summary>Template part names of the dialog's command buttons.</summary>
    internal static readonly string[] CommandButtons = ["PrimaryButton", "SecondaryButton", "CloseButton"];

    /// <summary>Sets <see cref="ElementHighContrastAdjustment.None"/> on an element and every descendant (not inherited).</summary>
    /// <param name="element">Root element.</param>
    internal static void WithoutBackplate(DependencyObject element)
    {
        if (element is UIElement ui) ui.HighContrastAdjustment = ElementHighContrastAdjustment.None;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(element); i++) WithoutBackplate(VisualTreeHelper.GetChild(element, i));
    }

    /// <summary>Finds a named template part below the dialog.</summary>
    /// <param name="dialog">Dialog.</param>
    /// <param name="name">Part name.</param>
    /// <returns>The part, or <see langword="null"/>.</returns>
    private static object? Find(ContentDialog dialog, string name) =>
        VisualTreeHelper.GetChildrenCount(dialog) > 0 && VisualTreeHelper.GetChild(dialog, 0) is FrameworkElement root
            ? root.FindName(name)
            : null;
}
#endregion
