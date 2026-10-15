using System.ComponentModel;
using System.Numerics;
using Festival.App.Services;
using Festival.Core.Domain;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;

namespace Festival.App.Controls;

#region Top edge fade
/// <summary>
/// The pinned-section-title row fade (scroll-edge R2–R5; issues #49, #308): rows are clear at <c>source</c>'s top edge and
/// opaque <see cref="SongHeaderEdgeFade.FadeDepth"/> epx below it, linear. WinUI 3 has no <c>OpacityMask</c>, so this
/// uses the composition opacity-mask technique (as in the Windows Community Toolkit's <c>OpacityMaskView</c>). A
/// <see cref="CompositionVisualSurface"/> renders the source's visual, a <see cref="CompositionMaskBrush"/> multiplies it
/// by a linear gradient, and a sprite on <c>host</c> (a hit-test-invisible sibling over the same cell) paints the result
/// while the source's own visual is hidden. Composition opacity is not XAML opacity, so hit testing, keyboard focus and
/// the UI Automation tree still use the source unchanged. The gradient's end (the ramp's depth) is an expression over
/// the scroll viewer's manipulation property set, so it follows the rows in the same frame; <see cref="SetTitles"/>
/// supplies the section titles it is cut to. Off, the source shows directly and the sprite is hidden (the hard edge).
/// </summary>
internal sealed class TopEdgeFade
{
    /// <summary>
    /// <see cref="SongHeaderEdgeFade.FadeDepth"/> on the compositor. Live scroll offset o = -s.Translation.Y and live
    /// title tops A + s.Translation.Y / B + s.Translation.Y (A, B: content tops). The floor keeps the gradient non-degenerate.
    /// </summary>
    private const string DepthExpression =
        "Vector2(0, p.E + Max(0.01, Min(p.R, Min(-s.Translation.Y, Min(" +
        "Max(Max(p.A + s.Translation.Y, -(p.A + s.Translation.Y) - p.H), 0), " +
        "Max(Max(p.B + s.Translation.Y, -(p.B + s.Translation.Y) - p.H), 0))))))";

    /// <summary>The clear edge, <c>p.E</c> below the source's top; the clamped gradient hides everything above it.</summary>
    private const string EdgeExpression = "Vector2(0, p.E)";

    private readonly UIElement source;
    private readonly UIElement host;
    private Visual? sourceVisual;
    private CompositionVisualSurface? surface;
    private SpriteVisual? sprite;
    private CompositionPropertySet? props;
    private CompositionPropertySet? scroll;
    private bool active;

    /// <summary>Creates the fade; composition objects are built on first use.</summary>
    /// <param name="source">Element whose top edge fades (its XAML opacity is left alone).</param>
    /// <param name="host">Hit-test-invisible element over the same area that hosts the masked copy.</param>
    public TopEdgeFade(FrameworkElement source, UIElement host)
    {
        this.source = source;
        this.host = host;
        source.SizeChanged += (_, e) =>
        {
            if (surface is not null) surface.SourceSize = new Vector2((float)e.NewSize.Width, (float)e.NewSize.Height);
        };
    }

    /// <summary>Whether the fade is currently drawn.</summary>
    public bool IsActive => active;

    /// <summary>Ties the ramp's depth to a scroll viewer's manipulation property set (call once it exists).</summary>
    /// <param name="scrollSet">The list's <c>ElementCompositionPreview.GetScrollViewerManipulationPropertySet</c>.</param>
    public void Track(CompositionPropertySet scrollSet)
    {
        scroll = scrollSet;
        props = scrollSet.Compositor.CreatePropertySet();
        props.InsertScalar("R", (float)SongHeaderEdgeFade.Depth);
        props.InsertScalar("E", 0);
        SetTitles(null, null, 0);
    }

