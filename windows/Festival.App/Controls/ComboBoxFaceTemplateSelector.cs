using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region ComboBox face template selector
/// <summary>
/// Lets a <see cref="ComboBox"/> show a shorter face than its drop-down options: every option keeps
/// <see cref="ItemTemplate"/> (icon and name), while the closed box's selected-item face switches to
/// <see cref="FaceTemplate"/> (icon only) when <see cref="IconOnly"/> is set (Paths compact row, issue #612). Use it as the
/// box's <c>ItemTemplateSelector</c>. A non-inline <c>ComboBox</c> copies the selected container's template selector to its
/// template's face <c>ContentPresenter</c>, which asks with itself as the container; options ask from inside a
/// <see cref="ComboBoxItem"/>. The box's value, Narrator name and option list are unchanged.
/// </summary>
public sealed partial class ComboBoxFaceTemplateSelector : DataTemplateSelector
{
    /// <summary>Template for every drop-down option, and for the face while <see cref="IconOnly"/> is off.</summary>
    public DataTemplate? ItemTemplate { get; set; }

    /// <summary>Template for the closed box's face while <see cref="IconOnly"/> is on.</summary>
    public DataTemplate? FaceTemplate { get; set; }

    /// <summary>Whether the face shows <see cref="FaceTemplate"/>; call <see cref="Refresh"/> after changing it.</summary>
    public bool IconOnly { get; set; }

    /// <inheritdoc />
    protected override DataTemplate? SelectTemplateCore(object item) => ItemTemplate;

    /// <inheritdoc />
    protected override DataTemplate? SelectTemplateCore(object item, DependencyObject container) =>
        IconOnly && FaceTemplate is { } face && IsFace(container) ? face : ItemTemplate;

    /// <summary>Re-selects the face template of <paramref name="box"/> after <see cref="IconOnly"/> changed.</summary>
    /// <param name="box">A combo box whose <c>ItemTemplateSelector</c> is this selector.</param>
    public void Refresh(ComboBox box)
    {
        // The face presenter only re-selects when its selector changes (ContentPresenter.OnContentTemplateSelectorChanged).
        if (FindFace(box) is not { } presenter) return;
        presenter.ContentTemplateSelector = null;
        presenter.ContentTemplateSelector = this;
    }

    /// <summary>Whether a template container is the closed box's face rather than a drop-down option.</summary>
    /// <param name="container">Container passed to <c>SelectTemplate</c>.</param>
    /// <returns><see langword="true"/> when a <see cref="ComboBox"/> is reached before any <see cref="ComboBoxItem"/>.</returns>
    private static bool IsFace(DependencyObject? container)
    {
        for (var node = container; node is not null; node = VisualTreeHelper.GetParent(node))
        {
            if (node is ComboBoxItem) return false;
            if (node is ComboBox) return true;
        }

        return false;
    }

    /// <summary>Finds the face <see cref="ContentPresenter"/> that uses this selector in the box's template.</summary>
    /// <param name="root">Element to search (the combo box; its drop-down popup is not a visual child).</param>
    /// <returns>The presenter, or <see langword="null"/> before the template is applied.</returns>
    private ContentPresenter? FindFace(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is ComboBoxItem) continue;
            if (child is ContentPresenter presenter && ReferenceEquals(presenter.ContentTemplateSelector, this)) return presenter;
            if (FindFace(child) is { } found) return found;
        }

        return null;
    }
}
#endregion
