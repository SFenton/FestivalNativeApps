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
        if (pane is not null) pane.Model = model;
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

    /// <summary>Re-reads anchors once the new sections have been laid out.</summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Change.</param>
    private void OnModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(QuickLinksViewModel.Items)) return;
        Apply();
        DispatcherQueue.GetForCurrentThread()?.TryEnqueue(DispatcherQueuePriority.Low, Binder.Refresh);
    }

    /// <summary>Menu below the pane width (or below <see cref="MenuMaxWidth"/> without a pane), pane from it.</summary>
    private void Apply()
    {
        var wide = paneAllowed && width > 0 && QuickLinks.UsesPane(width);
        if (pane is not null) pane.Visibility = wide && model.IsAvailable ? Visibility.Visible : Visibility.Collapsed;
        // The button still hides itself below two sections; this only suppresses it where the pane replaces it.
        menu.IsSuppressed = wide || (!paneAllowed && width >= MenuMaxWidth);
    }
}
#endregion
