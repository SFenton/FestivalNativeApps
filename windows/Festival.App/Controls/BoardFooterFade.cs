using System.ComponentModel;
using System.Numerics;
using Festival.App.Services;
using Festival.Core.Domain;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Board footer fade
/// <summary>
/// The one bottom-chrome ramp for every board with a floating footer (scroll-edge R1–R4, R7; issues #93, #308, web
/// <c>useScrollFade</c>): rows are clear at the footer's top, opaque <see cref="BoardFooterEdgeFade.FadeDepth"/> epx above
/// it, and hidden beneath it; depth 0 is the end of the list (nothing dimmed) or, under a contrast theme, Windows
/// transparency effects off, or in-app Increase Contrast / Less Transparency, the accessibility hard cut at the footer's
/// top. Pages call <see cref="Attach"/> once; it follows scrolling, sizes, visibility and the appearance settings itself.
/// </summary>
/// <remarks>
/// WinUI 3 has no <c>UIElement.OpacityMask</c>, so this is the composition opacity-mask technique shared with
/// <see cref="TopEdgeFade"/>: a <see cref="CompositionVisualSurface"/> renders <c>source</c>'s visual, a
/// <see cref="CompositionMaskBrush"/> multiplies it by <see cref="BoardFooterEdgeFade.Stops"/> placed above the footer's
/// top, and a sprite on the <see cref="EdgeFadeLayer"/> host (a hit-test-invisible sibling over the same cell) paints the
/// result while the source's own visual is hidden. Hit testing, keyboard focus and UI Automation still use the source.
/// The host publishes the drawn state (<see cref="BoardFooterEdgeFade.Status"/>) in the UIA raw view for UI tests.
/// </remarks>
internal sealed class BoardFooterFade
{
    private readonly FrameworkElement source;
    private readonly EdgeFadeLayer host;
    private readonly FrameworkElement list;
    private readonly FrameworkElement footer;
    private readonly FrameworkElement? plate;
    private readonly Windows.UI.ViewManagement.UISettings uiSettings = new();
    private ScrollViewer? scroller;
    private bool following;
    private Visual? sourceVisual;
    private CompositionVisualSurface? surface;
    private SpriteVisual? sprite;
    private CompositionLinearGradientBrush? gradient;
    private bool active;
    private double cut = double.NaN;
    private double depth = double.NaN;

