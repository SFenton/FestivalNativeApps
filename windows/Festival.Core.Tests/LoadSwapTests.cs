using Festival.Core.Domain;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

public class LoadSwapTests
{
    [Fact]
    public async Task Reload_FadesContentOutThenSpinnerOutThenReveals()
    {
        var time = new FakeTimeProvider();
        var swap = new LoadSwap(time, initiallyVisible: true);
        var begin = swap.BeginReloadAsync(animate: true, hasContent: true);
        Assert.Equal(LoadSwapPhase.ContentOut, swap.Phase);
        time.Advance(LoadSwapTiming.ContentOut - TimeSpan.FromMilliseconds(1));
        Assert.False(begin.IsCompleted);
        time.Advance(TimeSpan.FromMilliseconds(1));
        var revision = await begin;
        Assert.Equal(LoadSwapPhase.Loading, swap.Phase);

        var applied = false;
        var revealed = false;
        swap.ContentRevealed += (_, _) => revealed = true;
        var commit = swap.CommitAsync(revision, () => applied = true, animate: true);
        Assert.True(applied);
        Assert.Equal(LoadSwapPhase.SpinnerOut, swap.Phase);
        time.Advance(LoadSwapTiming.SpinnerOut - TimeSpan.FromMilliseconds(1));
        Assert.False(commit.IsCompleted);
        time.Advance(TimeSpan.FromMilliseconds(1));
        Assert.True(await commit);
        Assert.Equal(LoadSwapPhase.ContentIn, swap.Phase);
        Assert.True(revealed);
    }

    [Fact]
    public async Task ReduceMotion_SkipsFadesAndWaits()
    {
        var swap = new LoadSwap(new FakeTimeProvider(), initiallyVisible: true);
        var revision = await swap.BeginReloadAsync(animate: false, hasContent: true);
        Assert.Equal(LoadSwapPhase.Loading, swap.Phase);
        var applied = false;
        Assert.True(await swap.CommitAsync(revision, () => applied = true, animate: false));
        Assert.True(applied);
        Assert.Equal(LoadSwapPhase.ContentIn, swap.Phase);
    }

    [Fact]
    public async Task RapidSelection_OnlyLatestCommitApplies()
    {
        var time = new FakeTimeProvider();
        var swap = new LoadSwap(time, initiallyVisible: true);
        var first = swap.BeginReloadAsync(animate: true, hasContent: true);
        var second = await swap.BeginReloadAsync(animate: true, hasContent: true);
        time.Advance(LoadSwapTiming.ContentOut);
        var firstRevision = await first;
        var staleApplied = false;
        var latestApplied = false;
        Assert.False(await swap.CommitAsync(firstRevision, () => staleApplied = true, animate: false));
        Assert.True(await swap.CommitAsync(second, () => latestApplied = true, animate: false));
        Assert.False(staleApplied);
        Assert.True(latestApplied);
        Assert.Equal(LoadSwapPhase.ContentIn, swap.Phase);
    }

    [Fact]
    public void CachedFirstVisit_ShowsImmediately()
    {
        var swap = new LoadSwap(new FakeTimeProvider());
        var applied = false;
        var revealed = false;
        swap.ContentRevealed += (_, _) => revealed = true;
        swap.ShowImmediately(() => applied = true);
        Assert.True(applied);
        Assert.True(revealed);
        Assert.Equal(LoadSwapPhase.ContentIn, swap.Phase);
    }

    [Fact]
    public async Task FailureState_IsCommittedAfterTheSameCycle()
    {
        var time = new FakeTimeProvider();
        var swap = new LoadSwap(time, initiallyVisible: true);
        var begin = swap.BeginReloadAsync(animate: true, hasContent: true);
        time.Advance(LoadSwapTiming.ContentOut);
        var revision = await begin;
        var state = "old";
        var commit = swap.CommitAsync(revision, () => state = "failed", animate: true);
        Assert.Equal("failed", state);
        Assert.Equal(LoadSwapPhase.SpinnerOut, swap.Phase);
        time.Advance(LoadSwapTiming.SpinnerOut);
        Assert.True(await commit);
        Assert.Equal(LoadSwapPhase.ContentIn, swap.Phase);
        Assert.Equal("failed", state);
    }
}
