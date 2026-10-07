namespace Festival.Core.Domain;

#region Large text
/// <summary>
/// The one Windows "large text" threshold (Apple's accessibility text sizes): at 150% Windows text size and above,
/// layouts that squeeze or truncate text at standard sizes give it more lines instead. Used by the shell title bar,
/// the Settings service-state row (<see cref="ServiceInfoText.StacksStateRow"/>) and in-page song header lines
/// (pattern <c>song-header</c> R3, issue #315).
/// </summary>
public static class LargeText
{
    /// <summary>Windows text size factor at and above which text counts as large (150%).</summary>
    public const double Scale = 1.5;

    /// <summary>Whether a Windows text size factor is large text.</summary>
    /// <param name="textScale">Windows text size factor (1–2.25).</param>
    /// <returns><see langword="true"/> at 150% text and above.</returns>
    public static bool Applies(double textScale) => textScale >= Scale;
}
#endregion