    /// <summary>Creates the fade; composition objects are built on first use.</summary>
    /// <param name="source">Wrapper whose rows fade (never the load-swap element itself: the fade hides this visual).</param>
    /// <param name="host">Fade layer over the same cell that paints the masked copy.</param>
    /// <param name="list">The scrolled list: a <see cref="ScrollViewer"/> or a control holding one (a <see cref="ListView"/>); while it is collapsed nothing is masked.</param>
    /// <param name="footer">The floating footer (pinned row and/or pager), bottom-aligned over the rows.</param>
    /// <param name="plate">Optional window-colour plate that backs the footer under a contrast theme (issues #197, #208, #209).</param>
    private BoardFooterFade(FrameworkElement source, EdgeFadeLayer host, FrameworkElement list, FrameworkElement footer, FrameworkElement? plate)
    {
        (this.source, this.host, this.list, this.footer, this.plate) = (source, host, list, footer, plate);
        source.SizeChanged += (_, e) =>
        {
            if (surface is not null) surface.SourceSize = new Vector2((float)e.NewSize.Width, (float)e.NewSize.Height);
            Update();
        };
        footer.SizeChanged += (_, _) => Update();
        footer.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Update());
        list.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Update());
        source.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Update());
        source.Loaded += (_, _) => Follow(true);
        source.Unloaded += (_, _) => Follow(false);
    }

    /// <summary>Gives a board the bottom-chrome ramp above its floating footer.</summary>
    /// <param name="source">Wrapper whose rows fade (never the load-swap element itself: the fade hides this visual).</param>
    /// <param name="host">Fade layer over the same cell that paints the masked copy (give it a <c>….footer-fade</c> AutomationId).</param>
    /// <param name="list">The scrolled list: a <see cref="ScrollViewer"/> or a control holding one (a <see cref="ListView"/>).</param>
    /// <param name="footer">The floating footer.</param>
    /// <param name="plate">Optional contrast-theme plate behind the footer.</param>
    /// <returns>The fade.</returns>
    public static BoardFooterFade Attach(FrameworkElement source, EdgeFadeLayer host, FrameworkElement list, FrameworkElement footer,
                                         FrameworkElement? plate = null) =>
        new(source, host, list, footer, plate);

    /// <summary>Whether the mask is currently drawn.</summary>
    public bool IsActive => active;

    #region Following
    /// <summary>Starts or stops following scrolling and the appearance settings while the board is in the tree.</summary>
    /// <param name="on">Whether the board is loaded.</param>
    private void Follow(bool on)
    {
        if (on == following) return;
        following = on;
        if (on)
        {
            App.Session.PropertyChanged += OnSessionChanged;
            uiSettings.AdvancedEffectsEnabledChanged += OnSystemChanged;
            // HighContrastChanged needs a CoreWindow; a contrast-theme switch raises ColorValuesChanged instead.
            uiSettings.ColorValuesChanged += OnSystemChanged;
            EnsureScroller();
            Update();
            return;
        }
        App.Session.PropertyChanged -= OnSessionChanged;
        uiSettings.AdvancedEffectsEnabledChanged -= OnSystemChanged;
        uiSettings.ColorValuesChanged -= OnSystemChanged;
    }

    /// <summary>Finds the list's scroll viewer once (a ListView's lives in its template) and follows its scrolling.</summary>
    /// <returns>The scroll viewer, or <see langword="null"/> before the template is applied.</returns>
    private ScrollViewer? EnsureScroller()
    {
        if (scroller is null && (scroller = FindScrollViewer(list)) is not null)
        {
            scroller.ViewChanged += (_, _) => Update();
            // Rows arriving (or a page swap) change the extent without a scroll; a board that loads long shows the
            // ramp at once, with or without the selected player's pinned row (issue #305).
            scroller.RegisterPropertyChangedCallback(ScrollViewer.ScrollableHeightProperty, (_, _) => Update());
        }
        return scroller;
    }

    /// <summary>Depth-first search for the first scroll viewer at or under <paramref name="root"/>.</summary>
    /// <param name="root">Search root.</param>
    /// <returns>The scroll viewer, or <see langword="null"/>.</returns>
    private static ScrollViewer? FindScrollViewer(DependencyObject root)
    {
        if (root is ScrollViewer viewer) return viewer;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            if (FindScrollViewer(VisualTreeHelper.GetChild(root, i)) is { } nested) return nested;
        return null;
    }

    /// <summary>Re-evaluates when the in-app settings change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == "Settings") source.DispatcherQueue.TryEnqueue(Update);
    }

    /// <summary>Re-evaluates when Windows transparency effects or the contrast theme change (any thread).</summary>
    /// <param name="sender">Settings source.</param>
    /// <param name="args">Ignored.</param>
    private void OnSystemChanged(Windows.UI.ViewManagement.UISettings sender, object args) => source.DispatcherQueue.TryEnqueue(Update);
    #endregion

    #region Drawing
    /// <summary>Places (or removes) the ramp for the current scroll position, footer and settings, then publishes the state.</summary>
    private void Update()
    {
        if (!following) return;
        var settings = App.Session.Settings;
        var contrast = ContrastTheme.IsOn;
        var shown = source.Visibility == Visibility.Visible && list.Visibility == Visibility.Visible &&
                    footer.Visibility == Visibility.Visible && footer.ActualHeight > 0;
        if (plate is not null)
        {
            plate.Visibility = contrast && shown ? Visibility.Visible : Visibility.Collapsed;
            if (contrast && shown) plate.Height = footer.ActualHeight + footer.Margin.Bottom;
        }
        var enabled = SongHeaderEdgeFade.IsEnabled(contrast, uiSettings.AdvancedEffectsEnabled, settings.LessTransparency, settings.MoreContrast);
        double? top = shown ? footer.TransformToVisual(source).TransformPoint(default).Y : null;
        var viewer = EnsureScroller();
        Apply(top, viewer is null ? 0 : BoardFooterEdgeFade.FadeDepth(viewer.ScrollableHeight, viewer.VerticalOffset, enabled));
        var drawn = active && gradient is not null ? gradient.EndPoint.Y - gradient.StartPoint.Y : 0;
        host.SetStatus(BoardFooterEdgeFade.Status(active, enabled, drawn));
    }

    /// <summary>Draws the mask with the footer's top at <paramref name="footerTop"/>, or turns it off.</summary>
    /// <param name="footerTop">Footer top in the source's coordinates, epx; <see langword="null"/> turns the mask off.</param>
    /// <param name="value">Ramp depth from <see cref="BoardFooterEdgeFade.FadeDepth"/> (0 = cut at the footer's top).</param>
    private void Apply(double? footerTop, double value)
    {
        if (footerTop is not { } top)
        {
            if (!active) return;
            active = false;
            sprite!.IsVisible = false;
            sourceVisual!.Opacity = 1;
            return;
        }
        Build();
        value = Math.Clamp(value, 0, BoardFooterEdgeFade.Depth);
        if (top != cut || value != depth)
        {
            (cut, depth) = (top, value);
            // A sub-pixel floor keeps the gradient non-degenerate: depth 0 is a hard cut at the footer's top.
            gradient!.StartPoint = new Vector2(0, (float)(top - Math.Max(value, 0.01)));
            gradient.EndPoint = new Vector2(0, (float)top);
        }
        if (active) return;
        active = true;
        sprite!.IsVisible = true;
        sourceVisual!.Opacity = 0;
    }

    /// <summary>Builds the surface, mask and sprite once.</summary>
    private void Build()
    {
        if (sprite is not null) return;
        sourceVisual = ElementCompositionPreview.GetElementVisual(source);
        var compositor = sourceVisual.Compositor;
        surface = compositor.CreateVisualSurface();
        surface.SourceVisual = sourceVisual;
        surface.SourceSize = source.ActualSize;
        var content = compositor.CreateSurfaceBrush(surface);
        content.Stretch = CompositionStretch.None;
        content.HorizontalAlignmentRatio = 0;
        content.VerticalAlignmentRatio = 0;
        gradient = compositor.CreateLinearGradientBrush();
        gradient.MappingMode = CompositionMappingMode.Absolute;
        gradient.ExtendMode = CompositionGradientExtendMode.Clamp;
        foreach (var (offset, alpha) in BoardFooterEdgeFade.Stops)
            gradient.ColorStops.Add(compositor.CreateColorGradientStop(offset, Windows.UI.Color.FromArgb((byte)Math.Round(255 * alpha), 0, 0, 0)));
        var mask = compositor.CreateMaskBrush();
        mask.Source = content;
        mask.Mask = gradient;
        sprite = compositor.CreateSpriteVisual();
        sprite.RelativeSizeAdjustment = Vector2.One;
        sprite.Brush = mask;
        sprite.IsVisible = false;
        ElementCompositionPreview.SetElementChildVisual(host, sprite);
    }
    #endregion
}
#endregion
