using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

// Ported from apple/Tests/FestivalCoreTests/QuickLinksTests.swift, plus the Windows view model.
public class QuickLinksTests
{
    private static readonly QuickLinkSection[] Sections = new[] { "a", "b", "c", "d" }.Select(id => new QuickLinkSection(id, id.ToUpperInvariant())).ToArray();

    private static Dictionary<string, QuickLinkFrame> Frames(params (string Id, double MinY, double Height)[] entries) =>
        entries.ToDictionary(e => e.Id, e => new QuickLinkFrame(e.MinY, e.MinY + e.Height));

    #region Rules
    [Fact]
    public void EntryPointNeedsTwoSectionsAndPaneNeedsWideWindow()
    {
        Assert.False(QuickLinks.IsAvailable(0));
        Assert.False(QuickLinks.IsAvailable(1));
        Assert.True(QuickLinks.IsAvailable(2));
        Assert.False(QuickLinks.UsesPane(1149));
        Assert.True(QuickLinks.UsesPane(1150));
    }

    [Fact]
    public void ExplicitWinsAndDuplicatesKeepFirst()
    {
        QuickLinkSection[] explicitSections = [new("x", "X"), new("y", "Y")];
        Assert.Equal(["x", "y"], QuickLinks.Ordered(explicitSections, Sections).Select(s => s.Id));
        Assert.Equal(["a", "b", "c", "d"], QuickLinks.Ordered(null, Sections).Select(s => s.Id));
        var ordered = QuickLinks.Ordered(null, [new("a", "First"), new("b", "B"), new("a", "Second")]);
        Assert.Equal(["a", "b"], ordered.Select(s => s.Id));
        Assert.Equal("First", ordered[0].Title);
    }

    [Fact]
    public void JumpOffsetKeepsMarginAndClampsToScrollRange()
    {
        Assert.Equal(1292, QuickLinks.JumpOffset(300, 1000, 5000, 8));
        Assert.Equal(0, QuickLinks.JumpOffset(0, 4, 5000, 8));
        Assert.Equal(2000, QuickLinks.JumpOffset(1500, 900, 2000, 8));
        Assert.Equal(0, QuickLinks.JumpOffset(0, 500, -1, 8));
        // Re-measuring after the list realizes its cards re-aims to the anchor's real position.
        Assert.Equal(1872, QuickLinks.JumpOffset(1292, 588, 5000, 8));
    }

    [Fact]
    public void LandedWithinTolerance()
    {
        Assert.True(QuickLinks.IsLanded(100, 100.4));
        Assert.False(QuickLinks.IsLanded(100, 100.5));
        Assert.False(QuickLinks.IsLanded(1292, 1872));
        Assert.True(QuickLinks.MaxJumpCorrections > 0);
    }

    [Fact]
    public void SectionDefaults()
    {
        Assert.Equal(0, new QuickLinkSection("a", "A", Depth: -3).Depth);
        Assert.Equal(2, new QuickLinkSection("a", "A", Depth: 2).Depth);
        Assert.Equal("Lead Rank History", new QuickLinkSection("a", "Rank History", SpokenTitle: "Lead Rank History").AccessibleTitle);
        Assert.Equal("A", new QuickLinkSection("a", "A").AccessibleTitle);
        Assert.Equal("fst.quick-links.item.a", new QuickLinkSection("a", "A").AutomationId);
    }

    [Fact]
    public void VisibilityRequiresIntersection()
    {
        Assert.False(QuickLinks.IsVisible(null, 600));
        Assert.True(QuickLinks.IsVisible(new QuickLinkFrame(-100, 1), 600));
        Assert.False(QuickLinks.IsVisible(new QuickLinkFrame(-100, 0), 600));
        Assert.False(QuickLinks.IsVisible(new QuickLinkFrame(600, 900), 600));
        Assert.Equal(10, new QuickLinkFrame(10, 5).MaxY);
    }

    [Fact]
    public void NaturalActiveIsLastPastTheLine()
    {
        var f = Frames(("a", -500, 300), ("b", -200, 200), ("c", 10, 300), ("d", 400, 300));
        Assert.Equal("c", QuickLinks.NaturalActive(Sections, f));
        Assert.Equal("b", QuickLinks.NaturalActive(Sections, f, 0));
    }

    [Fact]
    public void LandingTargetPutsSectionsOnTheLandingLine()
    {
        Assert.Equal(32d, QuickLinks.LandingOffset);
        Assert.Equal(QuickLinks.LandingOffset, QuickLinks.DefaultActivationOffset);
        Assert.Equal(468d, QuickLinks.LandingTarget(500, 2000));
        Assert.Equal(0d, QuickLinks.LandingTarget(20, 2000));
        Assert.Equal(300d, QuickLinks.LandingTarget(500, 300));
        Assert.Equal(0d, QuickLinks.LandingTarget(500, -1));
        Assert.Equal(492d, QuickLinks.LandingTarget(500, 2000, 8));
        // The binder's re-aiming jump (#46) lands on the same 32 epx line by default.
        Assert.Equal(1268d, QuickLinks.JumpOffset(300, 1000, 5000));
    }

