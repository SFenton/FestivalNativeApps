using CommunityToolkit.Mvvm.ComponentModel;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

public partial class AccessibilityAnnouncerTests
{
    private sealed partial class Model : ObservableObject
    {
        [ObservableProperty] private bool loading;
        [ObservableProperty] private string? summary;
    }

    private static (Model Model, FakeTimeProvider Time, LoadAnnouncer Announcer, List<Announcement> Spoken) Create(bool loading = false, string? summary = null,
        string? loadingText = "Loading songs")
    {
        var model = new Model { Loading = loading, Summary = summary };
        var time = new FakeTimeProvider();
        var announcer = new LoadAnnouncer([model], () => model.Loading, () => model.Summary, loadingText, time);
        var spoken = new List<Announcement>();
        announcer.Announced += (_, a) => spoken.Add(a);
        return (model, time, announcer, spoken);
    }

    [Fact]
    public void SlowLoad_AnnouncesLoadingOnceThenSummary()
    {
        var (model, time, _, spoken) = Create();
        model.Loading = true;
        time.Advance(TimeSpan.FromMilliseconds(900));
        Assert.Empty(spoken);
        time.Advance(TimeSpan.FromMilliseconds(200));
        Assert.Equal([new Announcement("Loading songs", AnnouncementKind.Progress)], spoken);
        time.Advance(TimeSpan.FromSeconds(5));
        Assert.Single(spoken);

        model.Summary = "245 songs";
        model.Loading = false;
        time.Advance(TimeSpan.FromMilliseconds(599));
        Assert.Single(spoken);
        time.Advance(TimeSpan.FromMilliseconds(1));
        Assert.Equal(new Announcement("245 songs", AnnouncementKind.Completed), spoken[^1]);
        Assert.Equal("fst.a11y.results", spoken[^1].ActivityId);
        Assert.Equal("fst.a11y.loading", spoken[0].ActivityId);
    }

    [Fact]
    public void FastLoad_SpeaksOnlyTheSummary()
    {
        var (model, time, _, spoken) = Create();
        model.Loading = true;
        time.Advance(TimeSpan.FromMilliseconds(300));
        model.Summary = "2 songs";
        model.Loading = false;
        time.Advance(TimeSpan.FromSeconds(2));
        Assert.Equal([new Announcement("2 songs", AnnouncementKind.Completed)], spoken);
    }

    [Fact]
    public void Typing_DebouncesToTheFinalSummary_AndRepeatsAreSilent()
    {
        var (model, time, _, spoken) = Create(summary: "245 songs");
        Assert.Empty(spoken);
        model.Summary = "40 songs";
        time.Advance(TimeSpan.FromMilliseconds(300));
        model.Summary = "3 songs";
        time.Advance(TimeSpan.FromMilliseconds(300));
        model.Summary = "1 song";
        time.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal([new Announcement("1 song", AnnouncementKind.Completed)], spoken);
        model.Summary = "1 song";
        model.Loading = false;
        time.Advance(TimeSpan.FromSeconds(1));
        Assert.Single(spoken);
    }

    [Fact]
    public void InitiallyLoading_StartsTheLoadingTimer_AndBlankSummariesAreIgnored()
    {
        var (model, time, _, spoken) = Create(loading: true, summary: "stale");
        time.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal("Loading songs", Assert.Single(spoken).Text);
        model.Summary = " ";
        model.Loading = false;
        time.Advance(TimeSpan.FromSeconds(1));
        Assert.Single(spoken);
        // A summary equal to the pre-load one is still news after a load (lastSummary was not captured while loading).
        model.Summary = "stale";
        time.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal("stale", spoken[^1].Text);
    }

    [Fact]
    public void LoadingThatEndsBeforeTheSettle_IsNotAnnounced_AndNoLoadingTextStaysSilent()
    {
        var (model, time, _, spoken) = Create(loadingText: null);
        model.Summary = "5 songs";
        time.Advance(TimeSpan.FromMilliseconds(300));
        model.Loading = true;
        time.Advance(TimeSpan.FromSeconds(3));
        Assert.Empty(spoken);
        model.Loading = false;
        time.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal("5 songs", Assert.Single(spoken).Text);
    }

    [Fact]
    public void Dispose_StopsListeningAndCancelsPendingAnnouncements()
    {
        var (model, time, announcer, spoken) = Create();
        model.Loading = true;
        announcer.Dispose();
        announcer.Dispose();
        time.Advance(TimeSpan.FromSeconds(2));
        model.Loading = false;
        model.Summary = "9 songs";
        announcer.Evaluate();
        time.Advance(TimeSpan.FromSeconds(2));
        Assert.Empty(spoken);
    }

    [Fact]
    public void Dispatch_RunsDelayedCallbacks()
    {
        var model = new Model();
        var time = new FakeTimeProvider();
        var dispatched = 0;
        using var announcer = new LoadAnnouncer([model], () => model.Loading, () => model.Summary, "Loading", time,
            TimeSpan.FromMilliseconds(10), TimeSpan.FromMilliseconds(10), action => { dispatched++; action(); });
        var spoken = new List<Announcement>();
        announcer.Announced += (_, a) => spoken.Add(a);
        model.Loading = true;
        time.Advance(TimeSpan.FromMilliseconds(10));
        model.Summary = "Done";
        model.Loading = false;
        time.Advance(TimeSpan.FromMilliseconds(10));
        Assert.Equal(2, dispatched);
        Assert.Equal(["Loading", "Done"], spoken.Select(a => a.Text));
    }

    [Fact]
    public void Failure_CombinesTitleAndMessage()
    {
        Assert.Equal(new Announcement("Songs unavailable. Try again later.", AnnouncementKind.Error),
            Announcement.Failure("Songs unavailable", "Try again later."));
        Assert.Equal("Songs unavailable", Announcement.Failure("Songs unavailable", " ").Text);
        Assert.Equal("fst.a11y.error", Announcement.Failure("x", "").ActivityId);
    }
}
