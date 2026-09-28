using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>Star image drawing rules (web <c>MiniStars</c>).</summary>
public sealed class StarRatingTests
{
    [Theory]
    [InlineData(1, 1, false, "1 star")]
    [InlineData(4, 4, false, "4 stars")]
    [InlineData(5, 5, false, "5 stars")]
    [InlineData(6, 5, true, "5 gold stars")]
    public void From_DrawsWhiteOrFiveGold(int stars, int count, bool gold, string announcement)
    {
        var rating = StarRating.From(stars);
        Assert.Equal(new StarRating(count, gold), rating);
        Assert.Equal(announcement, rating!.Value.Announcement);
    }

    [Theory]
    [InlineData(null)]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(7)]
    public void From_MissingOrInvalidDrawsNothing(int? stars) => Assert.Null(StarRating.From(stars));
}
