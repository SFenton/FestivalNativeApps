using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Setting value grid
/// <summary>
/// Two-column label/value card body (Settings Version card). Children are read as (label, value) pairs in order, so
/// UI Automation and Narrator keep label → value order. Values share one right-hand column while every label and value
/// fits at its natural width; otherwise (narrow windows, 200% text, long release versions) every value moves under its
/// label instead of clipping the label (<see cref="SettingValueLayout.ShouldStack"/>).
/// </summary>
public sealed partial class SettingValueGrid : Panel
{
    private bool _stacked;

    /// <summary>Vertical space between rows in epx.</summary>
    public double RowSpacing { get; set; } = 8;

    /// <inheritdoc />
    protected override Size MeasureOverride(Size availableSize)
    {
        var unbounded = new Size(double.PositiveInfinity, double.PositiveInfinity);
        double labelWidth = 0, valueWidth = 0;
        for (var i = 0; i < Children.Count; i++)
        {
            Children[i].Measure(unbounded);
            if (i % 2 == 0) labelWidth = Math.Max(labelWidth, Children[i].DesiredSize.Width);
            else valueWidth = Math.Max(valueWidth, Children[i].DesiredSize.Width);
        }

        _stacked = SettingValueLayout.ShouldStack(availableSize.Width, labelWidth, valueWidth);
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
            return new Size(availableSize.Width, height);
        }

        for (var i = 0; i < Children.Count; i += 2)
            height += (rows++ > 0 ? RowSpacing : 0) + RowHeight(i);
        var natural = labelWidth + (valueWidth > 0 ? SettingValueLayout.ColumnSpacing + valueWidth : 0);
        return new Size(double.IsInfinity(availableSize.Width) ? natural : availableSize.Width, height);
    }

    /// <inheritdoc />
    protected override Size ArrangeOverride(Size finalSize)
    {
        double y = 0;
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

    /// <summary>Side-by-side height of the pair starting at <paramref name="labelIndex"/>.</summary>
    /// <param name="labelIndex">Index of the pair's label child.</param>
    /// <returns>Taller of the label and its value.</returns>
    private double RowHeight(int labelIndex) =>
        Math.Max(Children[labelIndex].DesiredSize.Height,
            labelIndex + 1 < Children.Count ? Children[labelIndex + 1].DesiredSize.Height : 0);
}
#endregion
