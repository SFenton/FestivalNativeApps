using System.Numerics;
using Festival.Core.Domain;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Hosting;

namespace Festival.App.Controls;

#region Top edge fade
/// <summary>
/// Fades <c>source</c>'s top edge over <see cref="SongHeaderEdgeFade.Depth"/> epx (the Songs list under its section
/// header bar, issue #49). WinUI 3 has no <c>OpacityMask</c>, so this uses the composition opacity-mask technique (as in
/// the Windows Community Toolkit's <c>OpacityMaskView</c>). A <see cref="CompositionVisualSurface"/> renders the
/// source's visual, a <see cref="CompositionMaskBrush"/> multiplies it by an eased linear gradient, and a sprite on
/// <c>host</c> (a hit-test-invisible sibling over the same cell) paints the result while the source's own visual is
/// hidden. Composition opacity is not XAML opacity, so hit testing, keyboard focus and the UI Automation tree still
/// use the source unchanged. With the fade off, the source shows directly and the sprite is hidden.
/// </summary>
internal sealed class TopEdgeFade
{
    private readonly UIElement source;
    private readonly UIElement host;
    private Visual? sourceVisual;
    private CompositionVisualSurface? surface;
    private SpriteVisual? sprite;
    private CompositionColorGradientStop[] stops = [];
    private double strength;

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
    public bool IsActive => strength > 0;

    /// <summary>Shows the fade at <paramref name="value"/> strength (0 = the plain hard edge).</summary>
    /// <param name="value">Strength in [0, 1].</param>
    public void Update(double value)
    {
        value = Math.Clamp(value, 0, 1);
        if (value == strength) return;
        strength = value;
        if (value <= 0)
        {
            if (sprite is null) return;
            sprite.IsVisible = false;
            sourceVisual!.Opacity = 1;
            return;
        }
        Build();
        for (var i = 0; i < stops.Length; i++)
            stops[i].Color = Windows.UI.Color.FromArgb((byte)Math.Round(255 * SongHeaderEdgeFade.MaskAlpha(SongHeaderEdgeFade.Stops[i].Alpha, value)), 0, 0, 0);
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
        var gradient = compositor.CreateLinearGradientBrush();
        gradient.MappingMode = CompositionMappingMode.Absolute;
        gradient.StartPoint = Vector2.Zero;
        gradient.EndPoint = new Vector2(0, (float)SongHeaderEdgeFade.Depth);
        gradient.ExtendMode = CompositionGradientExtendMode.Clamp;
        stops = [.. SongHeaderEdgeFade.Stops.Select(s => compositor.CreateColorGradientStop(s.Offset, Microsoft.UI.Colors.Black))];
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
