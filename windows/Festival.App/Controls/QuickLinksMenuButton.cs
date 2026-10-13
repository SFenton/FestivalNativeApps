using System.ComponentModel;
using Microsoft.UI.Dispatching;
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
    private bool suppressed;
    private bool chosen;
    private string? pendingJump;
    private readonly ToolTip toolTip = new() { Content = "Quick Links" };

    /// <summary>Fluent's minimum touch target in epx, matching the <c>FSTMinTargetSize</c> resource.</summary>
    public const double MinTargetSize = 40;

    /// <summary>Creates the button.</summary>
    public QuickLinksMenuButton()
    {
        Content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            Children = { new FontIcon { Glyph = "", FontSize = 14 }, new TextBlock { Text = "Quick Links" } },
        };
        AutomationProperties.SetAutomationId(this, "fst.quick-links.open");
        // Fluent's 40 epx minimum touch target (Styles.xaml FSTMinTargetSize; issue #72): DropDownButton is 32 by default.
        MinHeight = MinTargetSize;
        Flyout = new MenuFlyout
        {
            Placement = Microsoft.UI.Xaml.Controls.Primitives.FlyoutPlacementMode.BottomEdgeAlignedRight,
            // In-window (not a windowed PopupHost, which Axe flags; issue #534, windows-accessibility.md open item 8).
            ShouldConstrainToRootBounds = true,
            // The presenter is the UIA Menu: Narrator reads its name on open (Axe requires one).
            MenuFlyoutPresenterStyle = new Style(typeof(MenuFlyoutPresenter))
            {
                Setters = { new Setter(AutomationProperties.NameProperty, "Quick Links") },
            },
        };
        Flyout.Opening += (_, _) => Populate();
        Flyout.Closed += OnFlyoutClosed;
        ToolTipService.SetToolTip(this, toolTip);
        // A wide page's pane replaces the button (IsSuppressed): an open tooltip must not outlive it (#571).
        CollapsedToolTip.CloseWhenCollapsed(this);
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

    /// <summary>Hides the button while a page shows the pane instead (or has no desktop Quick Links).</summary>
    public bool IsSuppressed
    {
        get => suppressed;
        set
        {
            if (suppressed == value) return;
            suppressed = value;
            Sync();
        }
    }

    /// <summary>Rebuilds the menu each time it opens (cheap; nothing is kept while closed).</summary>
    private void Populate()
    {
        var menu = (MenuFlyout)Flyout;
        chosen = false;
        menu.Items.Clear();
        if (model is null) return;
        foreach (var item in model.Items)
        {
            var entry = new RadioMenuFlyoutItem
            {
                Text = item.Title,
                GroupName = "fst-quick-links",
                IsChecked = item.IsActive,
                Icon = item.HasIcon ? new ImageIcon { Source = InstrumentIcon.Bitmap(item.IconFile) }
                    : item.Glyph.Length > 0 ? new FontIcon { Glyph = item.Glyph } : null,
            };
            AutomationProperties.SetAutomationId(entry, item.AutomationId);
            AutomationProperties.SetName(entry, item.AccessibleName);
            var id = item.Section.Id;
            entry.Click += (_, _) => Choose(id);
            // A radio item's UIA peer offers Toggle, not Invoke: Narrator's default action and other UIA clients check it
            // without raising Click, so a newly checked item jumps too.
            entry.RegisterPropertyChangedCallback(ToggleMenuFlyoutItem.IsCheckedProperty, (sender, _) =>
            {
                if (sender is ToggleMenuFlyoutItem { IsChecked: true }) Choose(id);
            });
            menu.Items.Add(entry);
        }
    }

    /// <summary>
    /// Jumps once per menu opening (a pointer or keyboard pick both checks the item and clicks it). The jump waits until
    /// the menu has closed: closing restores keyboard focus to this button, and a restore that lands after the jump's
    /// scroll brings the button back into view where it scrolls with the page (compact and medium layouts at large
    /// text), which hands Quick Links back to the top section (#548: "current section Global Statistics" after a Drums
    /// pick at 225% text).
    /// </summary>
    /// <param name="id">Section ID.</param>
    private void Choose(string id)
    {
        if (chosen) return;
        chosen = true;
        if (!Flyout.IsOpen)
        {
            model?.Jump(id);
            return;
        }
        pendingJump = id;
        Flyout.Hide();
    }

    /// <summary>
    /// Runs the picked jump after the menu's focus restore: Low priority runs it once the close (and the bring-into-view
    /// that focus requests) has been processed, so the jump's scroll is the last one.
    /// </summary>
    /// <param name="sender">Menu.</param>
    /// <param name="e">Unused.</param>
    private void OnFlyoutClosed(object? sender, object e)
    {
        if (pendingJump is not { } id) return;
        pendingJump = null;
        if (!DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () => model?.Jump(id))) model?.Jump(id);
    }

    /// <summary>Tracks availability and the accessible name.</summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Change.</param>
    private void OnModelChanged(object? sender, PropertyChangedEventArgs e) => Sync();

    /// <summary>Applies availability and the accessible name ("Quick Links, current section …").</summary>
    private void Sync()
    {
        Visibility = !suppressed && model?.IsAvailable == true ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetName(this, model?.EntryName ?? "Quick Links");
        toolTip.Content = model?.ActiveTitle is { Length: > 0 } active ? $"Quick Links: {active}" : "Quick Links";
    }
}
#endregion
