namespace Festival.Core.Domain;

#region Card surface opacity
/// <summary>
/// The shared card surface's translucency (<c>FSTCardSurfaceBrush</c>, surface-materials R4; issue #397). Cards are
/// translucent over the page artwork only while Windows transparency effects are on and neither the in-app Less
/// Transparency nor Increase Contrast setting is: either accessibility setting makes them opaque, like Apple's
/// <c>FestivalCardModifier</c> and Android's <c>GlassCard</c>. Windows contrast themes use their own system-colour
/// dictionary and are opaque already.
/// </summary>
public static class CardSurfaceOpacity
{
    /// <summary>Card fill alpha over the artwork (web <c>frostedCard</c>, about 78%).</summary>
    public const byte TranslucentAlpha = 0xC7;

    /// <summary>Card fill alpha when translucency is off.</summary>
    public const byte OpaqueAlpha = 0xFF;

    /// <summary>Whether cards (and the overlay pane's acrylic) may stay translucent.</summary>
    /// <param name="transparencyEffects">Windows transparency effects are on.</param>
    /// <param name="lessTransparency">The in-app Less Transparency setting is on.</param>
    /// <param name="moreContrast">The in-app Increase Contrast setting is on.</param>
    /// <returns><see langword="true"/> only when no setting asks for an opaque surface.</returns>
    public static bool IsTranslucent(bool transparencyEffects, bool lessTransparency, bool moreContrast) =>
        transparencyEffects && !lessTransparency && !moreContrast;

    /// <summary>The card fill alpha for the current settings.</summary>
    /// <param name="transparencyEffects">Windows transparency effects are on.</param>
    /// <param name="lessTransparency">The in-app Less Transparency setting is on.</param>
    /// <param name="moreContrast">The in-app Increase Contrast setting is on.</param>
    /// <returns><see cref="TranslucentAlpha"/> or <see cref="OpaqueAlpha"/>.</returns>
    public static byte Alpha(bool transparencyEffects, bool lessTransparency, bool moreContrast) =>
        IsTranslucent(transparencyEffects, lessTransparency, moreContrast) ? TranslucentAlpha : OpaqueAlpha;
}
#endregion
