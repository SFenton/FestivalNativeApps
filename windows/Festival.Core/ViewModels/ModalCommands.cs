namespace Festival.Core.ViewModels;

#region Modal commands
/// <summary>
/// Command-row rules every Festival modal dialog shares (issue #23). Windows modals close through ContentDialog's own
/// Close button (its <c>CloseButtonText</c>, which Esc and a click outside also trigger), never a custom glyph or an
/// in-content button; a dialog whose command row holds one button shows it full width, centred.
/// </summary>
public static class ModalCommands
{
    /// <summary>Text of the standard Close command.</summary>
    public const string Close = "Close";

    /// <summary>Number of visible command buttons (empty text hides a ContentDialog button).</summary>
    /// <param name="primary">Primary button text.</param>
    /// <param name="secondary">Secondary button text.</param>
    /// <param name="close">Close button text.</param>
    /// <returns>Visible button count, 0-3.</returns>
    public static int Count(string? primary, string? secondary, string? close) =>
        new[] { primary, secondary, close }.Count(text => !string.IsNullOrWhiteSpace(text));

    /// <summary>Whether the command row spans its single button across the whole width.</summary>
    /// <param name="primary">Primary button text.</param>
    /// <param name="secondary">Secondary button text.</param>
    /// <param name="close">Close button text.</param>
    /// <returns><see langword="true"/> when exactly one button is visible.</returns>
    public static bool SpansFullWidth(string? primary, string? secondary, string? close) => Count(primary, secondary, close) == 1;
}
#endregion
