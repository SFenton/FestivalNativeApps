using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>Suggestions row lines: metadata stacks only on narrow rows with wide metadata, and only then is there a line gap (#654).</summary>
public sealed class SuggestionRowMetricsTests
{
    [Theory]
    [InlineData(SuggestionRowLayout.InstrumentChips)]
    [InlineData(SuggestionRowLayout.Rival)]
    public void NarrowRowWithWideMetadata_StacksIt(SuggestionRowLayout layout)
    {
        Assert.True(SuggestionRowMetrics.StacksMetadata(layout, SuggestionRowMetrics.NarrowWidth - 1, hasMetadata: true));
        Assert.False(SuggestionRowMetrics.StacksMetadata(layout, SuggestionRowMetrics.NarrowWidth, hasMetadata: true));
    }

    [Theory]
    [InlineData(SuggestionRowLayout.SingleInstrument)]
    [InlineData(SuggestionRowLayout.Percentile)]
    [InlineData(SuggestionRowLayout.Season)]
    [InlineData(SuggestionRowLayout.UnfcAccuracy)]
    [InlineData(SuggestionRowLayout.Hidden)]
    public void CompactMetadata_StaysOnTheTitleLine(SuggestionRowLayout layout) =>
        Assert.False(SuggestionRowMetrics.StacksMetadata(layout, 200, hasMetadata: true));

    [Fact]
    public void NothingToStack_StaysOneLine()
    {
        Assert.False(SuggestionRowMetrics.StacksMetadata(SuggestionRowLayout.Rival, 200, hasMetadata: false));
        Assert.False(SuggestionRowMetrics.StacksMetadata(SuggestionRowLayout.InstrumentChips, 0, hasMetadata: true));
        Assert.False(SuggestionRowMetrics.StacksMetadata(null, 200, hasMetadata: true));
    }

    [Fact]
    public void OneLineRow_HasNoLineGap_SoItsContentIsCentred()
    {
        Assert.Equal(0, SuggestionRowMetrics.RowSpacing(stacked: false));
        Assert.Equal(SuggestionRowMetrics.LineSpacing, SuggestionRowMetrics.RowSpacing(stacked: true));
    }
}
