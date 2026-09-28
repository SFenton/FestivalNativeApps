namespace Festival.Core.Tests;

#region Occlusion
public sealed class WindowOcclusionTests
{
    private static readonly PixelRect App = new(100, 100, 500, 400);

    [Fact]
    public void FullCoverByOneWindow_IsOccluded()
    {
        Assert.True(WindowOcclusion.IsOccluded(App, [new WindowSnapshot(new PixelRect(0, 0, 1920, 1080))]));
        Assert.True(WindowOcclusion.IsOccluded(App, [new WindowSnapshot(App)]));
    }

    [Fact]
    public void PartialCover_IsVisible()
    {
        Assert.False(WindowOcclusion.IsOccluded(App, [new WindowSnapshot(new PixelRect(100, 100, 499, 400))]));
        Assert.False(WindowOcclusion.IsOccluded(App, [new WindowSnapshot(new PixelRect(600, 0, 900, 900))]));
        Assert.False(WindowOcclusion.IsOccluded(App, []));
    }

    [Fact]
    public void UnionOfSeveralWindows_Occludes()
    {
        // Snapped halves plus a strip covering the seam and a hole in the middle.
        WindowSnapshot[] tiles =
        [
            new(new PixelRect(0, 0, 300, 1080)),
            new(new PixelRect(300, 0, 1920, 250)),
            new(new PixelRect(300, 250, 1920, 1080)),
        ];
        Assert.True(WindowOcclusion.IsOccluded(App, tiles));
        Assert.False(WindowOcclusion.IsOccluded(App, tiles[..2]));
        WindowSnapshot[] ring =
        [
            new(new PixelRect(0, 0, 1920, 200)), new(new PixelRect(0, 300, 1920, 1080)),
            new(new PixelRect(0, 0, 250, 1080)), new(new PixelRect(350, 0, 1920, 1080)),
        ];
        Assert.False(WindowOcclusion.IsOccluded(App, ring));
        Assert.True(WindowOcclusion.IsOccluded(App, [.. ring, new(new PixelRect(250, 200, 350, 300))]));
    }

    [Theory]
    [InlineData(false, false, false, false, false, false, false)]
    [InlineData(true, true, false, false, false, false, false)]
    [InlineData(true, false, true, false, false, false, false)]
    [InlineData(true, false, false, true, false, false, false)]
    [InlineData(true, false, false, false, true, false, false)]
    [InlineData(true, false, false, false, false, true, false)]
    public void NonOpaqueWindows_NeverOcclude(bool visible, bool minimized, bool cloaked, bool clickThrough, bool layered, bool region, bool layeredOpaque)
    {
        var window = new WindowSnapshot(new PixelRect(0, 0, 1920, 1080), visible, minimized, cloaked, clickThrough, layered, layeredOpaque, region);
        Assert.False(WindowOcclusion.IsOpaqueOccluder(window));
        Assert.False(WindowOcclusion.IsOccluded(App, [window]));
    }

    [Fact]
    public void OpaqueLayeredWindow_Occludes_EmptyRectsDoNot()
    {
        Assert.True(WindowOcclusion.IsOccluded(App, [new WindowSnapshot(new PixelRect(0, 0, 1920, 1080), Layered: true, LayeredOpaque: true)]));
        Assert.False(WindowOcclusion.IsOpaqueOccluder(new WindowSnapshot(new PixelRect(5, 5, 5, 10))));
        Assert.False(WindowOcclusion.IsCovered(new PixelRect(0, 0, 0, 0), [new PixelRect(0, 0, 10, 10)]));
    }

    [Fact]
    public void TooManyFragments_ReportsVisible()
    {
        // A grid of 1-px holes explodes the uncovered fragments; the check gives up and keeps animating.
        var covers = Enumerable.Range(0, 200).Select(i => new PixelRect(App.Left + i * 2, App.Top, App.Left + i * 2 + 1, App.Bottom))
            .Concat(Enumerable.Range(0, 150).Select(i => new PixelRect(App.Left, App.Top + i * 2, App.Right, App.Top + i * 2 + 1)));
        Assert.False(WindowOcclusion.IsCovered(App, covers));
        Assert.Equal(new PixelRect(2, 3, 4, 5), new PixelRect(0, 0, 4, 5).Intersect(new PixelRect(2, 3, 9, 9)));
    }
}
#endregion
