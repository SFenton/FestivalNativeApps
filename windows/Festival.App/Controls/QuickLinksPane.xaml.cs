using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Pane
/// <summary>Wide-window Quick Links pane (web ≥1440 px rail): selecting jumps without closing anything.</summary>
public sealed partial class QuickLinksPane : UserControl
{
    /// <summary>Model dependency property.</summary>
    public static readonly DependencyProperty ModelProperty =
        DependencyProperty.Register(nameof(Model), typeof(QuickLinksViewModel), typeof(QuickLinksPane), new PropertyMetadata(null));

    /// <summary>Creates the pane.</summary>
    public QuickLinksPane()
    {
        InitializeComponent();
        // UIA names/IDs belong on the ListViewItem containers (the invokable elements), not their content.
        List.ContainerContentChanging += (_, e) =>
        {
            if (e.Item is not QuickLinkItemViewModel item) return;
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(e.ItemContainer, item.AutomationId);
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(e.ItemContainer, item.Section.AccessibleTitle);
        };
    }

    /// <summary>The page's Quick Links model.</summary>
    public QuickLinksViewModel? Model
    {
        get => (QuickLinksViewModel?)GetValue(ModelProperty);
        set => SetValue(ModelProperty, value);
    }

    /// <summary>Jumps to the clicked section.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked item.</param>
    private void OnItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is QuickLinkItemViewModel item) Model?.Jump(item.Section.Id);
    }
}
#endregion
