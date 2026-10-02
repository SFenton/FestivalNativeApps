using System.ComponentModel;
using Festival.App.Services;
using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
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

    /// <summary>Reapplies when the element role changes.</summary>
    /// <param name="d">Element.</param>
    /// <param name="e">Changed role.</param>
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
        element.Opacity = swap.ContentOpacity;
        element.IsHitTestVisible = swap.ContentHitTestVisible;
        AutomationProperties.SetAccessibilityView(element, swap.ContentHitTestVisible ? AccessibilityView.Content : AccessibilityView.Raw);
    }
}
#endregion
