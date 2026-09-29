namespace Festival.Core.Tests;

public class InstrumentSelectorTests
{
    private static InstrumentSelectorState Make(params Instrument[] instruments) => new() { Instruments = instruments };

    [Fact]
    public void Press_SelectsThenClears_UnlessRequired()
    {
        var state = Make(Instrument.Lead, Instrument.Bass);
        Assert.Equal(Instrument.Bass, state.Press(Instrument.Bass, out var changed));
        Assert.True(changed);
        state.Selected = Instrument.Bass;
        Assert.Null(state.Press(Instrument.Bass, out changed));
        Assert.True(changed);
        state.Required = true;
        Assert.Equal(Instrument.Bass, state.Press(Instrument.Bass, out changed));
        Assert.Equal(Instrument.Lead, state.Press(Instrument.Lead, out _));
    }

    [Fact]
    public void Press_IgnoresDisabledAndHidden()
    {
        var state = Make(Instrument.Lead, Instrument.Bass, Instrument.Drums);
        state.Disabled = new HashSet<Instrument> { Instrument.Bass };
        state.Hidden = new HashSet<Instrument> { Instrument.Drums };
        state.Press(Instrument.Bass, out var changed);
        Assert.False(changed);
        state.Press(Instrument.Drums, out changed);
        Assert.False(changed);
        Assert.Equal([Instrument.Lead, Instrument.Bass], state.Available);
    }

    [Fact]
    public void EffectiveSelected_DropsHiddenSelection()
    {
        var state = Make(Instrument.Lead, Instrument.Bass);
        state.Selected = Instrument.Bass;
        Assert.True(state.HasSelection);
        state.Hidden = new HashSet<Instrument> { Instrument.Bass };
        Assert.Null(state.EffectiveSelected);
        Assert.False(state.HasSelection);
        Assert.Equal(Instrument.Lead, state.CompactKey);
    }

    [Fact]
    public void Muted_OnlyWhenNotSelectedOrDisabled()
    {
        var state = Make(Instrument.Lead, Instrument.Bass, Instrument.Drums);
        state.Muted = new HashSet<Instrument> { Instrument.Lead, Instrument.Bass };
        state.Disabled = new HashSet<Instrument> { Instrument.Bass };
        state.Selected = Instrument.Lead;
        Assert.False(state.IsMuted(Instrument.Lead));
        Assert.False(state.IsMuted(Instrument.Bass));
        Assert.False(state.IsMuted(Instrument.Drums));
        state.Selected = Instrument.Drums;
        Assert.True(state.IsMuted(Instrument.Lead));
        Assert.False(state.IsCompactMuted());
        state.Selected = Instrument.Lead;
        Assert.True(state.IsCompactMuted());
    }

    [Theory]
    [InlineData(InstrumentSelectorCompactMode.Always, 2000, true)]
    [InlineData(InstrumentSelectorCompactMode.Never, 10, false)]
    [InlineData(InstrumentSelectorCompactMode.Auto, 0, false)]
    [InlineData(InstrumentSelectorCompactMode.Auto, 215, true)]
    [InlineData(InstrumentSelectorCompactMode.Auto, 216, false)]
    public void IsCompact_MeasuresThreeButtons(InstrumentSelectorCompactMode mode, double width, bool expected)
    {
        Assert.Equal(expected, Make(Instrument.Lead, Instrument.Bass, Instrument.Drums).IsCompact(mode, width));
    }

    [Fact]
    public void IsCompact_FalseWithoutInstruments()
    {
        Assert.False(Make().IsCompact(InstrumentSelectorCompactMode.Always, 10));
    }

    [Fact]
    public void Cycle_WrapsAndSkipsDisabled()
    {
        var state = Make(Instrument.Lead, Instrument.Bass, Instrument.Drums);
        state.Disabled = new HashSet<Instrument> { Instrument.Bass };
        Assert.Equal(Instrument.Lead, state.Cycle(1, out var changed));
        Assert.True(changed);
        Assert.Equal(Instrument.Drums, state.Cycle(-1, out _));
        state.Selected = Instrument.Lead;
        Assert.Equal(Instrument.Drums, state.Cycle(1, out _));
        state.Selected = Instrument.Drums;
        Assert.Equal(Instrument.Lead, state.Cycle(1, out _));
    }

    [Fact]
    public void Cycle_AllDisabledDoesNothing()
    {
        var state = Make(Instrument.Lead);
        state.Disabled = new HashSet<Instrument> { Instrument.Lead };
        state.Cycle(1, out var changed);
        Assert.False(changed);
        state.Selected = Instrument.Lead;
        Assert.Equal(Instrument.Lead, state.Cycle(1, out changed));
        Assert.False(changed);
        Make().Cycle(1, out changed);
        Assert.False(changed);
    }

    [Fact]
    public void DeferSelection_PreviewsThenCommits()
    {
        var state = Make(Instrument.Lead, Instrument.Bass, Instrument.Drums);
        state.DeferSelection = true;
        Assert.Equal(Instrument.Lead, state.CompactKey);
        state.Cycle(-1, out var changed);
        Assert.False(changed);
        Assert.Equal(Instrument.Drums, state.CompactKey);
        Assert.Equal(Instrument.Drums, state.PressCompact(out changed));
        Assert.True(changed);
        state.Selected = Instrument.Drums;
        Assert.Null(state.PressCompact(out _));
        state.Required = true;
        Assert.Equal(Instrument.Drums, state.PressCompact(out _));
    }

    [Fact]
    public void PressCompact_DisabledPreviewAndEmpty()
    {
        var state = Make(Instrument.Lead);
        state.Disabled = new HashSet<Instrument> { Instrument.Lead };
        state.PressCompact(out var changed);
        Assert.False(changed);
        Make().PressCompact(out changed);
        Assert.False(changed);
        Assert.Null(Make().CompactKey);
    }

    [Fact]
    public void ChangingAvailableCount_ResetsPreview()
    {
        var state = Make(Instrument.Lead, Instrument.Bass, Instrument.Drums);
        state.DeferSelection = true;
        state.Cycle(1, out _);
        Assert.Equal(Instrument.Bass, state.CompactKey);
        state.Hidden = new HashSet<Instrument> { Instrument.Drums };
        Assert.Equal(Instrument.Lead, state.CompactKey);
        state.Cycle(1, out _);
        state.Instruments = [Instrument.Lead, Instrument.Bass, Instrument.Vocals, Instrument.Drums];
        Assert.Equal(Instrument.Lead, state.CompactKey);
        state.Cycle(1, out _);
        state.Instruments = [Instrument.Bass, Instrument.Lead, Instrument.Vocals, Instrument.Drums];
        Assert.Equal(Instrument.Lead, state.CompactKey);
    }
}
