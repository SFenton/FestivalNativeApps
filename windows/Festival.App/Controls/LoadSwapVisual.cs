using System.ComponentModel;
using Festival.App.Services;
using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace Festival.App.Controls;

#region Load-swap visuals
/// <summary>Which side of a <see cref="LoadSwap"/> an element represents.</summary>
public enum LoadSwapVisualRole
{
    /// <summary>Rows, empty state or failure content that fades out during a reload.</summary>
    Content,
    /// <summary>The centered loading spinner that fades out before content is revealed.</summary>
    Spinner,
}

/// <summary>
/// Attached presentation for <see cref="LoadSwap"/>: content receives the 300 ms fade-out transition, the spinner
/// receives the 500 ms fade-out transition, and both disable transitions completely when app/system motion is off.
/// </summary>
public static class LoadSwapVisual
{
    /// <summary>Attached load-swap model.</summary>
    public static readonly DependencyProperty SwapProperty = DependencyProperty.RegisterAttached(
        "Swap", typeof(LoadSwap), typeof(LoadSwapVisual), new PropertyMetadata(null, OnSwapChanged));

    /// <summary>Attached visual role.</summary>
    public static readonly DependencyProperty RoleProperty = DependencyProperty.RegisterAttached(
        "Role", typeof(LoadSwapVisualRole), typeof(LoadSwapVisual), new PropertyMetadata(LoadSwapVisualRole.Content, OnRoleChanged));

    /// <summary>
    /// Whether a content element follows the swap (default). A board's pinned row binds it to its
    /// <see cref="PinnedRowGate.IsGated"/>: while ungated it stays shown, readable and hit-testable through a reload.
    /// Put a gated pinned row in a <see cref="LoadSwapGate"/>, which also hides its children from UI Automation.
    /// </summary>
    public static readonly DependencyProperty IsGatedProperty = DependencyProperty.RegisterAttached(
        "IsGated", typeof(bool), typeof(LoadSwapVisual), new PropertyMetadata(true, OnRoleChanged));

    private static readonly DependencyProperty HandlerProperty = DependencyProperty.RegisterAttached(
        "Handler", typeof(PropertyChangedEventHandler), typeof(LoadSwapVisual), new PropertyMetadata(null));

    private static readonly DependencyProperty MotionHandlerProperty = DependencyProperty.RegisterAttached(
        "MotionHandler", typeof(EventHandler), typeof(LoadSwapVisual), new PropertyMetadata(null));

    /// <summary>Gets the attached swap.</summary>
    /// <param name="element">Element.</param>
    /// <returns>Swap, or <see langword="null"/>.</returns>
    public static LoadSwap? GetSwap(FrameworkElement element) => (LoadSwap?)element.GetValue(SwapProperty);

    /// <summary>Sets the attached swap.</summary>
    /// <param name="element">Element.</param>
    /// <param name="value">Swap.</param>
    public static void SetSwap(FrameworkElement element, LoadSwap? value) => element.SetValue(SwapProperty, value);

    /// <summary>Gets the element role.</summary>
    /// <param name="element">Element.</param>
    /// <returns>Role.</returns>
    public static LoadSwapVisualRole GetRole(FrameworkElement element) => (LoadSwapVisualRole)element.GetValue(RoleProperty);

    /// <summary>Sets the element role.</summary>
    /// <param name="element">Element.</param>
    /// <param name="value">Role.</param>
    public static void SetRole(FrameworkElement element, LoadSwapVisualRole value) => element.SetValue(RoleProperty, value);

    /// <summary>Gets whether the element follows the swap.</summary>
    /// <param name="element">Element.</param>
    /// <returns>Whether it is gated.</returns>
    public static bool GetIsGated(FrameworkElement element) => (bool)element.GetValue(IsGatedProperty);

    /// <summary>Sets whether the element follows the swap.</summary>
    /// <param name="element">Element.</param>
    /// <param name="value">Whether it is gated.</param>
    public static void SetIsGated(FrameworkElement element, bool value) => element.SetValue(IsGatedProperty, value);

