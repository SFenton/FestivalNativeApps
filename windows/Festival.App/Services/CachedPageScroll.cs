using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Services;

#region Cached page scroll
/// <summary>
/// Keeps a cached page (<see cref="Page.NavigationCacheMode"/>) at the scroll position the reader left it when a page
/// is pushed over it and Back returns. When the focused control (the View All button just clicked) leaves the window
/// with the outgoing page, WinUI walks focus through the page's remaining controls on the way out, and each scroller
/// brought every one of them into view, so Back showed Leaderboards or Rivals several sections further down (issue
/// #82). Focus-follow scrolling (<see cref="ScrollViewer.BringIntoViewOnFocusChange"/>) is paused on the outgoing
/// page's scrollers while it is off screen and restored when it is shown again. Scroll anchoring is paused with it
/// (<see cref="ScrollViewer.VerticalAnchorRatio"/> NaN, issue #276): when the page re-entered the window, its re-laid
/// rows moved by sub-pixel steps at large text and the anchor followed them, so the page crept up 2 epx. Back also
/// returns keyboard focus to the control that opened the pushed page (issue #276: it fell to the pane toggle, so
/// keyboard and Narrator users lost their place), the way flyouts and dialogs return focus to their invoker.
/// </summary>
internal static class CachedPageScroll
{
    /// <summary>Scrollers paused on each outgoing cached page, with the anchor ratio to restore.</summary>
    private static readonly ConditionalWeakTable<Page, List<(ScrollViewer Scroller, double AnchorRatio)>> Paused = new();

    /// <summary>The control that had focus when each cached page was left.</summary>
    private static readonly ConditionalWeakTable<Page, LeftFocus> Focused = new();

    /// <summary>Follows a section frame's navigations.</summary>
    /// <param name="frame">Section frame.</param>
    public static void Attach(Frame frame)
    {
        frame.Navigating += (_, _) =>
        {
            if (frame.Content is Page { NavigationCacheMode: not NavigationCacheMode.Disabled } page) Pause(page);
        };
        frame.Navigated += (_, e) =>
        {
            if (e.Content is not Page page) return;
            if (e.NavigationMode == NavigationMode.Back) ReturnFocus(page, Focused.TryGetValue(page, out var left) ? left : null);
            else Resume(page);
        };
        // A stopped or failed navigation leaves the page on screen.
        frame.NavigationStopped += (_, _) =>
        {
            if (frame.Content is Page page) Resume(page);
        };
        frame.NavigationFailed += (_, _) =>
        {
            if (frame.Content is Page page) Resume(page);
        };
    }

    /// <summary>Stops the page's scrollers following focus and scroll anchors.</summary>
    /// <param name="page">Outgoing cached page.</param>
    private static void Pause(Page page)
    {
        Resume(page);
        Remember(page);
        var scrollers = new List<ScrollViewer>();
        Collect(page, scrollers);
        var paused = new List<(ScrollViewer Scroller, double AnchorRatio)>();
        foreach (var scroller in scrollers)
        {
            paused.Add((scroller, scroller.VerticalAnchorRatio));
            scroller.BringIntoViewOnFocusChange = false;
            scroller.VerticalAnchorRatio = double.NaN;
        }
        if (paused.Count > 0) Paused.AddOrUpdate(page, paused);
    }

    /// <summary>Records the page's focused control before WinUI walks focus away from it.</summary>
    /// <param name="page">Outgoing cached page.</param>
    private static void Remember(Page page)
    {
        Focused.Remove(page);
        if (page.XamlRoot is null
            || FocusManager.GetFocusedElement(page.XamlRoot) is not Control { FocusState: not FocusState.Unfocused } control
            || !IsWithin(control, page)) return;
        Focused.Add(page, new LeftFocus(new WeakReference<Control>(control), control.FocusState, control.DataContext,
            AutomationProperties.GetAutomationId(control)));
    }

    /// <summary>Once the returning page is in the window and laid out, focuses the control that opened the pushed page,
    /// then lets the scrollers follow focus and anchors again (still paused until then, so the page cannot move).</summary>
    /// <param name="page">Page shown again by Back.</param>
    /// <param name="left">Focus recorded when the page was left, or <see langword="null"/> when none was.</param>
    private static void ReturnFocus(Page page, LeftFocus? left)
    {
        Focused.Remove(page);
        if (page.IsLoaded) Queue(page, left);
        else
        {
            void OnLoaded(object sender, RoutedEventArgs e)
            {
                page.Loaded -= OnLoaded;
                Queue(page, left);
            }
            page.Loaded += OnLoaded;
        }
    }