    [Fact]
    public void JumpLandedOnTheLineIsActiveAndReleasesOnDrift()
    {
        var line = QuickLinks.LandingOffset;
        var landed = Frames(("b", line - 300, 300), ("c", line, 300), ("d", line + 300, 300));
        Assert.Equal("c", QuickLinks.NaturalActive(Sections, landed));
        var tracker = new QuickLinkTracker();
        tracker.BeginJump("c");
        tracker.Settle(Sections, landed, 800);
        Assert.Equal((QuickLinkPhase.Owned, "c", false), (tracker.Phase, tracker.ActiveId, tracker.LockWhileVisible));
        tracker.Update(Sections, Frames(("c", line - 200, 300), ("d", line + 100, 300)), 800);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
    }

    [Fact]
    public void NaturalActiveDefaultsToFirstAndSkipsUnbuilt()
    {
        Assert.Null(QuickLinks.NaturalActive([], Frames()));
        Assert.Equal("a", QuickLinks.NaturalActive(Sections, Frames()));
        Assert.Equal("a", QuickLinks.NaturalActive(Sections, Frames(("a", 50, 300))));
        Assert.Equal("c", QuickLinks.NaturalActive(Sections, Frames(("c", -40, 400), ("d", 500, 300))));
    }
    #endregion

    #region Tracker
    [Fact]
    public void IdleFollowsScroll()
    {
        var tracker = new QuickLinkTracker();
        tracker.Update(Sections, Frames(("a", -300, 200), ("b", -100, 400)), 600);
        Assert.Equal("b", tracker.ActiveId);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
    }

    [Fact]
    public void JumpHoldsTargetWhileScrollingEvenIfNotBuilt()
    {
        var tracker = new QuickLinkTracker();
        tracker.BeginJump("d");
        Assert.Equal("d", tracker.ActiveId);
        tracker.Update(Sections, Frames(("a", 0, 300)), 600);
        Assert.Equal("d", tracker.ActiveId);
        Assert.Equal(QuickLinkPhase.Scrolling, tracker.Phase);
        Assert.Equal("d", tracker.Target);
    }

    [Fact]
    public void JumpReleasesWhenTargetRemoved()
    {
        var tracker = new QuickLinkTracker();
        tracker.BeginJump("z");
        tracker.Update(Sections, Frames(("a", 0, 300)), 600);
        Assert.Equal("a", tracker.ActiveId);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
    }

    [Fact]
    public void SettledJumpOwnsUntilReaderScrollsAway()
    {
        var tracker = new QuickLinkTracker();
        tracker.BeginJump("b");
        tracker.Settle(Sections, Frames(("a", -300, 300), ("b", 0, 300), ("c", 300, 300)), 600);
        Assert.Equal((QuickLinkPhase.Owned, "b", 0d, false), (tracker.Phase, tracker.Target, tracker.AnchorMinY, tracker.LockWhileVisible));
        tracker.Update(Sections, Frames(("a", -250, 300), ("b", 50, 300)), 600);
        Assert.Equal("b", tracker.ActiveId);
        tracker.Update(Sections, Frames(("b", -400, 300), ("c", -100, 300)), 600);
        Assert.Equal("c", tracker.ActiveId);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
    }

    [Fact]
    public void SettledJumpNearEndLocksWhileVisible()
    {
        var tracker = new QuickLinkTracker();
        tracker.BeginJump("d");
        tracker.Settle(Sections, Frames(("c", -50, 400), ("d", 350, 200)), 600);
        Assert.Equal((QuickLinkPhase.Owned, 350d, true), (tracker.Phase, tracker.AnchorMinY, tracker.LockWhileVisible));
        tracker.Update(Sections, Frames(("c", 100, 400), ("d", 500, 200)), 600);
        Assert.Equal("d", tracker.ActiveId);
        tracker.Update(Sections, Frames(("b", 0, 400), ("d", 700, 200)), 600);
        Assert.Equal("b", tracker.ActiveId);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
    }

    [Fact]
    public void SettleFallsBackWhenTargetOffScreenOrMissing()
    {
        var tracker = new QuickLinkTracker();
        tracker.BeginJump("c");
        tracker.Settle(Sections, Frames(("a", -10, 300), ("c", 900, 300)), 600);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
        Assert.Equal("a", tracker.ActiveId);
        tracker.Settle(Sections, Frames(), 600);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
        tracker.BeginJump("z");
        tracker.Settle(Sections, Frames(("z", 0, 10)), 600);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
    }

