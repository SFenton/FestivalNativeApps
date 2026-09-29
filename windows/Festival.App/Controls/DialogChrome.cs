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
    public static void LightDismiss(ContentDialog dialog) => dialog.Opened += (_, _) =>
    {
        if (Find(dialog, "SmokeLayerBackground") is not UIElement smoke) return;
        smoke.PointerPressed += (_, e) =>
        {
            e.Handled = true;
            dialog.Hide();
        };
    };

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
