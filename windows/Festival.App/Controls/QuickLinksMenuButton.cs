using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Menu button
/// <summary>
/// Compact/medium Quick Links entry point: a <see cref="DropDownButton"/> ("Quick Links", compass glyph) whose
/// <see cref="MenuFlyout"/> lists sections as radio items with the current section checked (Fluent: choose one of a
/// small set of destinations without leaving the page). Hidden with fewer than two sections.
/// </summary>
public sealed partial class QuickLinksMenuButton : DropDownButton
{
    private QuickLinksViewModel? model;

    /// <summary>Creates the button.</summary>
    public QuickLinksMenuButton()
    {
        Content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            Children = { new FontIcon { Glyph = "", FontSize = 14 }, new TextBlock { Text = "Quick Links" } },
        };
        AutomationProperties.SetAutomationId(this, "fst.quick-links.open");
        Flyout = new MenuFlyout { Placement = Microsoft.UI.Xaml.Controls.Primitives.FlyoutPlacementMode.BottomEdgeAlignedRight };
        Flyout.Opening += (_, _) => Populate();
    }

    /// <summary>The page's Quick Links model.</summary>
    public QuickLinksViewModel? Model
    {
        get => model;
        set
        {
            if (model is not null) model.PropertyChanged -= OnModelChanged;
            model = value;
            if (model is not null) model.PropertyChanged += OnModelChanged;
            Sync();
        }
    }

    /// <summary>Rebuilds the menu each time it opens (cheap; nothing is kept while closed).</summary>
    private void Populate()
    {
        var menu = (MenuFlyout)Flyout;
        menu.Items.Clear();
        if (model is null) return;
        foreach (var item in model.Items)
        {
            var entry = new RadioMenuFlyoutItem
            {
                Text = item.Title,
                GroupName = "fst-quick-links",
                IsChecked = item.IsActive,
                Icon = item.Glyph.Length > 0 ? new FontIcon { Glyph = item.Glyph } : null,
            };
            AutomationProperties.SetAutomationId(entry, item.AutomationId);
            AutomationProperties.SetName(entry, item.AccessibleName);
            var id = item.Section.Id;
            entry.Click += (_, _) => model.Jump(id);
            menu.Items.Add(entry);
        }
    }

    /// <summary>Tracks availability and the accessible name.</summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Change.</param>
    private void OnModelChanged(object? sender, PropertyChangedEventArgs e) => Sync();

    /// <summary>Applies availability and the accessible name ("Quick Links, current section …").</summary>
    private void Sync()
    {
        Visibility = model?.IsAvailable == true ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetName(this, model?.EntryName ?? "Quick Links");
        ToolTipService.SetToolTip(this, model?.ActiveTitle is { Length: > 0 } active ? $"Quick Links: {active}" : "Quick Links");
    }
}
#endregion
