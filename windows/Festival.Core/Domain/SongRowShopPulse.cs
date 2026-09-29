namespace Festival.Core.Domain;

#region Songs row Shop pulse
/// <summary>
/// The Songs row's Item Shop border pulse (web <c>animations.module.css</c> <c>shopPulse</c>, <c>shopPulseGold</c>,
/// <c>shopPulseRed</c>): a 2 px status-coloured ring over the card whose opacity goes 0 → peak → 0 every 2 s,
/// ease-in-out, forever; with reduced motion it holds at the peak (<c>prefers-reduced-motion</c> rule).
/// </summary>
/// <param name="Argb">Ring colour (ARGB).</param>
/// <param name="PeakOpacity">Opacity at the middle of the cycle, and the static opacity without motion.</param>
public sealed record SongRowShopPulse(uint Argb, float PeakOpacity)
{
    /// <summary>One cycle.</summary>
    public static readonly TimeSpan Cycle = TimeSpan.FromSeconds(2);

    /// <summary>Ring thickness in epx.</summary>
    public const double Thickness = 2;

    /// <summary>Green: in the Shop (<c>--color-status-green</c> <c>#2ECC71</c>, peak 0.7).</summary>
    public static SongRowShopPulse InShop { get; } = new(0xFF2ECC71, 0.7f);

    /// <summary>Gold: new in the Shop (<c>--color-gold</c> <c>#FFD700</c>, peak 0.75).</summary>
    public static SongRowShopPulse New { get; } = new(0xFFFFD700, 0.75f);

    /// <summary>Red: leaving tomorrow (<c>--color-leaving-red</c> <c>#EF4444</c>, peak 0.7).</summary>
    public static SongRowShopPulse Leaving { get; } = new(0xFFEF4444, 0.7f);

    /// <summary>Pulse for a row (Leaving Tomorrow wins over New, New over plain membership).</summary>
    /// <param name="inShop">Highlighted Shop member.</param>
    /// <param name="highlight">Accent.</param>
    /// <returns>Pulse, or <see langword="null"/>.</returns>
    public static SongRowShopPulse? For(bool inShop, ShopHighlight? highlight) => highlight switch
    {
        ShopHighlight.LeavingTomorrow => Leaving,
        ShopHighlight.New => New,
        _ => inShop ? InShop : null,
    };

    /// <summary>Breathe level over one cycle: CSS <c>ease-in-out</c> up to 1 at the midpoint and back to 0.</summary>
    /// <param name="t">Cycle progress, 0…1.</param>
    /// <returns>Level, 0…1.</returns>
    public static float Level(float t)
    {
        t = Math.Clamp(t, 0f, 1f);
        return EaseInOut(t < 0.5f ? t * 2 : (1 - t) * 2);
    }

    /// <summary>CSS <c>ease-in-out</c> (cubic-bezier 0.42, 0, 0.58, 1).</summary>
    /// <param name="x">Progress, 0…1.</param>
    /// <returns>Eased value.</returns>
    public static float EaseInOut(float x)
    {
        // Bisect for the curve parameter whose x matches, then read its y.
        float lo = 0, hi = 1, u = x;
        for (var i = 0; i < 24; i++)
        {
            u = (lo + hi) / 2;
            if (Bezier(u, 0.42f, 0.58f) < x) lo = u; else hi = u;
        }
        return Bezier(u, 0f, 1f);
    }

    /// <summary>One coordinate of a cubic Bezier from 0 to 1.</summary>
    /// <param name="u">Curve parameter.</param>
    /// <param name="p1">First control coordinate.</param>
    /// <param name="p2">Second control coordinate.</param>
    /// <returns>Coordinate.</returns>
    private static float Bezier(float u, float p1, float p2)
    {
        var v = 1 - u;
        return 3 * v * v * u * p1 + 3 * v * u * u * p2 + u * u * u;
    }
}
#endregion
