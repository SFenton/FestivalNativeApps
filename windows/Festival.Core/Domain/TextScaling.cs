namespace Festival.Core.Domain;

#region Text scaling
/// <summary>Sizes that follow the Windows text size (Settings › Accessibility › Text size, 100–225%).</summary>
public static class TextScaling
{
    /// <summary>
    /// A width chosen for 100% text scaled by the text size factor, so a column sized for its longest label still fits it
    /// at larger text. Factors below 1 or not finite leave the width unchanged; negative or non-finite widths become 0.
    /// </summary>
    /// <param name="width">Width at 100% text (epx).</param>
    /// <param name="factor">Text size factor (1–2.25).</param>
    /// <returns>Scaled width (epx), rounded up.</returns>
    public static double ScaledWidth(double width, double factor)
    {
        if (!double.IsFinite(width) || width <= 0) return 0;
        return !double.IsFinite(factor) || factor <= 1 ? width : Math.Ceiling(width * factor);
    }
}
#endregion
