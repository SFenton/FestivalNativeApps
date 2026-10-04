namespace Festival.Core.Domain;

#region Star rating
/// <summary>
/// How a score's stars are drawn (web <c>MiniStars</c>): 1–5 white star images, or five gold star images for six stars
/// (a gold-star run). The images are bundled (<c>Assets/Stars/star_white.png</c>, <c>star_gold.png</c>, from the web's
/// <c>public/</c>), never glyphs.
/// </summary>
/// <param name="Count">Stars drawn (1–5).</param>
/// <param name="Gold">Whether they are gold (six stars).</param>
public readonly record struct StarRating(int Count, bool Gold)
{
    /// <summary>Gold stars are drawn as this many images.</summary>
    public const int MaxDrawn = 5;

    /// <summary>The service's gold-star value.</summary>
    public const int GoldValue = 6;

    /// <summary>Maps a wire star count to its drawing; <see langword="null"/> when there is nothing to draw.</summary>
    /// <remarks>
    /// Six <em>or more</em> is gold (web <c>MiniStars</c>: <c>starsCount &gt;= 6</c>). Zero, negative and missing counts
    /// draw nothing: every web call site guards <c>stars &gt; 0</c>, and Core uses 0 as its "no stars" sentinel, so the
    /// web's <c>max(1, n)</c> floor only ever applies to 1.
    /// </remarks>
    /// <param name="stars">Service stars (1–5 white, 6 or more gold; anything else is missing).</param>
    /// <returns>Rating, or <see langword="null"/>.</returns>
    public static StarRating? From(int? stars) => stars switch
    {
        >= 1 and < GoldValue => new StarRating(stars.Value, false),
        >= GoldValue => new StarRating(MaxDrawn, true),
        _ => null,
    };

    /// <summary>Screen-reader text, e.g. "5 gold stars", "1 star", "4 stars".</summary>
    public string Announcement => Gold ? $"{Count} gold stars" : Count == 1 ? "1 star" : $"{Count} stars";

    /// <summary>Contract state name (<c>contracts/product.json</c> star-rating): <c>white-1</c>…<c>white-5</c> or <c>gold-6</c>.</summary>
    public string StateName => Gold ? $"gold-{GoldValue}" : $"white-{Count}";

    /// <summary>UI Automation ID under the control's test ID root, e.g. <c>fst.star-rating.gold-6</c>.</summary>
    public string AutomationId => $"fst.star-rating.{StateName}";
}
#endregion