    /// <summary>
    /// Keeps a spinner's stretching, Raw region between the visible retained header and floating footer (#624).
    /// The region occupies the result viewport's grid cell/span; the named native ring centres inside it.
    /// Layout is followed only while loading, without altering the swap, focus, visibility or fade timings.
    /// </summary>
    /// <param name="spinner">The region's native busy indicator.</param>
    /// <param name="region">Stretching region containing the ring, not its scroll content.</param>
    /// <param name="retainedHeader">Header inside the viewport, if any.</param>
    /// <param name="footer">Footer floating over the viewport, if any.</param>
    /// <param name="scroller">Scroller of a retained header, if any.</param>
    public static void PlaceSpinner(ProgressRing spinner, FrameworkElement region, FrameworkElement? retainedHeader = null,
        FrameworkElement? footer = null, ScrollViewer? scroller = null)
    {
        var following = false;

        // Edges are measured in the region's layout slot (its parent's cell), which its own margin never changes: deriving
        // the viewport from the region's size let a ring taller than the gap grow the margins every pass (layout cycle).
        double? Edge(FrameworkElement? element, UIElement host, Windows.Foundation.Rect slot, bool bottom)
        {
            if (element is null || !element.IsLoaded || element.ActualHeight <= 0) return null;
            for (DependencyObject? parent = element; parent is not null; parent = VisualTreeHelper.GetParent(parent))
                if (parent is UIElement { Visibility: Visibility.Collapsed }) return null;
            return element.TransformToVisual(host).TransformPoint(default).Y - slot.Y + (bottom ? element.ActualHeight : 0);
        }

        void Update(object? sender, object args)
        {
            if (!region.IsLoaded || !spinner.IsActive || VisualTreeHelper.GetParent(region) is not UIElement host) return;
            var slot = LayoutInformation.GetLayoutSlot(region);
            var margin = region.Margin;
            var (top, bottom) = LoadingRegion.Insets(slot.Height, Edge(retainedHeader, host, slot, true),
                Edge(footer, host, slot, false), spinner.ActualHeight);
            if (Math.Abs(margin.Top - top) < 0.5 && Math.Abs(margin.Bottom - bottom) < 0.5) return;
            region.Margin = new Thickness(margin.Left, top, margin.Right, bottom);
        }

        void Follow()
        {
            var shouldFollow = region.IsLoaded && spinner.IsActive;
            if (following == shouldFollow) return;
            following = shouldFollow;
            if (following)
            {
                region.LayoutUpdated += Update;
                if (scroller is not null) scroller.ViewChanged += Update;
            }
            else
            {
                region.LayoutUpdated -= Update;
                if (scroller is not null) scroller.ViewChanged -= Update;
            }
        }

        region.Loaded += (_, _) => Follow();
        region.Unloaded += (_, _) => Follow();
        spinner.RegisterPropertyChangedCallback(ProgressRing.IsActiveProperty, (_, _) => Follow());
        Follow();
    }

