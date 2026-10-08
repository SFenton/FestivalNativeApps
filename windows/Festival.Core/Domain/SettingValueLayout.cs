namespace Festival.Core.Domain;

#region Setting value layout
/// <summary>
/// Placement rule for a Settings label/value row (Version card): the value sits right of the label when both fit
/// at their natural widths, otherwise it stacks under the label so neither is clipped (Android <c>SettingsValueRow</c>;
/// Fluent "reposition side details below main" at narrow widths and large text).
/// </summary>
public static class SettingValueLayout
{
    /// <summary>Horizontal gap between label and value in epx.</summary>
    public const double ColumnSpacing = 12;

    /// <summary>Vertical gap between a label and its stacked value in epx.</summary>
    public const double StackedSpacing = 4;

    /// <summary>
    /// Whether the value moves under its label.
    /// </summary>
    /// <param name="availableWidth">Width the row may use; infinite or NaN never stacks.</param>
    /// <param name="labelWidth">Label's unconstrained desired width.</param>
    /// <param name="valueWidth">Value's unconstrained desired width.</param>
    /// <returns><see langword="true"/> when label, gap and value together exceed <paramref name="availableWidth"/>.</returns>
    public static bool ShouldStack(double availableWidth, double labelWidth, double valueWidth)
    {
        if (double.IsNaN(availableWidth) || double.IsInfinity(availableWidth)) return false;
        return labelWidth + ColumnSpacing + valueWidth > availableWidth;
    }
}
#endregion