    /// <summary>
    /// Moves the clear edge below the source's top, for chrome that overlays the scroller (Song Details' pinned bar,
    /// issue #640): content above <paramref name="edgeTop"/> is hidden, and the ramp starts there. A hard edge keeps the
    /// cut at <paramref name="edgeTop"/> with no ramp (scroll-edge R7), so nothing shows behind the chrome in any mode.
    /// </summary>
    /// <param name="edgeTop">Chrome bottom in the source's coordinates, epx (0 = the source's top).</param>
    /// <param name="hardEdge">Whether to cut without a ramp.</param>
    public void SetEdge(double edgeTop, bool hardEdge)
    {
        if (props is null) return;
        props.InsertScalar("E", (float)Math.Max(0, edgeTop));
        props.InsertScalar("R", hardEdge ? 0f : (float)SongHeaderEdgeFade.Depth);
    }

    /// <summary>
    /// Sets the section titles the ramp is cut to (<see cref="SongHeaderEdgeFade.TitleLimit"/>), as content tops
    /// (viewport-relative top plus the scroll offset) so the compositor can follow them between view changes.
    /// </summary>
    /// <param name="ownContentTop">The first visible row's section title, or <see langword="null"/>.</param>
    /// <param name="nextContentTop">The following section's title, or <see langword="null"/>.</param>
    /// <param name="barHeight">The pinned bar's height.</param>
    public void SetTitles(double? ownContentTop, double? nextContentTop, double barHeight)
    {
        if (props is null) return;
        props.InsertScalar("A", (float)(ownContentTop ?? SongHeaderEdgeFade.FarTitle));
        props.InsertScalar("B", (float)(nextContentTop ?? SongHeaderEdgeFade.FarTitle));
        props.InsertScalar("H", (float)Math.Max(0, barHeight));
    }

    /// <summary>Shows the ramp, or the plain hard edge.</summary>
    /// <param name="on">Whether to draw the ramp.</param>
    public void Update(bool on)
    {
        if (on && (scroll is null || props is null)) on = false;
        if (on == active) return;
        active = on;
        if (!on)
        {
            if (sprite is null) return;
            sprite.IsVisible = false;
            sourceVisual!.Opacity = 1;
            return;
        }
        Build();
        sprite!.IsVisible = true;
        sourceVisual!.Opacity = 0;
    }

    /// <summary>Builds the surface, mask, depth expression and sprite once.</summary>
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
        var gradient = compositor.CreateLinearGradientBrush();
        gradient.MappingMode = CompositionMappingMode.Absolute;
        gradient.StartPoint = Vector2.Zero;
        gradient.EndPoint = new Vector2(0, (float)SongHeaderEdgeFade.Depth);
        gradient.ExtendMode = CompositionGradientExtendMode.Clamp;
        foreach (var (offset, alpha) in SongHeaderEdgeFade.Stops)
            gradient.ColorStops.Add(compositor.CreateColorGradientStop(offset, Windows.UI.Color.FromArgb((byte)Math.Round(255 * alpha), 0, 0, 0)));
        var depth = compositor.CreateExpressionAnimation(DepthExpression);
        depth.SetReferenceParameter("s", scroll!);
        depth.SetReferenceParameter("p", props!);
        gradient.StartAnimation(nameof(gradient.EndPoint), depth);
        var edge = compositor.CreateExpressionAnimation(EdgeExpression);
        edge.SetReferenceParameter("p", props!);
        gradient.StartAnimation(nameof(gradient.StartPoint), edge);
        var mask = compositor.CreateMaskBrush();
        mask.Source = content;
        mask.Mask = gradient;
        sprite = compositor.CreateSpriteVisual();
        sprite.RelativeSizeAdjustment = Vector2.One;
        sprite.Brush = mask;
        ElementCompositionPreview.SetElementChildVisual(host, sprite);
    }
}
#endregion

#region Overlay header fade
/// <summary>
/// Content fading under page chrome that overlays the page scroller rather than sitting in a row above it: Song Details'
/// pinned compact bar (scroll-edge R2, R3, R7; issue #640). While the chrome shows, the scroller's content is hidden down
/// to the chrome's bottom and ramps in over 40 epx below it (<see cref="TopEdgeFade"/> with <see cref="TopEdgeFade.SetEdge"/>),
/// so the chrome needs no fill and the page's backdrop art stays visible behind it. A contrast theme, Windows
/// transparency effects off, or in-app Less Transparency / Increase Contrast keep the cut with no ramp, so content never
/// shows behind the chrome. Pages call <see cref="Attach"/> once; it follows scrolling, the chrome's visibility and size,
/// and the appearance settings, and publishes <see cref="SongHeaderEdgeFade.OverlayEdge"/>'s status on the host.
/// </summary>
internal sealed class OverlayHeaderFade
{
    private readonly FrameworkElement source;
    private readonly EdgeFadeLayer host;
    private readonly ScrollViewer scroller;
    private readonly FrameworkElement chrome;
    private readonly TopEdgeFade fade;
    private readonly Windows.UI.ViewManagement.UISettings uiSettings = new();
    private bool following;
    private bool tracking;