    /// <summary>Subscribes to a new swap and updates immediately.</summary>
    /// <param name="d">Element.</param>
    /// <param name="e">Changed swap.</param>
    private static void OnSwapChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not FrameworkElement element) return;
        Detach(element, e.OldValue as LoadSwap);
        element.Loaded -= OnLoaded;
        element.Unloaded -= OnUnloaded;
        if (e.NewValue is not LoadSwap swap) return;
        // Cached pages (NavigationCacheMode) unload and load again: re-attach on every Loaded.
        element.Loaded += OnLoaded;
        element.Unloaded += OnUnloaded;
        Attach(element, swap);
    }

    /// <summary>Reapplies when the element role or gating changes.</summary>
    /// <param name="d">Element.</param>
    /// <param name="e">Changed role or gating.</param>
    private static void OnRoleChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is FrameworkElement element && GetSwap(element) is { } swap) Apply(element, swap);
    }

    /// <summary>Re-attaches when a cached page's element returns to the tree.</summary>
    /// <param name="sender">Element.</param>
    /// <param name="e">Unused.</param>
    private static void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement element && GetSwap(element) is { } swap) Attach(element, swap);
    }

    /// <summary>Detaches handlers while the element is out of the tree.</summary>
    /// <param name="sender">Element.</param>
    /// <param name="e">Unused.</param>
    private static void OnUnloaded(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement element) Detach(element, GetSwap(element));
    }

    /// <summary>Subscribes the element to its swap and to motion changes (idempotent), then applies the phase.</summary>
    /// <param name="element">Element.</param>
    /// <param name="swap">Swap.</param>
    private static void Attach(FrameworkElement element, LoadSwap swap)
    {
        Detach(element, swap);
        PropertyChangedEventHandler handler = (_, args) =>
        {
            if (args.PropertyName is nameof(LoadSwap.Phase) or nameof(LoadSwap.ContentVisible) or nameof(LoadSwap.SpinnerVisible))
                element.DispatcherQueue.TryEnqueue(() => Apply(element, swap));
        };
        EventHandler motionHandler = (_, _) => element.DispatcherQueue.TryEnqueue(() => Apply(element, swap));
        element.SetValue(HandlerProperty, handler);
        element.SetValue(MotionHandlerProperty, motionHandler);
        swap.PropertyChanged += handler;
        Motion.Changed += motionHandler;
        Apply(element, swap);
    }

    /// <summary>Removes the element's swap and motion subscriptions.</summary>
    /// <param name="element">Element.</param>
    /// <param name="swap">Swap the handler was attached to, if any.</param>
    private static void Detach(FrameworkElement element, LoadSwap? swap)
    {
        if (swap is not null && element.GetValue(HandlerProperty) is PropertyChangedEventHandler handler) swap.PropertyChanged -= handler;
        if (element.GetValue(MotionHandlerProperty) is EventHandler motion) Motion.Changed -= motion;
        element.ClearValue(HandlerProperty);
        element.ClearValue(MotionHandlerProperty);
    }

    /// <summary>Applies visibility, opacity, hit testing and transition duration from the swap phase.</summary>
    /// <param name="element">Element.</param>
    /// <param name="swap">Swap.</param>
    private static void Apply(FrameworkElement element, LoadSwap swap)
    {
        var role = GetRole(element);
        if (role == LoadSwapVisualRole.Spinner)
        {
            element.OpacityTransition = Motion.Allowed && swap.Phase == LoadSwapPhase.SpinnerOut
                ? new ScalarTransition { Duration = LoadSwapTiming.SpinnerOut }
                : null;
            element.Opacity = swap.SpinnerOpacity;
            element.IsHitTestVisible = false;
            AutomationProperties.SetAccessibilityView(element, swap.SpinnerVisible ? AccessibilityView.Content : AccessibilityView.Raw);
            if (element is ProgressRing ring) ring.IsActive = swap.SpinnerVisible;
            return;
        }

        element.OpacityTransition = Motion.Allowed && swap.Phase == LoadSwapPhase.ContentOut
            ? new ScalarTransition { Duration = LoadSwapTiming.ContentOut }
            : null;
        // An ungated element (a pinned row on a page-only reload) keeps showing its still-current content.
        var shown = !GetIsGated(element) || swap.ContentHitTestVisible;
        element.Opacity = GetIsGated(element) ? swap.ContentOpacity : 1;
        element.IsHitTestVisible = shown;
        if (element is LoadSwapGate gate)
        {
            gate.ContentHidden = !shown;
            gate.IsEnabled = shown || swap.Phase == LoadSwapPhase.ContentOut;
            return;
        }
        AutomationProperties.SetAccessibilityView(element, shown ? AccessibilityView.Content : AccessibilityView.Raw);
    }
}
#endregion
