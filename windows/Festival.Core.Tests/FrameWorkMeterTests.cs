using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>The scroll probe's per-frame UI-thread work samples (issues #668, #676).</summary>
public sealed class FrameWorkMeterTests
{
    [Fact]
    public void IdleBeforeTheNextFrame_RecordsTheFramesWork()
    {
        var meter = new FrameWorkMeter();
        Assert.True(meter.Frame(0));
        meter.Marked(0);
        meter.Idle(4.5);
        Assert.True(meter.Frame(16));
        Assert.Equal([4.5], meter.Samples);
    }

    [Fact]
    public void MarkerStillPendingAtTheNextFrame_EndsTheSampleAtTheInterval()
    {
        var meter = new FrameWorkMeter();
        meter.Frame(0);
        meter.Marked(0);
        Assert.False(meter.Frame(31));
        meter.Idle(40);
        Assert.Equal([31.0], meter.Samples);
    }

    [Fact]
    public void FramesWhileTheMarkerStaysPending_AddNoSamples()
    {
        // #676: a scrollbar drag kept the UI thread busy between on-time frames for 1.15 s and logged one 1.15 s "frame".
        var meter = new FrameWorkMeter();
        meter.Frame(0);
        meter.Marked(0);
        for (var t = 60.0; t < 1150; t += 60) Assert.False(meter.Frame(t));
        meter.Idle(1150);
        Assert.Equal([60.0], meter.Samples);
        Assert.True(meter.Frame(1160));
    }

    [Fact]
    public void LongFrame_CountsForItsWholeLength()
    {
        // A frame whose own layout takes 500 ms delays the next Rendering, so the sample still spans it.
        var meter = new FrameWorkMeter();
        meter.Frame(0);
        meter.Marked(0);
        meter.Frame(500);
        Assert.Equal([500.0], meter.Samples);
    }

    [Fact]
    public void EverySampleIsAtMostTheUncappedOne()
    {
        // Uncapped (Rendering to idle): 20, 2, 251, 2. Capped at the next Rendering: 16, 2, 71, 2.
        var meter = new FrameWorkMeter();
        void Frame(double t)
        {
            if (meter.Frame(t)) meter.Marked(t);
        }
        Frame(0);
        Frame(16);
        meter.Idle(20);
        Frame(33);
        meter.Idle(35);
        Frame(49);
        Frame(120);
        Frame(136);
        meter.Idle(300);
        Frame(310);
        meter.Idle(312);
        Assert.Equal([16.0, 2, 71, 2], meter.Samples);
    }

    [Fact]
    public void Reset_ClearsSamplesAndThePendingMarker()
    {
        var meter = new FrameWorkMeter();
        meter.Frame(0);
        meter.Marked(0);
        meter.Idle(2);
        meter.Frame(10);
        meter.Marked(10);
        meter.Reset();
        Assert.Empty(meter.Samples);
        Assert.True(meter.Frame(20));
        meter.Idle(25);
        Assert.Empty(meter.Samples);
    }
}