    [Fact]
    public void OwnedTargetReleasesWhenFrameDisappears()
    {
        var tracker = new QuickLinkTracker();
        tracker.BeginJump("b");
        tracker.Settle(Sections, Frames(("b", 0, 300)), 600);
        tracker.Update(Sections, Frames(("a", 0, 300)), 600);
        Assert.Equal("a", tracker.ActiveId);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
    }

    [Fact]
    public void OwnedTargetHoldsAtAnchorOutsideReachableBand()
    {
        var tracker = new QuickLinkTracker();
        tracker.BeginJump("b");
        tracker.Settle(Sections, Frames(("a", -600, 400), ("b", 0, 900)), 600, 0);
        tracker.Update(Sections, Frames(("b", 4, 900)), 600, 0);
        Assert.Equal("b", tracker.ActiveId);
    }

    [Fact]
    public void OwnedTargetHoldsWhenOnlyDriftingWithinThreshold()
    {
        var tracker = new QuickLinkTracker();
        tracker.BeginJump("b");
        tracker.Settle(Sections, Frames(("b", -200, 900)), 600, 0);
        // Outside the reachable band (-200 < -96) but within 8 epx of the anchor.
        tracker.Update(Sections, Frames(("b", -205, 900)), 600, 0);
        Assert.Equal("b", tracker.ActiveId);
        tracker.Update(Sections, Frames(("b", -300, 900)), 600, 0);
        Assert.Equal(QuickLinkPhase.Idle, tracker.Phase);
    }
    #endregion

    #region View model
    [Fact]
    public void ViewModel_JumpsTracksAndNamesEntryPoint()
    {
        var vm = new QuickLinksViewModel("Quick Links");
        Assert.False(vm.IsAvailable);
        Assert.Equal("Quick Links", vm.EntryName);
        Assert.Equal("", vm.ActiveTitle);
        vm.SetSections([.. Sections, new QuickLinkSection("a", "Duplicate")]);
        Assert.True(vm.IsAvailable);
        Assert.Equal(4, vm.Items.Count);
        Assert.Equal("a", vm.ActiveId);
        Assert.True(vm.Items[0].IsActive);
        Assert.Equal("A, current section", vm.Items[0].AccessibleName);
        Assert.Equal("B", vm.Items[1].AccessibleName);
        Assert.Equal("Quick Links, current section A", vm.EntryName);

        string? requested = null;
        vm.JumpRequested += (_, id) => requested = id;
        vm.Jump("nope");
        Assert.Null(requested);
        vm.Jump("c");
        Assert.Equal("c", requested);
        Assert.Equal("C", vm.ActiveTitle);
        Assert.Equal(QuickLinkPhase.Scrolling, vm.Phase);
        vm.ReportLayout(Frames(("b", -300, 300), ("c", 0, 300)), 600, isFinal: false);
        Assert.Equal(QuickLinkPhase.Scrolling, vm.Phase);
        vm.ReportLayout(Frames(("b", -300, 300), ("c", 0, 300)), 600, isFinal: true);
        Assert.Equal(QuickLinkPhase.Owned, vm.Phase);
        Assert.True(vm.Items[2].IsActive);
        vm.ReportLayout(Frames(("c", -900, 300), ("d", -10, 300)), 600, isFinal: true);
        Assert.Equal("d", vm.ActiveId);
        Assert.Equal("Glyph", new QuickLinkItemViewModel(new QuickLinkSection("g", "G", "Glyph")).Glyph);
        Assert.Equal("", vm.Items[0].Glyph);
        Assert.Equal("fst.quick-links.item.a", vm.Items[0].AutomationId);
        Assert.Equal("A", vm.Items[0].Title);
        Assert.Equal(QuickLinks.DefaultActivationOffset, vm.ActivationOffset);
    }

    [Fact]
    public void ViewModel_SetSectionsIsIdempotentAndRefreshes()
    {
        var vm = new QuickLinksViewModel();
        vm.SetSections(Sections);
        var items = vm.Items;
        vm.SetSections(Sections);
        Assert.Same(items, vm.Items);
        vm.ReportLayout(Frames(("a", -900, 300), ("b", -600, 300), ("c", -10, 300)), 600, false);
        Assert.Equal("c", vm.ActiveId);
        vm.SetSections(Sections.Take(2));
        Assert.Equal("b", vm.ActiveId);
        vm.SetSections([new QuickLinkSection("a", "Renamed"), Sections[1]]);
        Assert.Equal("Renamed", vm.Items[0].Title);
    }
    #endregion
}
