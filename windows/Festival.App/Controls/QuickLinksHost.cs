using System.ComponentModel;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Host
/// <summary>
/// One-call Quick Links adoption for a page (see <c>.agents/controls/quick-links/windows.md</c>): binds the scroller
/// (<see cref="QuickLinksBinder"/>), gives the header <see cref="QuickLinksMenuButton"/> the model, and swaps it for the
/// persistent <see cref="QuickLinksPane"/> when the page area is at least <see cref="QuickLinks.PaneMinimumWidth"/> wide.
/// Anchors are re-read after the section list changes (data-driven cards), never per frame.
/// </summary>
public sealed class QuickLinksHost
{
    private readonly QuickLinksViewModel model;
    private readonly QuickLinksMenuButton menu;
    private readonly List<QuickLinksMenuButton> copies = [];
    private readonly QuickLinksPane? pane;
    private readonly bool paneAllowed;
    private double width;

    /// <summary>Attaches Quick Links to a page.</summary>
    /// <param name="root">Element whose width is the page area (its <c>SizeChanged</c> picks menu or pane).</param>
    /// <param name="scroller">Page scroller holding the <see cref="QuickLinkAnchor"/> elements.</param>
    /// <param name="model">Page model's Quick Links.</param>
    /// <param name="menu">Header menu button.</param>
    /// <param name="pane">Wide pane, or <see langword="null"/> for pages whose web links are mobile-only (menu below
    /// <paramref name="menuMaxWidth"/> only).</param>
    /// <param name="menuMaxWidth">Page width from which a pane-less page hides its menu (mobile-only web links).</param>
    public QuickLinksHost(FrameworkElement root, ScrollViewer scroller, QuickLinksViewModel model, QuickLinksMenuButton menu,
        QuickLinksPane? pane, double menuMaxWidth = double.PositiveInfinity)
    {
        this.model = model;
        this.menu = menu;
        this.pane = pane;
        paneAllowed = pane is not null;
        MenuMaxWidth = menuMaxWidth;
        Binder = new QuickLinksBinder(scroller, model, () => QuickLinksBinder.ReducedMotion(App.Session.Settings.ReduceMotion));
        menu.Model = model;
        if (pane is not null)
        {
            pane.Model = model;
            CollapsedToolTip.CloseWhenCollapsed(pane);
        }
        root.SizeChanged += (_, e) =>
        {
            width = e.NewSize.Width;
            Apply();
        };
        model.PropertyChanged += OnModelChanged;
        Apply();
    }

    /// <summary>The scroller binding (call <see cref="QuickLinksBinder.Collect"/> after replacing anchored content).</summary>
    public QuickLinksBinder Binder { get; }

    /// <summary>Page width from which a pane-less page hides its menu.</summary>
    public double MenuMaxWidth { get; }

    /// <summary>
    /// Adds a second copy of the header menu that a pinned bar shows while the header is scrolled away (Song Detail's
    /// compact header, issue #639). It shares the model and is suppressed exactly where the header menu is.
    /// </summary>
    /// <param name="copy">The pinned bar's menu button.</param>
    public void AddMenu(QuickLinksMenuButton copy)
    {
        copy.Model = model;
        copies.Add(copy);
        Apply();
    }

    /// <summary>
    /// Shows or hides the entry points with availability and re-reads anchors once new sections have been laid out. When
    /// a page's content gate opens, the entry points fade in with the content's entrance (load-transition R1, #649).
    /// </summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Change.</param>
    private void OnModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(QuickLinksViewModel.IsContentShown) && model.IsContentShown) FadeAfterLayout();
        if (e.PropertyName == nameof(QuickLinksViewModel.IsAvailable)) Apply();
        if (e.PropertyName != nameof(QuickLinksViewModel.Items)) return;
        Apply();
        DispatcherQueue.GetForCurrentThread()?.TryEnqueue(DispatcherQueuePriority.Low, Binder.Refresh);
    }

    /// <summary>
    /// Fades the entry points in once the layout that realizes the gated content has run, so they start with the content's
    /// first fade rather than finishing theirs while that (often long) layout pass is still building it.
    /// </summary>
    private void FadeAfterLayout()
    {
        void OnLayout(object? sender, object e)
        {
            menu.LayoutUpdated -= OnLayout;
            FadeIn.Play(menu);
            foreach (var copy in copies) FadeIn.Play(copy);
            if (pane is not null) FadeIn.Play(pane);
        }
        menu.LayoutUpdated += OnLayout;
    }

    /// <summary>Menu below the pane width (or below <see cref="MenuMaxWidth"/> without a pane), pane from it.</summary>
    private void Apply()
    {
        var wide = paneAllowed && width > 0 && QuickLinks.UsesPane(width);
        // Focus on the entry point that the swap hides follows it to the other one, programmatically (no keyboard
        // tooltip, and focus doesn't fall to the next control), as for every responsive swap (#571).
        var menuFocused = CollapsedToolTip.HasFocusWithin(menu);
        var paneFocused = pane is not null && CollapsedToolTip.HasFocusWithin(pane);
        if (pane is not null) pane.Visibility = wide && model.IsAvailable ? Visibility.Visible : Visibility.Collapsed;
        // The button still hides itself below two sections; this only suppresses it where the pane replaces it.
        menu.IsSuppressed = wide || (!paneAllowed && width >= MenuMaxWidth);
        foreach (var copy in copies) copy.IsSuppressed = menu.IsSuppressed;
        if (menuFocused && menu.Visibility == Visibility.Collapsed && pane is { Visibility: Visibility.Visible })
            CollapsedToolTip.HandFocusWith(pane, pane.FocusCurrent);
        else if (paneFocused && pane!.Visibility == Visibility.Collapsed && menu.Visibility == Visibility.Visible)
            CollapsedToolTip.HandFocus(menu, () => menu);
    }
}
#endregion
