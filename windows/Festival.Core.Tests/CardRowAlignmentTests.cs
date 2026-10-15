using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>Side-by-side card headers share their title and surface lines (section-headers R14, issue #657).</summary>
public class CardRowAlignmentTests
{
    private static CardHeaderSize? H(double lead, double height) => new CardHeaderSize(lead, height);

    [Fact]
    public void ComboIconRowLowersOnlyItsRowsTitles()
    {
        // Leaderboards at three columns: the combo board (40 epx icon row above a 36 epx title band) leads row one.
        CardHeaderSize?[] headers = [H(40, 76), H(0, 36), H(0, 36), H(0, 36), H(0, 36), H(0, 36)];
        Assert.Equal(
            [new(0, 0), new(40, 0), new(40, 0), new(0, 0), new(0, 0), new(0, 0)],
            CardRowAlignment.Insets(headers, 3));
    }

    [Fact]
    public void SubtitlePadsBelowSoTitlesStayOnOneLine()
    {
        // Song Detail band previews: Duos (title only) beside Trios (title + "No scores recorded yet").
        CardHeaderSize?[] headers = [H(0, 40), H(0, 62)];
        Assert.Equal([new(0, 22), new(0, 0)], CardRowAlignment.Insets(headers, 2));
    }

    [Fact]
    public void ComboBesideSubtitledHeaderPadsBothWays()
    {
        // Titles: the subtitled header drops by the icon row. Surfaces: the combo pads below by the subtitle.
        CardHeaderSize?[] headers = [H(40, 76), H(0, 58)];
        Assert.Equal([new(0, 22), new(40, 0)], CardRowAlignment.Insets(headers, 2));
        // Both subtitled (Leaderboards' entry totals): only the icon row needs space.
        CardHeaderSize?[] bothSubtitled = [H(40, 98), H(0, 58)];
        Assert.Equal([new(0, 0), new(40, 0)], CardRowAlignment.Insets(bothSubtitled, 2));
    }

    [Fact]
    public void CentredShortTitleKeepsItsLineBesideASubtitledTitle()
    {
        // Song Detail band headers have MinHeight 44: "Duos" (28 epx text) is centred 8 epx down; "Trios" with its
        // subtitle fills 62 epx from the top. Trios drops by 8 so the titles meet; Duos pads below so the cards do too.
        CardHeaderSize?[] headers = [H(8, 44), H(0, 62)];
        Assert.Equal([new(0, 26), new(8, 0)], CardRowAlignment.Insets(headers, 2));
    }

    [Fact]
    public void LastPartialRowAlignsWithinItself()
    {
        CardHeaderSize?[] headers = [H(40, 76), H(0, 36), H(0, 36), H(0, 40), H(0, 36)];
        Assert.Equal(
            [new(0, 0), new(40, 0), new(0, 4), new(0, 0), new(0, 0)],
            CardRowAlignment.Insets(headers, 2));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(0)]
    public void OneColumnAlignsNothing(int columns) =>
        Assert.Equal([new(0, 0), new(0, 0)], CardRowAlignment.Insets([H(40, 76), H(0, 36)], columns));

    [Fact]
    public void CardsWithoutHeadersNeitherSetNorTakeTheRowLines()
    {
        CardHeaderSize?[] headers = [null, H(0, 36), H(0, 28)];
        Assert.Equal([new(0, 0), new(0, 0), new(0, 8)], CardRowAlignment.Insets(headers, 3));
    }

    [Fact]
    public void EqualHeadersTakeNoSpace() =>
        Assert.Equal([new(0, 0), new(0, 0)], CardRowAlignment.Insets([H(0, 44), H(0, 44)], 2));

    [Fact]
    public void EmptyGridHasNoInsets() => Assert.Empty(CardRowAlignment.Insets([], 3));
}
