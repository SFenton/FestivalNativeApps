namespace Festival.Core.Tests;

/// <summary>Pattern <c>leaderboard-row</c> R7 (#307): one selected-row rule for the solo and band song boards.</summary>
public class SelectedRowNavigationTests
{
    [Theory]
    [InlineData(29, false, 2)]
    [InlineData(25, false, 1)]
    [InlineData(26, false, 2)]
    [InlineData(29, true, null)]
    [InlineData(0, false, null)]
    [InlineData(-1, false, null)]
    public void Footer_JumpsOnlyWhenTheRankedRowIsOffThePage(int rank, bool visible, int? page)
    {
        var action = SelectedRowAction.Footer(rank, visible);
        Assert.Equal(page, action.JumpPage);
        Assert.Equal(page is not null, action.Jumps);
    }

    [Fact]
    public void Preview_AppendedRowsJump_InPlaceRowsOpen()
    {
        Assert.Equal(new SelectedRowAction(6), SelectedRowAction.Preview(129, isAppended: true));
        Assert.Equal(new SelectedRowAction(2), SelectedRowAction.Preview(11, isAppended: true, pageSize: 10));
        Assert.False(SelectedRowAction.Preview(3, isAppended: false).Jumps);
    }

    [Fact]
    public void Destination_NamesWhereTheRowGoes()
    {
        Assert.Equal("Jump to your position", new SelectedRowAction(2).Destination(SelectedRowSubject.Player));
        Assert.Equal("Open your statistics", new SelectedRowAction(null).Destination(SelectedRowSubject.Player));
        Assert.Equal("Jump to your band's position", new SelectedRowAction(2).Destination(SelectedRowSubject.Band));
        Assert.Equal("Open band", new SelectedRowAction(null).Destination(SelectedRowSubject.Band));
    }
}
