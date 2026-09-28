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
    /// <param name="stars">Service stars (1–6; anything else is missing or invalid).</param>
    /// <returns>Rating, or <see langword="null"/>.</returns>
    public static StarRating? From(int? stars) => stars switch
    {
        >= 1 and < GoldValue => new StarRating(stars.Value, false),
        GoldValue => new StarRating(MaxDrawn, true),
        _ => null,
    };

    /// <summary>Screen-reader text, e.g. "5 gold stars", "1 star", "4 stars".</summary>
    public string Announcement => Gold ? $"{Count} gold stars" : Count == 1 ? "1 star" : $"{Count} stars";
}
#endregion
