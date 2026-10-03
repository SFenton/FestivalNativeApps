using System.Numerics;
using Festival.Core.Domain;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Hosting;

namespace Festival.App.Controls;

#region Board footer fade
/// <summary>
/// Fades a board's rows out just above its floating footer and hides them beneath it (issue #93, web
/// <c>useScrollMask</c> over a viewport that ends at the footer). Same composition opacity-mask technique as
/// <see cref="TopEdgeFade"/>: a <see cref="CompositionVisualSurface"/> renders <c>source</c>'s visual, a
/// <see cref="CompositionMaskBrush"/> multiplies it by <see cref="BoardFooterEdgeFade.Stops"/> placed at the footer's top,
/// and a sprite on <c>host</c> (a hit-test-invisible sibling over the same cell) paints the result while the source's own
/// visual is hidden. Hit testing, keyboard focus and UI Automation still use the source. Turned off, the source shows
/// directly and the sprite is hidden.
/// </summary>
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
    public BoardFooterFade(FrameworkElement source, UIElement host)
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
}
#endregion