    /// <summary>Runs the focus return after layout, when the cached controls are live again.</summary>
    /// <param name="page">Page shown again by Back.</param>
    /// <param name="left">Focus recorded when the page was left, or <see langword="null"/> when none was.</param>
    private static void Queue(Page page, LeftFocus? left)
    {
        if (!page.DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () => Restore(page, left)))
            Resume(page);
    }

    /// <summary>Focuses the remembered control (or the row now showing the same item) unless the reader has moved focus
    /// into the navigation pane (re-invoking the section's pane item also pops back to this page).</summary>
    /// <param name="page">Page shown again by Back.</param>
    /// <param name="left">Focus recorded when the page was left, or <see langword="null"/> when none was.</param>
    private static void Restore(Page page, LeftFocus? left)
    {
        if (left is null || page.XamlRoot is null || FocusManager.GetFocusedElement(page.XamlRoot) is NavigationViewItem
            || Target(page, left) is not { } control)
        {
            Resume(page);
            return;
        }
        // Back must not move the page (#82), so the bring-into-view request that focusing raises is dropped and the
        // scrollers follow focus again once it has been handled. A control left partly visible (clicked at the edge,
        // or the window was resized meanwhile) scrolls into view only with the next key press.
        control.BringIntoViewRequested += Hold;
        control.Focus(left.State);
        void Release()
        {
            control.BringIntoViewRequested -= Hold;
            Resume(page);
        }
        if (!page.DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, Release)) Release();
    }

    /// <summary>The control to return focus to: the one left when it is still shown with the same item, otherwise the
    /// shown control with the same automation ID, preferring one bound to the same item. Songs re-projects its rows on
    /// return when the Shop or scores changed while it was away (an unchanged list keeps its rows, #560); a list may
    /// re-realize the item in a new container and keep the old one collapsed (Suggestions, #276); and
    /// an automation ID can repeat on a page (a song in two Suggestions cards).</summary>
    /// <param name="page">Page shown again by Back.</param>
    /// <param name="left">Focus recorded when the page was left.</param>
    /// <returns>The control, or <see langword="null"/> to leave focus where WinUI put it.</returns>
    private static Control? Target(Page page, LeftFocus left)
    {
        if (left.Control.TryGetTarget(out var control) && Focusable(control, page)
            && ReferenceEquals(control.DataContext, left.DataContext)
            && AutomationProperties.GetAutomationId(control) == left.AutomationId) return control;
        if (string.IsNullOrEmpty(left.AutomationId)) return null;
        Control? first = null;
        return Find(page, left, page, ref first) ?? first;
    }

    /// <summary>Finds a shown, focusable control by automation ID, skipping collapsed subtrees.</summary>
    /// <param name="element">Subtree root.</param>
    /// <param name="left">Focus recorded when the page was left.</param>
    /// <param name="page">Owning page.</param>
    /// <param name="first">The first match in tree order, whatever item it shows.</param>
    /// <returns>The first match bound to the item left, or <see langword="null"/>.</returns>
    private static Control? Find(DependencyObject element, LeftFocus left, Page page, ref Control? first)
    {
        if (element is UIElement { Visibility: not Visibility.Visible }) return null;
        if (element is Control control && AutomationProperties.GetAutomationId(control) == left.AutomationId
            && Focusable(control, page))
        {
            if (ReferenceEquals(control.DataContext, left.DataContext)) return control;
            first ??= control;
        }
        var count = VisualTreeHelper.GetChildrenCount(element);
        for (var i = 0; i < count; i++)
            if (Find(VisualTreeHelper.GetChild(element, i), left, page, ref first) is { } found) return found;
        return null;
    }

    /// <summary>Whether a control is shown in the page and can take focus.</summary>
    /// <param name="control">Control.</param>
    /// <param name="page">Owning page.</param>
    /// <returns><see langword="true"/> when loaded and enabled, and it and every ancestor up to <paramref name="page"/>
    /// are visible.</returns>
    private static bool Focusable(Control control, Page page)
    {
        if (control is not { IsLoaded: true, IsEnabled: true }) return false;
        for (DependencyObject? node = control; node is not null; node = VisualTreeHelper.GetParent(node))
        {
            if (node is UIElement { Visibility: not Visibility.Visible }) return false;
            if (ReferenceEquals(node, page)) return true;
        }
        return false;
    }

    /// <summary>Drops a bring-into-view request while focus returns.</summary>
    /// <param name="sender">Control focus returned to.</param>
    /// <param name="args">Request.</param>
    private static void Hold(UIElement sender, BringIntoViewRequestedEventArgs args) => args.Handled = true;

    /// <summary>Whether an element is inside a page's visual tree.</summary>
    /// <param name="element">Element.</param>
    /// <param name="page">Page.</param>
    /// <returns><see langword="true"/> when <paramref name="page"/> is an ancestor (or the element itself).</returns>
    private static bool IsWithin(DependencyObject element, Page page)
    {
        for (var node = element; node is not null; node = VisualTreeHelper.GetParent(node))
            if (ReferenceEquals(node, page)) return true;
        return false;
    }

    /// <summary>Lets the page's paused scrollers follow focus and scroll anchors again.</summary>
    /// <param name="page">Page shown again.</param>
    private static void Resume(Page page)
    {
        if (!Paused.TryGetValue(page, out var scrollers)) return;
        Paused.Remove(page);
        foreach (var (scroller, anchorRatio) in scrollers)
        {
            scroller.BringIntoViewOnFocusChange = true;
            scroller.VerticalAnchorRatio = anchorRatio;
        }
    }

    /// <summary>Finds the scrollers that currently follow focus.</summary>
    /// <param name="element">Subtree root.</param>
    /// <param name="found">Scrollers collected so far.</param>
    private static void Collect(DependencyObject element, List<ScrollViewer> found)
    {
        if (element is ScrollViewer { BringIntoViewOnFocusChange: true } scroller) found.Add(scroller);
        var count = VisualTreeHelper.GetChildrenCount(element);
        for (var i = 0; i < count; i++) Collect(VisualTreeHelper.GetChild(element, i), found);
    }

    /// <summary>A page's focused control when it was left.</summary>
    /// <param name="Control">The control, held weakly.</param>
    /// <param name="State">How it was focused (keyboard focus keeps its visible rectangle; pointer focus does not).</param>
    /// <param name="DataContext">The item it showed, to skip a recycled container.</param>
    /// <param name="AutomationId">Its automation ID, to find the row showing the same item after a rebind.</param>
    private sealed record LeftFocus(WeakReference<Control> Control, FocusState State, object? DataContext, string AutomationId);
}
#endregion