    /// <summary>Creates the fade; it follows the page while <paramref name="source"/> is loaded.</summary>
    /// <param name="source">Wrapper around the scroller (never the scroller itself: the fade hides this visual).</param>
    /// <param name="host">Fade layer over the same cell that paints the masked copy.</param>
    /// <param name="scroller">The page scroller.</param>
    /// <param name="chrome">The chrome pinned over the scroller's top.</param>
    private OverlayHeaderFade(FrameworkElement source, EdgeFadeLayer host, ScrollViewer scroller, FrameworkElement chrome)
    {
        (this.source, this.host, this.scroller, this.chrome) = (source, host, scroller, chrome);
        fade = new TopEdgeFade(source, host);
        scroller.ViewChanged += (_, _) => Update();
        chrome.SizeChanged += (_, _) => Update();
        chrome.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Update());
        scroller.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Update());
        source.Loaded += (_, _) => Follow(true);
        source.Unloaded += (_, _) => Follow(false);
    }

    /// <summary>Fades a page's content under chrome that overlays its scroller.</summary>
    /// <param name="source">Wrapper around the scroller.</param>
    /// <param name="host">Fade layer over the same cell (give it a <c>….edge-fade</c> AutomationId).</param>
    /// <param name="scroller">The page scroller.</param>
    /// <param name="chrome">The overlaying chrome.</param>
    /// <returns>The fade.</returns>
    public static OverlayHeaderFade Attach(FrameworkElement source, EdgeFadeLayer host, ScrollViewer scroller, FrameworkElement chrome) =>
        new(source, host, scroller, chrome);

    /// <summary>Whether the mask is currently drawn.</summary>
    public bool IsActive => fade.IsActive;

    /// <summary>Starts or stops following the appearance settings while the page is in the tree.</summary>
    /// <param name="on">Whether the page is loaded.</param>
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
            Update();
            return;
        }
        App.Session.PropertyChanged -= OnSessionChanged;
        uiSettings.AdvancedEffectsEnabledChanged -= OnSystemChanged;
        uiSettings.ColorValuesChanged -= OnSystemChanged;
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

    /// <summary>Places (or removes) the clear edge for the chrome and settings, then publishes the state.</summary>
    private void Update()
    {
        if (!following) return;
        if (!tracking)
        {
            fade.Track(ElementCompositionPreview.GetScrollViewerManipulationPropertySet(scroller));
            tracking = true;
        }
        var settings = App.Session.Settings;
        var enabled = SongHeaderEdgeFade.IsEnabled(ContrastTheme.IsOn, uiSettings.AdvancedEffectsEnabled,
            settings.LessTransparency, settings.MoreContrast);
        var shown = chrome.Visibility == Visibility.Visible && scroller.Visibility == Visibility.Visible && chrome.ActualHeight > 0;
        var bottom = shown ? chrome.TransformToVisual(source).TransformPoint(default).Y + chrome.ActualHeight : 0;
        var (masked, edge, hard, status) = SongHeaderEdgeFade.OverlayEdge(shown, bottom, enabled, scroller.VerticalOffset);
        fade.SetEdge(edge, hard);
        fade.Update(masked);
        host.SetStatus(status);
    }
}
#endregion

