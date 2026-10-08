using System.Numerics;
using Festival.Core.Domain;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
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
        "Vector2(0, Max(0.01, Min(p.R, Min(-s.Translation.Y, Min(" +
        "Max(Max(p.A + s.Translation.Y, -(p.A + s.Translation.Y) - p.H), 0), " +
        "Max(Max(p.B + s.Translation.Y, -(p.B + s.Translation.Y) - p.H), 0))))))";

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
        SetTitles(null, null, 0);
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
