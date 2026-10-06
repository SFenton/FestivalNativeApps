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
/// Fades a board's rows out just above its floating footer and hides them beneath it (issue #93, web
/// <c>useScrollMask</c> over a viewport that ends at the footer). Same composition opacity-mask technique as
/// <see cref="TopEdgeFade"/>: a <see cref="CompositionVisualSurface"/> renders <c>source</c>'s visual, a
/// <see cref="CompositionMaskBrush"/> multiplies it by <see cref="BoardFooterEdgeFade.Stops"/> (the web's linear 40 epx
/// ramp) placed at the footer's top,
/// and a sprite on <c>host</c> (a hit-test-invisible sibling over the same cell) paints the result while the source's own
/// visual is hidden. Hit testing, keyboard focus and UI Automation still use the source. With reduced transparency the
/// same mask runs at zero strength: a hard cut at the footer's top. Turned off, the source shows directly and the sprite
/// is hidden.
/// </summary>
/// <remarks>
/// The one bottom-chrome edge treatment for every board with a floating footer (song and band song leaderboards, Full
/// Rankings, Band Rankings, a player's bands): pages call <see cref="Attach"/>, never build their own fade or plate. The
/// footer may hold the pinned "your score" row, the pager or both; the fade is the same with or without the pinned row
/// (issue #305).
/// </remarks>
internal sealed class BoardFooterFade
{
    private readonly UIElement source;
    private readonly UIElement host;
    private Visual? sourceVisual;
    private CompositionVisualSurface? surface;
    private SpriteVisual? sprite;
    private CompositionLinearGradientBrush? gradient;
    private CompositionColorGradientStop[] stops = [];
    private bool active;
    private double cut = double.NaN;
    private double strength = double.NaN;

    /// <summary>Creates the fade; composition objects are built on first use.</summary>
    /// <param name="source">Element whose rows fade (its XAML opacity is left alone).</param>
    /// <param name="host">Hit-test-invisible element over the same area that hosts the masked copy.</param>
    private BoardFooterFade(FrameworkElement source, UIElement host)
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

    #region Attach
    /// <summary>
    /// Gives a board its bottom edge: rows fade out above <paramref name="footer"/> while more lie below and are hidden
    /// beneath it. Windows transparency effects off or the in-app Increase Contrast or Less Transparency setting turn the
    /// ramp into a hard cut at the footer's top; under a contrast theme <paramref name="plate"/> (a window-colour border
    /// bottom-aligned in the footer's cell) is sized to the footer and shown instead (scroll-edge R7: rows never show
    /// behind the footer). Follows scrolling, size, visibility and appearance changes while <paramref name="host"/> is
    /// loaded, and publishes the edge state (<see cref="BoardFooterEdgeFade.Status"/>) as the host's ItemStatus.
    /// </summary>
    /// <param name="source">Wrapper around the scrolled rows, in the same cell as the footer. Its own composition visual is
    /// hidden while the fade draws, so it must not carry a load-swap or entrance animation itself.</param>
    /// <param name="host">Raw-view layer over the same cell that paints the faded rows; give it a
    /// <c>fst.&lt;board&gt;.footer-edge</c> AutomationId for UI tests.</param>
    /// <param name="footer">The floating footer (pinned row and/or pager), bottom-aligned in the same cell.</param>
    /// <param name="rows">The scrolling element: a <see cref="ScrollViewer"/>, or a control that scrolls inside its
    /// template (a <see cref="ListView"/>). It hides while the board loads or fails, which turns the edge off.</param>
    /// <param name="plate">Contrast-theme plate behind the footer.</param>
    /// <returns>The fade.</returns>
    public static BoardFooterFade Attach(FrameworkElement source, EdgeFadeLayer host, FrameworkElement footer, FrameworkElement rows,
        FrameworkElement plate)
    {
        var fade = new BoardFooterFade(source, host);
        var binding = new EdgeBinding(fade, source, host, footer, rows, plate);
        // The host is never collapsed, so it loads with the page even while the rows wait for content.
        host.Loaded += (_, _) => binding.Start();
        host.Unloaded += (_, _) => binding.Stop();
        return fade;
    }

    /// <summary>Keeps one board's edge in step with its scroll position, layout and appearance settings.</summary>
    private sealed class EdgeBinding
    {
        private readonly BoardFooterFade fade;
        private readonly FrameworkElement source;
        private readonly EdgeFadeLayer host;
        private readonly FrameworkElement footer;
        private readonly FrameworkElement rows;
        private readonly FrameworkElement plate;
        private readonly Windows.UI.ViewManagement.UISettings uiSettings = new();
        private ScrollViewer? scroller;
        private bool started;

