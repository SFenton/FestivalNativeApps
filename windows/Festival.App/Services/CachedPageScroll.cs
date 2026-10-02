using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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
/// page's scrollers while it is off screen and restored when it is shown again; focus itself still lands where it did.
/// </summary>
internal static class CachedPageScroll
{
    /// <summary>Scrollers paused on each outgoing cached page.</summary>
    private static readonly ConditionalWeakTable<Page, List<ScrollViewer>> Paused = new();

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
            if (e.Content is Page page) Resume(page);
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

    /// <summary>Stops the page's scrollers following focus.</summary>
    /// <param name="page">Outgoing cached page.</param>
    private static void Pause(Page page)
    {
        Resume(page);
        var scrollers = new List<ScrollViewer>();
        Collect(page, scrollers);
        foreach (var scroller in scrollers) scroller.BringIntoViewOnFocusChange = false;
        if (scrollers.Count > 0) Paused.AddOrUpdate(page, scrollers);
    }

    /// <summary>Lets the page's paused scrollers follow focus again.</summary>
    /// <param name="page">Page shown again.</param>
    private static void Resume(Page page)
    {
        if (!Paused.TryGetValue(page, out var scrollers)) return;
        Paused.Remove(page);
        foreach (var scroller in scrollers) scroller.BringIntoViewOnFocusChange = true;
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
}
#endregion
