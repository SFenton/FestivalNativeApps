using Festival.Core.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Suggestions line template
/// <summary>
/// Chooses a Suggestions line's template (pattern <c>wide-columns</c>, issue #653): the single-card list item, or the
/// row-major pair of named card groups. A line's template is fixed for its lifetime; a column change rebuilds the lines.
/// </summary>
public sealed partial class SuggestionLineTemplateSelector : DataTemplateSelector
{
    /// <summary>One card per line.</summary>
    public DataTemplate? Single { get; set; }

    /// <summary>Two cards per line.</summary>
    public DataTemplate? Pair { get; set; }

    /// <inheritdoc />
    protected override DataTemplate? SelectTemplateCore(object item) => item is SuggestionCardLine { Paired: true } ? Pair : Single;

    /// <inheritdoc />
    protected override DataTemplate? SelectTemplateCore(object item, DependencyObject container) => SelectTemplateCore(item);
}
#endregion
