using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>Stat tile side padding: symmetric around centred text, clearing the trailing chevron (#651).</summary>
public sealed class StatTileInsetsTests
{
    [Fact]
    public void LinkedTile_PadsBothSidesPastTheChevron()
    {
        Assert.Equal(28, StatTileInsets.Horizontal(linked: true));
        Assert.True(StatTileInsets.Horizontal(linked: true) - StatTileInsets.ChevronMargin - StatTileInsets.ChevronSize >= StatTileInsets.ChevronGap);
    }

    [Fact]
    public void PlainTile_KeepsItsNarrowerInset() =>
        Assert.Equal(StatTileInsets.PlainInset, StatTileInsets.Horizontal(linked: false));
}
