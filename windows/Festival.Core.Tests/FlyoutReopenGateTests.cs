using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>A show request while the same flyout is closing opens it once it has closed (issue #684).</summary>
public class FlyoutReopenGateTests
{
    [Fact]
    public void ShowsAtOnceWhenNeverShownOrAlreadyOpen()
    {
        var gate = new FlyoutReopenGate();
        Assert.False(gate.IsClosing(isOpen: false));
        Assert.True(gate.RequestShow(isOpen: false));
        gate.Opened();
        // Open: WinUI ignores the repeat itself, so nothing is kept for later.
        Assert.True(gate.RequestShow(isOpen: true));
        Assert.False(gate.Closed());
    }

    [Fact]
    public void KeepsARequestWhileClosingAndReopensOnceAfterClosed()
    {
        var gate = new FlyoutReopenGate();
        gate.Opened();
        Assert.True(gate.IsClosing(isOpen: false));
        Assert.False(gate.RequestShow(isOpen: false));
        Assert.False(gate.RequestShow(isOpen: false));
        Assert.True(gate.Closed());
        Assert.False(gate.IsClosing(isOpen: false));
        Assert.True(gate.RequestShow(isOpen: false));
        Assert.False(gate.Closed());
    }

    [Fact]
    public void ClosingWithoutARequestDoesNotReopen()
    {
        var gate = new FlyoutReopenGate();
        gate.Opened();
        Assert.False(gate.Closed());
        gate.Opened();
        Assert.False(gate.Closed());
    }
}
