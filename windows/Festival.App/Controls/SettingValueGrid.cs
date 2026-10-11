using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Setting value grid
/// <summary>
/// The Windows Settings value row (pattern <c>settings-value-row</c>): label/value pairs for the Version card and the
/// Service Info "Leaderboard Service State" row. Children are read as (label, value) pairs in order, so UI Automation and
/// Narrator keep label → value order. Values share one right-hand column, vertically centred on their label, while every
/// label's title and value fit at their natural widths; otherwise (narrow windows, large text, long release versions)
/// every value moves under its label, start-aligned, instead of clipping the label (<see cref="SettingValueLayout.ShouldStack"/>).
/// A label may be a panel whose first child is the title and whose later children are supporting text: the supporting
/// text wraps under the title and never counts toward the fit (R1).
/// </summary>
public sealed partial class SettingValueGrid : Panel
{
    private bool _stacked;
    private double _contentHeight;

    /// <summary>Vertical space between rows in epx.</summary>
    public double RowSpacing { get; set; } = 8;

    /// <inheritdoc />
    protected override Size MeasureOverride(Size availableSize)
    {
        var unbounded = new Size(double.PositiveInfinity, double.PositiveInfinity);
        double fitWidth = 0, naturalLabelWidth = 0, valueWidth = 0;
        for (var i = 0; i < Children.Count; i++)
        {
            Children[i].Measure(unbounded);
            if (i % 2 == 1)
            {
                valueWidth = Math.Max(valueWidth, Children[i].DesiredSize.Width);
                continue;
            }
            fitWidth = Math.Max(fitWidth, TitleWidth(Children[i]));
            naturalLabelWidth = Math.Max(naturalLabelWidth, Children[i].DesiredSize.Width);
        }

        _stacked = SettingValueLayout.ShouldStack(availableSize.Width, fitWidth, valueWidth);
        double height = 0;
        var rows = 0;
        if (_stacked)
        {
            var bounded = new Size(availableSize.Width, double.PositiveInfinity);
            for (var i = 0; i < Children.Count; i += 2)
            {
                Children[i].Measure(bounded);
                height += (rows++ > 0 ? RowSpacing : 0) + Children[i].DesiredSize.Height;
                if (i + 1 < Children.Count)
                {
                    Children[i + 1].Measure(bounded);
                    height += SettingValueLayout.StackedSpacing + Children[i + 1].DesiredSize.Height;
                }
            }
            _contentHeight = height;
            return new Size(availableSize.Width, height);
        }

        // Supporting text wraps in the label column; a title that fits keeps its one line.
        var valueColumn = valueWidth > 0 ? SettingValueLayout.ColumnSpacing + valueWidth : 0;
        var labelColumn = double.IsInfinity(availableSize.Width) ? double.PositiveInfinity : Math.Max(0, availableSize.Width - valueColumn);
        for (var i = 0; i < Children.Count; i += 2)
        {
            Children[i].Measure(new Size(labelColumn, double.PositiveInfinity));
            height += (rows++ > 0 ? RowSpacing : 0) + RowHeight(i);
        }
        _contentHeight = height;
        return new Size(double.IsInfinity(availableSize.Width) ? naturalLabelWidth + valueColumn : availableSize.Width, height);
    }

    /// <inheritdoc />
    protected override Size ArrangeOverride(Size finalSize)
    {
        // A MinHeight taller than the content centres the rows (the Service Info row's 56 epx minimum).
        var y = Math.Max(0, (finalSize.Height - _contentHeight) / 2);
        if (_stacked)
        {
            for (var i = 0; i < Children.Count; i += 2)
            {
                if (i > 0) y += RowSpacing;
                var label = Children[i];
                label.Arrange(new Rect(0, y, finalSize.Width, label.DesiredSize.Height));
                y += label.DesiredSize.Height;
                if (i + 1 >= Children.Count) continue;
                var value = Children[i + 1];
                y += SettingValueLayout.StackedSpacing;
                value.Arrange(new Rect(0, y, Math.Min(value.DesiredSize.Width, finalSize.Width), value.DesiredSize.Height));
                y += value.DesiredSize.Height;
            }
            return finalSize;
        }

        double valueWidth = 0;
        for (var i = 1; i < Children.Count; i += 2) valueWidth = Math.Max(valueWidth, Children[i].DesiredSize.Width);
        var valueX = Math.Max(0, finalSize.Width - valueWidth);
        var labelWidth = Math.Max(0, valueX - (valueWidth > 0 ? SettingValueLayout.ColumnSpacing : 0));
        for (var i = 0; i < Children.Count; i += 2)
        {
            if (i > 0) y += RowSpacing;
            var rowHeight = RowHeight(i);
            var label = Children[i];
            label.Arrange(new Rect(0, y + (rowHeight - label.DesiredSize.Height) / 2, labelWidth, label.DesiredSize.Height));
            if (i + 1 < Children.Count)
            {
                var value = Children[i + 1];
                value.Arrange(new Rect(valueX, y + (rowHeight - value.DesiredSize.Height) / 2, value.DesiredSize.Width, value.DesiredSize.Height));
            }
            y += rowHeight;
        }
        return finalSize;
    }

    /// <summary>Natural width that decides the fit for one label (measured unconstrained).</summary>
    /// <param name="label">Label child: a text element, or a panel whose first visible child is the title.</param>
    /// <returns>The title's width; a panel's later children are supporting text and don't count (R1).</returns>
    private static double TitleWidth(UIElement label)
    {
        if (label is not Panel panel) return label.DesiredSize.Width;
        foreach (var child in panel.Children)
            if (child.Visibility == Visibility.Visible) return child.DesiredSize.Width;
        return 0;
    }

    /// <summary>Side-by-side height of the pair starting at <paramref name="labelIndex"/>.</summary>
    /// <param name="labelIndex">Index of the pair's label child.</param>
    /// <returns>Taller of the label and its value.</returns>
    private double RowHeight(int labelIndex) =>
        Math.Max(Children[labelIndex].DesiredSize.Height,
            labelIndex + 1 < Children.Count ? Children[labelIndex + 1].DesiredSize.Height : 0);
}
#endregion
