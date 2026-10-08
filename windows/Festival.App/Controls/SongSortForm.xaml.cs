using Festival.Core.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Song sort form
/// <summary>
/// The Sort flyout's form (songs-sort control): heading, <b>Sort By</b> and <b>Direction</b> radio groups and the red
/// Reset, bound to a live <see cref="SongSortDraft"/>. Shared by Songs and the Item Shop (issue #379); each page keeps
/// its own Sort <c>DropDownButton</c> and calls <see cref="SongSortDraft.Begin"/> when its flyout opens. Adds no UI
/// Automation element of its own, so the flyout's controls read as before.
/// </summary>
public sealed partial class SongSortForm : UserControl
{
    /// <summary>Bound draft.</summary>
    public static readonly DependencyProperty DraftProperty = DependencyProperty.Register(
        nameof(Draft), typeof(SongSortDraft), typeof(SongSortForm), new PropertyMetadata(null, OnDraftChanged));

    /// <summary>Heading text.</summary>
    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title), typeof(string), typeof(SongSortForm), new PropertyMetadata("Sort"));

    /// <summary>Automation ID root.</summary>
    public static readonly DependencyProperty IdPrefixProperty = DependencyProperty.Register(
        nameof(IdPrefix), typeof(string), typeof(SongSortForm), new PropertyMetadata("fst.songs.sort", OnIdPrefixChanged));

    /// <summary>Creates the form.</summary>
    public SongSortForm()
    {
        InitializeComponent();
        ApplyIds();
    }

    /// <summary>Live sort draft.</summary>
    public SongSortDraft? Draft
    {
        get => (SongSortDraft?)GetValue(DraftProperty);
        set => SetValue(DraftProperty, value);
    }

    /// <summary>Heading, e.g. "Sort Songs" or "Sort Item Shop".</summary>
    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    /// <summary>
    /// Automation ID root (the host button's ID): the form is <c>.form</c>, the groups <c>.mode</c> and
    /// <c>.direction</c>, the rows <c>.direction.ascending</c> / <c>.direction.descending</c> and the button <c>.reset</c>.
    /// </summary>
    public string IdPrefix
    {
        get => (string)GetValue(IdPrefixProperty);
        set => SetValue(IdPrefixProperty, value);
    }

    private static void OnDraftChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((SongSortForm)d).Bindings.Update();

    private static void OnIdPrefixChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((SongSortForm)d).ApplyIds();

    /// <summary>Applies the automation IDs under <see cref="IdPrefix"/>.</summary>
    private void ApplyIds()
    {
        var prefix = IdPrefix;
        AutomationProperties.SetAutomationId(Root, prefix + ".form");
        AutomationProperties.SetAutomationId(ModeGroup, prefix + ".mode");
        AutomationProperties.SetAutomationId(DirectionGroup, prefix + ".direction");
        AutomationProperties.SetAutomationId(AscendingOption, prefix + ".direction.ascending");
        AutomationProperties.SetAutomationId(DescendingOption, prefix + ".direction.descending");
        AutomationProperties.SetAutomationId(ResetButton, prefix + ".reset");
    }
}
#endregion
