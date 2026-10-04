using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>Star image drawing rules (web <c>MiniStars</c>).</summary>
public sealed class StarRatingTests
{
    [Theory]
    [InlineData(1, 1, false, "1 star", "white-1")]
    [InlineData(2, 2, false, "2 stars", "white-2")]
    [InlineData(4, 4, false, "4 stars", "white-4")]
    [InlineData(5, 5, false, "5 stars", "white-5")]
    [InlineData(6, 5, true, "5 gold stars", "gold-6")]
    public void From_DrawsWhiteOrFiveGold(int stars, int count, bool gold, string announcement, string state)
    {
        var rating = StarRating.From(stars);
        Assert.Equal(new StarRating(count, gold), rating);
        Assert.Equal(announcement, rating!.Value.Announcement);
        Assert.Equal(state, rating.Value.StateName);
        Assert.Equal($"fst.star-rating.{state}", rating.Value.AutomationId);
    }

    /// <summary>Spec "6 (or more)": web <c>MiniStars</c> draws gold for any count of six or more.</summary>
    [Theory]
    [InlineData(7)]
    [InlineData(99)]
    [InlineData(int.MaxValue)]
    public void From_AboveSixIsGold(int stars) => Assert.Equal(new StarRating(5, true), StarRating.From(stars));

    /// <summary>Web call sites guard <c>stars &gt; 0</c>, so the 1-star floor never draws a star for 0.</summary>
    [Theory]
    [InlineData(null)]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(int.MinValue)]
    public void From_MissingOrInvalidDrawsNothing(int? stars) => Assert.Null(StarRating.From(stars));
}
