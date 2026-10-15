using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

public sealed class InstrumentChipRowsTests
{
    // Windows Songs chips: 30 epx with 6 epx spacing, so nine take 318 epx on one row.
    private const double Chip = 30, Gap = 6;

    [Fact]
    public void KeepsOneRowWhileEveryChipFits()
    {
        Assert.Equal([9], InstrumentChipRows.Split(9, 318, Chip, Gap));
        Assert.Equal([9], InstrumentChipRows.Split(9, 600, Chip, Gap));
    }

    [Fact]
    public void RoundingShortfallKeepsTheRowWhole()
    {
        // Issue #516: arrange can get a fraction of a pixel less than measure did.
        Assert.Equal([9], InstrumentChipRows.Split(9, 317.4, Chip, Gap));
    }

    [Fact]
    public void BalancesTwoRowsLikeTheWeb()
    {
        // Issue #645: seven fit, but the web splits nine as 5 + 4, not 7 + 2.
        Assert.Equal([5, 4], InstrumentChipRows.Split(9, 250, Chip, Gap));
        Assert.Equal([5, 4], InstrumentChipRows.Split(9, 174, Chip, Gap));
    }

    [Fact]
    public void EarlierRowsTakeTheRemainder()
    {
        Assert.Equal([3, 3, 3], InstrumentChipRows.Split(9, 138, Chip, Gap));
        Assert.Equal([2, 2, 2, 2, 1], InstrumentChipRows.Split(9, 66, Chip, Gap));
        Assert.Equal([4, 3], InstrumentChipRows.Split(7, 138, Chip, Gap));
    }

    [Fact]
    public void NoRowEverExceedsWhatFits()
    {
        for (var width = 1d; width <= 400; width += 0.5)
        {
            var fit = Math.Max(1, (int)Math.Floor((width + Gap + WrapLineLayout.Tolerance) / (Chip + Gap)));
            var rows = InstrumentChipRows.Split(9, width, Chip, Gap);
            Assert.Equal(9, rows.Sum());
            Assert.All(rows, row => Assert.InRange(row, 1, fit));
            Assert.InRange(rows.Max() - rows.Min(), 0, 1);
            Assert.Equal((9 + fit - 1) / fit, rows.Length);
        }
    }

    [Fact]
    public void OneChipPerRowWhenNarrowerThanAChip()
    {
        Assert.Equal([1, 1, 1], InstrumentChipRows.Split(3, 10, Chip, Gap));
    }

    [Fact]
    public void InfiniteWidthAndNoChips()
    {
        Assert.Equal([9], InstrumentChipRows.Split(9, double.PositiveInfinity, Chip, Gap));
        Assert.Empty(InstrumentChipRows.Split(0, 300, Chip, Gap));
    }

    [Fact]
    public void LinesNumberEachChipsRow()
    {
        Assert.Equal([0, 0, 0, 0, 0, 1, 1, 1, 1], InstrumentChipRows.Lines([5, 4]));
        Assert.Empty(InstrumentChipRows.Lines([]));
    }
}