#region Auto-scroll edge fade
/// <summary>
/// The first-run infinite-scroll demo's top and bottom fades (web <c>InfiniteScrollDemo</c> <c>updateMask</c>; scroll-edge
/// pattern): the scroller's content is clear at each edge and opaque <see cref="FirstRunAutoScroll.Fades"/> epx in, with
/// no ramp at the end it rests against. Same composition opacity-mask technique as <see cref="TopEdgeFade"/>; with the
/// fade disabled (<see cref="SongHeaderEdgeFade.IsEnabled"/>: contrast themes, transparency effects off, Less
/// Transparency, Increase Contrast) the scroller shows directly with hard edges.
/// </summary>
internal sealed class AutoScrollEdgeFade
{
    private readonly FrameworkElement source;
    private readonly UIElement host;
    private Visual? sourceVisual;
    private CompositionVisualSurface? surface;
    private SpriteVisual? sprite;
    private CompositionColorGradientStop[] stops = [];
    private bool active;

    /// <summary>Creates the fade; composition objects are built on first use.</summary>
    /// <param name="source">The scroller whose edges fade (its XAML opacity is left alone).</param>
    /// <param name="host">Hit-test-invisible element over the same area that hosts the masked copy.</param>
    public AutoScrollEdgeFade(FrameworkElement source, UIElement host)
    {
        this.source = source;
        this.host = host;
        source.SizeChanged += (_, e) =>
        {
            if (surface is not null) surface.SourceSize = new Vector2((float)e.NewSize.Width, (float)e.NewSize.Height);
        };
    }

    /// <summary>Whether the ramps are currently drawn.</summary>
    public bool IsActive => active;

    /// <summary>Whether the drawn mask fades the top edge (content lies above).</summary>
    public bool TopFaded { get; private set; }

    /// <summary>Whether the drawn mask fades the bottom edge (content lies below).</summary>
    public bool BottomFaded { get; private set; }

    /// <summary>Draws the ramps for a scroll position, or the plain hard edges.</summary>
    /// <param name="on">Whether fades are enabled (<see cref="SongHeaderEdgeFade.IsEnabled"/>).</param>
    /// <param name="offset">Scroll offset.</param>
    /// <param name="range">Scroll range.</param>
    public void Update(bool on, double offset, double range)
    {
        var height = source.ActualHeight;
        if (on && height <= 0) on = false;
        if (!on)
        {
            if (!active) return;
            active = false;
            sprite!.IsVisible = false;
            sourceVisual!.Opacity = 1;
            return;
        }
        Build();
        var (top, bottom) = FirstRunAutoScroll.Fades(offset, range);
        stops[1].Offset = (float)Math.Clamp(top / height, 0.001, 0.5);
        stops[2].Offset = (float)Math.Clamp(1 - bottom / height, 0.5, 0.999);
        stops[0].Color = Windows.UI.Color.FromArgb(top > 0 ? (byte)0 : (byte)255, 0, 0, 0);
        stops[3].Color = Windows.UI.Color.FromArgb(bottom > 0 ? (byte)0 : (byte)255, 0, 0, 0);
        TopFaded = top > 0;
        BottomFaded = bottom > 0;
        if (active) return;
        active = true;
        sprite!.IsVisible = true;
        sourceVisual!.Opacity = 0;
    }

    /// <summary>Builds the surface, the four-stop mask and the sprite once.</summary>
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
        var gradient = compositor.CreateLinearGradientBrush();
        gradient.StartPoint = Vector2.Zero;
        gradient.EndPoint = new Vector2(0, 1);
        gradient.ExtendMode = CompositionGradientExtendMode.Clamp;
        stops =
        [
            compositor.CreateColorGradientStop(0, Windows.UI.Color.FromArgb(0, 0, 0, 0)),
            compositor.CreateColorGradientStop(0.1f, Windows.UI.Color.FromArgb(255, 0, 0, 0)),
            compositor.CreateColorGradientStop(0.9f, Windows.UI.Color.FromArgb(255, 0, 0, 0)),
            compositor.CreateColorGradientStop(1, Windows.UI.Color.FromArgb(0, 0, 0, 0)),
        ];
        foreach (var stop in stops) gradient.ColorStops.Add(stop);
        var mask = compositor.CreateMaskBrush();
        mask.Source = content;
        mask.Mask = gradient;
        sprite = compositor.CreateSpriteVisual();
        sprite.RelativeSizeAdjustment = Vector2.One;
        sprite.Brush = mask;
        ElementCompositionPreview.SetElementChildVisual(host, sprite);
    }
}
#endregion