        /// <summary>Wires layout and visibility changes; appearance settings follow <see cref="Start"/>.</summary>
        /// <param name="fade">Fade.</param>
        /// <param name="source">Rows wrapper.</param>
        /// <param name="host">Layer that paints the masked rows and reports the edge state.</param>
        /// <param name="footer">Footer.</param>
        /// <param name="rows">Scrolling element.</param>
        /// <param name="plate">Contrast plate.</param>
        public EdgeBinding(BoardFooterFade fade, FrameworkElement source, EdgeFadeLayer host, FrameworkElement footer, FrameworkElement rows,
            FrameworkElement plate)
        {
            this.fade = fade;
            this.source = source;
            this.host = host;
            this.footer = footer;
            this.rows = rows;
            this.plate = plate;
            footer.SizeChanged += (_, _) => Update();
            source.SizeChanged += (_, _) => Update();
            footer.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Update());
            source.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Update());
            if (!ReferenceEquals(rows, source))
            {
                rows.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Update());
                rows.SizeChanged += (_, _) => Update();
            }
        }

        /// <summary>Starts following appearance changes and the rows' scroller.</summary>
        public void Start()
        {
            if (started) return;
            started = true;
            App.Session.PropertyChanged += OnSettingsChanged;
            uiSettings.AdvancedEffectsEnabledChanged += OnSystemChanged;
            // HighContrastChanged needs a CoreWindow; a contrast-theme switch raises ColorValuesChanged instead.
            uiSettings.ColorValuesChanged += OnSystemChanged;
            FindScroller();
            Update();
        }

        /// <summary>Stops following appearance changes.</summary>
        public void Stop()
        {
            if (!started) return;
            started = false;
            App.Session.PropertyChanged -= OnSettingsChanged;
            uiSettings.AdvancedEffectsEnabledChanged -= OnSystemChanged;
            uiSettings.ColorValuesChanged -= OnSystemChanged;
        }

        /// <summary>
        /// Finds the scroller (a <see cref="ListView"/>'s lives in its template, realized once loaded) and follows its
        /// offset and extent: rows arriving grow the extent without a scroll, and the band must appear then too.
        /// </summary>
        private void FindScroller()
        {
            if (scroller is not null) return;
            scroller = rows as ScrollViewer ?? Descendant(rows);
            if (scroller is null) return;
            scroller.ViewChanged += (_, _) => Update();
            scroller.RegisterPropertyChangedCallback(ScrollViewer.ScrollableHeightProperty, (_, _) => Update());
        }

        /// <summary>First <see cref="ScrollViewer"/> below <paramref name="root"/>, depth first.</summary>
        /// <param name="root">Element to search.</param>
        /// <returns>The scroller, or <see langword="null"/> before the template is applied.</returns>
        private static ScrollViewer? Descendant(DependencyObject root)
        {
            for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            {
                var child = VisualTreeHelper.GetChild(root, i);
                if ((child as ScrollViewer ?? Descendant(child)) is { } found) return found;
            }
            return null;
        }

        /// <summary>Shows the fade, the contrast plate or neither. Runs on scroll, size and setting changes only.</summary>
        private void Update()
        {
            if (!started) return;
            FindScroller();
            var settings = App.Session.Settings;
            var shown = source.Visibility == Visibility.Visible && rows.Visibility == Visibility.Visible &&
                        footer.Visibility == Visibility.Visible && footer.ActualHeight > 0;
            var treatment = BoardFooterEdgeFade.Treatment(shown, ContrastTheme.IsOn, uiSettings.AdvancedEffectsEnabled,
                settings.LessTransparency, settings.MoreContrast);
            plate.Visibility = treatment == BoardFooterTreatment.Plate ? Visibility.Visible : Visibility.Collapsed;
            if (treatment == BoardFooterTreatment.Plate) plate.Height = footer.ActualHeight + footer.Margin.Bottom;
            var masked = treatment is BoardFooterTreatment.Fade or BoardFooterTreatment.Cut;
            double? top = masked ? footer.TransformToVisual(source).TransformPoint(default).Y : null;
            var strength = scroller is null ? 0 : BoardFooterEdgeFade.Strength(scroller.ScrollableHeight, scroller.VerticalOffset);
            fade.Update(top, BoardFooterEdgeFade.MaskStrength(treatment, strength));
            host.SetStatus(BoardFooterEdgeFade.Status(treatment, strength));
        }

        /// <summary>Re-evaluates when the in-app settings change.</summary>
        /// <param name="sender">Session.</param>
        /// <param name="e">Changed property.</param>
        private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == "Settings") source.DispatcherQueue.TryEnqueue(Update);
        }

        /// <summary>Re-evaluates when Windows transparency effects or the contrast theme change (any thread).</summary>
        /// <param name="sender">Settings source.</param>
        /// <param name="args">Ignored.</param>
        private void OnSystemChanged(Windows.UI.ViewManagement.UISettings sender, object args) =>
            source.DispatcherQueue.TryEnqueue(Update);
    }
    #endregion

    #region Drawing
    /// <summary>Shows the fade with the footer's top at <paramref name="footerTop"/>, or turns it off.</summary>
    /// <param name="footerTop">Footer top in the source's coordinates, epx; <see langword="null"/> turns the fade off.</param>
    /// <param name="value">Band strength from <see cref="BoardFooterEdgeFade.Strength"/>.</param>
    public void Update(double? footerTop, double value)
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
        if (top != cut)
        {
            cut = top;
            gradient!.StartPoint = new Vector2(0, (float)(top - BoardFooterEdgeFade.Depth));
            gradient.EndPoint = new Vector2(0, (float)(top + 1));
        }
        value = Math.Clamp(value, 0, 1);
        if (value != strength)
        {
            strength = value;
            var alphas = BoardFooterEdgeFade.Stops(value);
            for (var i = 0; i < stops.Length; i++)
                stops[i].Color = Windows.UI.Color.FromArgb((byte)Math.Round(255 * alphas[i].Alpha), 0, 0, 0);
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
        stops = [.. BoardFooterEdgeFade.Stops(1).Select(s => compositor.CreateColorGradientStop(s.Offset, Microsoft.UI.Colors.Black))];
        foreach (var stop in stops) gradient.ColorStops.Add(stop);
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
