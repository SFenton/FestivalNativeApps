using System.Net;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

public class SettingsServiceInfoTests
{
    private static ServiceInfo Info(ServiceCurrentUpdate current, string? worker = "online", double? contract = 2,
        ServicePhasePlan? plan = null, string? publishedAt = "2026-09-28T15:04:05.1234567Z", ServicePublicationState? publication = null) =>
        new(contract, plan, new ServiceCompletedUpdate(publishedAt, null), current, 99, publication,
            worker is null ? null : new ServiceWorkerStatus(worker), null);

    private static ServiceCurrentUpdate Updating(string phase = "post.compute_rankings", double attempt = 1, double ordinal = 5,
        ServiceSubphaseProgress? sub = null, string? subphaseId = "per_instrument_rankings", string? at = "2026-09-28T15:00:00Z",
        double? percent = null, bool? final = null) =>
        new("updating", ScrapeId: 42, OperationId: "op", PhaseId: phase, PhaseAttempt: attempt, PhaseOrdinal: ordinal,
            SubphaseId: subphaseId, SubphaseProgress: sub, LastProgressAt: at, PhasePercent: percent, UnitsTotalFinal: final);

    private static ServiceSubphaseProgress Sub(double completed, double total, double percent, double sequence = 1,
        string kind = "exact", bool final = true, string id = "per_instrument_rankings", double schema = 1) =>
        new(schema, id, 1, sequence, kind, "leaderboards", completed, total, final, percent);

    #region Reducer
    [Fact]
    public void Reduce_IdleIsEmpty()
    {
        var (display, memory) = ServiceProgressReducer.Reduce(null, Info(new ServiceCurrentUpdate("idle")));
        Assert.Same(ServiceProgressDisplay.Empty, display);
        Assert.Null(memory.OperationIdentity);
        Assert.Null(ServiceProgressReducer.OperationIdentity(new ServiceInfo(null, null, null, new ServiceCurrentUpdate("idle"), null, null, null, null)));
        Assert.Equal("1.5:legacy:unversioned", ServiceProgressReducer.OperationIdentity(
            new ServiceInfo(null, null, null, new ServiceCurrentUpdate("idle"), 1.5, null, null, null)));
        Assert.Equal("t0:op:v2", ServiceProgressReducer.OperationIdentity(
            new ServiceInfo(null, new ServicePhasePlan("v2", null), null, new ServiceCurrentUpdate("idle", StartedAt: "t0", OperationId: "op"), null, null, null, null)));
    }

    [Fact]
    public void Reduce_ExactSubphaseIsMonotonicAndIgnoresStale()
    {
        var (first, memory) = ServiceProgressReducer.Reduce(null, Info(Updating(sub: Sub(50, 100, 50))));
        Assert.Equal(ServiceBarKind.Exact, first.BarProgress!.Kind);
        Assert.Equal(50, first.BarProgress.Percent);
        Assert.Equal("42:op:unversioned", memory.OperationIdentity);

        // Lower percent, same identity and a newer sequence: the bar never moves back.
        var (second, memory2) = ServiceProgressReducer.Reduce(memory, Info(Updating(sub: Sub(40, 100, 40, sequence: 2), at: "2026-09-28T15:00:05Z")));
        Assert.Equal(50, second.BarProgress!.Percent);

        // Older sequence: the previous bar is kept as is.
        var (third, _) = ServiceProgressReducer.Reduce(memory2, Info(Updating(sub: Sub(90, 100, 90, sequence: 1), at: "2026-09-28T15:00:06Z")));
        Assert.Same(second.BarProgress, third.BarProgress);

        // Older timestamp: the whole payload is ignored.
        var (stale, _) = ServiceProgressReducer.Reduce(memory2, Info(Updating(sub: Sub(99, 100, 99, sequence: 9), at: "2026-09-28T14:00:00Z")));
        Assert.True(stale.StalePayloadIgnored);
        Assert.Equal(50, stale.BarProgress!.Percent);
    }

    [Fact]
    public void Reduce_RestartedAttemptResets()
    {
        var (_, memory) = ServiceProgressReducer.Reduce(null, Info(Updating(sub: Sub(80, 100, 80), percent: 80, final: true)));
        Assert.Equal(80, memory.Display.PhasePercent);
        var (retry, _) = ServiceProgressReducer.Reduce(memory, Info(Updating(attempt: 2, sub: Sub(10, 100, 10), percent: 10, final: true, at: "2026-09-28T14:00:00Z")));
        Assert.True(retry.Restarted);
        Assert.Equal(10, retry.PhasePercent);
        Assert.Equal(10, retry.BarProgress!.Percent);
        var (earlier, _) = ServiceProgressReducer.Reduce(memory, Info(Updating(ordinal: 1, sub: Sub(5, 100, 5))));
        Assert.True(earlier.Restarted);
    }

    [Theory]
    [InlineData("exact", false, 1, ServiceBarKind.Indeterminate)]
    [InlineData("exact", true, 2, ServiceBarKind.Indeterminate)]
    [InlineData("not_applicable", true, 1, ServiceBarKind.NotApplicable)]
    [InlineData("mystery", true, 1, ServiceBarKind.Indeterminate)]
    public void Reduce_SubphaseKinds(string kind, bool final, double schema, ServiceBarKind expected)
    {
        var (display, _) = ServiceProgressReducer.Reduce(null, Info(Updating(sub: Sub(1, 10, 10, kind: kind, final: final, schema: schema))));
        Assert.Equal(expected, display.BarProgress!.Kind);
        if (expected != ServiceBarKind.Exact) Assert.Null(display.BarProgress.UnitsCompleted);
    }

    [Fact]
    public void Reduce_MismatchedSubphaseAndLegacyAndPhaseBars()
    {
        var mismatched = ServiceProgressReducer.Reduce(null, Info(Updating(sub: Sub(1, 10, 10, id: "other")))).Display;
        Assert.Equal(ServiceBarKind.Indeterminate, mismatched.BarProgress!.Kind);

        var legacy = ServiceProgressReducer.Reduce(null, Info(Updating(sub: null))).Display;
        Assert.EndsWith(":per_instrument_rankings:legacy", legacy.BarProgress!.Identity, StringComparison.Ordinal);

        var phase = ServiceProgressReducer.Reduce(null, Info(Updating(sub: null, subphaseId: null, percent: 150, final: true))).Display;
        Assert.Equal((ServiceBarKind.Exact, 100.0), (phase.BarProgress!.Kind, phase.BarProgress.Percent!.Value));
        var unknown = ServiceProgressReducer.Reduce(null, Info(Updating(sub: null, subphaseId: null, percent: double.NaN, final: true))).Display;
        Assert.Equal(ServiceBarKind.Indeterminate, unknown.BarProgress!.Kind);
        var v1 = ServiceProgressReducer.Reduce(null, Info(Updating(phase: null!, sub: null, subphaseId: null, percent: 40, final: true) with { PhaseId = null }, contract: 1)).Display;
        Assert.Null(v1.PhasePercent);
    }

    private static ServiceAttemptProgressWire Attempts(double attempted, double unavailable, double schema = 1) => new(schema, attempted, unavailable);

    private static ServiceCurrentUpdate Discovery(ServiceAttemptProgressWire? attempts, double? completed = 10, double? total = 50,
        double attempt = 1, string at = "2026-09-28T15:00:00Z") =>
        new("updating", ScrapeId: 42, OperationId: "op", PhaseId: ServiceInfoText.RegisteredBandDiscoveryPhaseId, PhaseAttempt: attempt,
            PhaseOrdinal: 9, UnitsKind: "accounts", UnitsCompleted: completed, UnitsTotal: total, LastProgressAt: at, AttemptProgress: attempts);

    [Fact]
    public void NormalizeAttemptProgress_ValidatesLikeTheWeb()
    {
        Assert.Equal(new ServiceAttemptProgress(12, 1), ServiceProgressReducer.NormalizeAttemptProgress(Attempts(12, 1)));
        Assert.Equal(new ServiceAttemptProgress(0, 0), ServiceProgressReducer.NormalizeAttemptProgress(Attempts(0, 0)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(null));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(Attempts(12, 1, schema: 2)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(new ServiceAttemptProgressWire(null, 12, 1)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(new ServiceAttemptProgressWire(1, null, 1)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(new ServiceAttemptProgressWire(1, 12, null)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(Attempts(double.NaN, 1)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(Attempts(12, double.PositiveInfinity)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(Attempts(12.5, 1)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(Attempts(12, 0.5)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(Attempts(-1, 0)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(Attempts(5, -1)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(Attempts(1, 2)));
        Assert.Null(ServiceProgressReducer.NormalizeAttemptProgress(Attempts(1e15, 0)));
        Assert.Equal(new ServiceAttemptProgress(999_999_999_999_999, 0), ServiceProgressReducer.NormalizeAttemptProgress(Attempts(999_999_999_999_999, 0)));
    }

    [Fact]
    public void Reduce_AttemptProgressNeverMovesBackwardsWithinAPhaseAttempt()
    {
        var (first, memory) = ServiceProgressReducer.Reduce(null, Info(Discovery(Attempts(12, 3))));
        Assert.Equal(new ServiceAttemptProgress(12, 3), first.AttemptProgress);
        Assert.Equal((10.0, 50.0), (first.UnitsCompleted!.Value, first.UnitsTotal!.Value));

        // A lower count in the same attempt keeps each count's high-water mark.
        var (second, memory2) = ServiceProgressReducer.Reduce(memory, Info(Discovery(Attempts(15, 1), at: "2026-09-28T15:00:05Z")));
        Assert.Equal(new ServiceAttemptProgress(15, 3), second.AttemptProgress);

        // Invalid counts hide the line rather than keeping or inventing numbers.
        var (invalid, _) = ServiceProgressReducer.Reduce(memory2, Info(Discovery(Attempts(1, 2), at: "2026-09-28T15:00:06Z")));
        Assert.Null(invalid.AttemptProgress);

        // A retried attempt starts again from the new counts.
        var (retry, _) = ServiceProgressReducer.Reduce(memory2, Info(Discovery(Attempts(2, 0), attempt: 2, at: "2026-09-28T15:00:07Z")));
        Assert.Equal(new ServiceAttemptProgress(2, 0), retry.AttemptProgress);

        // Another phase does not inherit counts.
        var (other, _) = ServiceProgressReducer.Reduce(memory2, Info(Updating(at: "2026-09-28T15:00:08Z") with { AttemptProgress = Attempts(1, 0) }));
        Assert.Equal(new ServiceAttemptProgress(1, 0), other.AttemptProgress);
    }

    [Fact]
    public void Wire_DecodesAttemptProgress()
    {
        var info = System.Text.Json.JsonSerializer.Deserialize(
            """{"currentUpdate":{"status":"updating","attemptProgress":{"schemaVersion":1,"attemptedThisPass":12,"retryableUnavailableThisPass":1}}}""",
            ServiceInfoJsonContext.Default.ServiceInfo)!;
        Assert.Equal(new ServiceAttemptProgressWire(1, 12, 1), info.CurrentUpdate!.AttemptProgress);
    }

    [Fact]
    public void Format_PrintsLikeJavaScript()
    {
        Assert.Equal("42", ServiceProgressReducer.Format(42));
        Assert.Equal("1.5", ServiceProgressReducer.Format(1.5));
    }
    #endregion

    #region Text
    [Theory]
    [InlineData(null, "idle", ServiceProcessState.Stopped, "Leaderboard Updater Unavailable")]
    [InlineData("stale", "failed", ServiceProcessState.Stopped, "Last Leaderboard Update Failed")]
    [InlineData("offline", "stalled", ServiceProcessState.Stopped, "Leaderboard Update Stalled")]
    [InlineData("online", "idle", ServiceProcessState.Idle, "Waiting for the Next Update")]
    [InlineData("online", "updating", ServiceProcessState.Updating, "Leaderboard Update in Progress")]
    [InlineData("starting", "brandNew", ServiceProcessState.Idle, "Brand New")]
    public void States(string? worker, string status, ServiceProcessState state, string sentence)
    {
        var info = Info(new ServiceCurrentUpdate(status), worker);
        Assert.Equal(state, ServiceInfoText.ProcessState(info));
        Assert.Equal(sentence, ServiceInfoText.ServiceState(info, state));
    }

    [Fact]
    public void Labels()
    {
        Assert.Equal(["Loading", "Updating", "Idle", "Stopped"], Enum.GetValues<ServiceProcessState>().Select(s => s.Label()));
        var empty = ServiceProgressDisplay.Empty;
        Assert.Equal("Waiting for the next update", ServiceInfoText.PhaseLabel(Info(new ServiceCurrentUpdate("idle")), empty));
        Assert.Equal("Computing Rankings", ServiceInfoText.PhaseLabel(Info(Updating()), empty with { PhaseId = "post.compute_rankings" }));
        var plan = new ServicePhasePlan("v1", [new ServicePhaseDescriptor("post.new_thing", "Shiny New Thing")]);
        Assert.Equal("Shiny New Thing", ServiceInfoText.PhaseLabel(Info(Updating(), plan: plan), empty with { PhaseId = "post.new_thing" }));
        Assert.Equal("Post Other Thing", ServiceInfoText.PhaseLabel(Info(Updating()), empty with { PhaseId = "post.other_thing" }));
        Assert.Equal("Waiting for progress", ServiceInfoText.PhaseLabel(Info(new ServiceCurrentUpdate("updating")), empty));

        Assert.Equal("Calculating Instrument Rankings", ServiceInfoText.SubphaseLabel(Info(Updating()), empty with { SubphaseId = "per_instrument_rankings" }));
        Assert.Equal("Cleaning Pro Lead Rank History", ServiceInfoText.SubphaseLabel(Info(Updating()), empty with { SubphaseId = "cleanup_rank_history_Solo_PeripheralGuitar" }));
        Assert.Equal("Cleaning Band Duets Rank History", ServiceInfoText.SubphaseLabel(Info(Updating()), empty with { SubphaseId = "cleanup_band_rank_history_band_duets" }));
        Assert.Null(ServiceInfoText.DynamicSubphaseLabel("cleanup_rank_history_"));
        Assert.Null(ServiceInfoText.SubphaseLabel(Info(new ServiceCurrentUpdate("updating", SubOperation: "updating")), empty));
        Assert.Null(ServiceInfoText.SubphaseLabel(Info(new ServiceCurrentUpdate("updating")), empty));
        Assert.Equal("Mystery Step", ServiceInfoText.SubphaseLabel(Info(new ServiceCurrentUpdate("updating", SubOperation: "mysteryStep")), empty));

        Assert.Equal("Computing Rankings · Saving", ServiceInfoText.PhaseTitle("Computing Rankings", "Saving"));
        Assert.Equal("Checkpoint", ServiceInfoText.PhaseTitle("Checkpoint", " checkpoint "));
        Assert.Equal("Checkpoint", ServiceInfoText.PhaseTitle("Checkpoint", null));
        Assert.Equal("A B2 C", ServiceInfoText.FallbackLabel("a.b2_c"));
        Assert.Equal("Phase Id Value", ServiceInfoText.FallbackLabel("phaseIdValue"));
    }

    [Fact]
    public void ProgressAndUnits()
    {
        var bar = new ServiceBarProgress("x", null, 0, ServiceBarKind.Exact, 42.25, "band_types", 1234, 5000);
        Assert.Equal("42.3%", ServiceInfoText.ProgressText(bar));
        Assert.Equal("1,234 of 5,000 band types completed", ServiceInfoText.UnitsText(bar));
        Assert.Equal("7 Widgets completed", ServiceInfoText.UnitsText(bar with { UnitsKind = "widgets", UnitsCompleted = 7, UnitsTotal = null }));
        Assert.Equal("7 items completed", ServiceInfoText.UnitsText(bar with { UnitsKind = null, UnitsCompleted = 7, UnitsTotal = null }));
        Assert.Null(ServiceInfoText.UnitsText(bar with { UnitsCompleted = null }));
        Assert.Equal(ServiceInfoText.ProgressIndeterminate, ServiceInfoText.ProgressText(bar with { Kind = ServiceBarKind.Indeterminate }));
        Assert.Equal(ServiceInfoText.ProgressIndeterminate, ServiceInfoText.ProgressText(null));
    }

    [Fact]
    public void DiscoveryAttemptText_MatchesTheWeb()
    {
        var display = ServiceProgressDisplay.Empty with
        {
            PhaseId = ServiceInfoText.RegisteredBandDiscoveryPhaseId,
            AttemptProgress = new ServiceAttemptProgress(12_345, 1),
            UnitsCompleted = 1_240,
            UnitsTotal = 5_000,
        };
        Assert.Equal("12,345 attempted this pass · 1 temporarily unavailable · 1,240 of 5,000 completed", ServiceInfoText.DiscoveryAttemptText(display));
        Assert.Equal("12,345 attempted this pass · 1 temporarily unavailable · 1,240 completed",
            ServiceInfoText.DiscoveryAttemptText(display with { UnitsTotal = null }));
        Assert.Equal("12,345 attempted this pass · 1 temporarily unavailable · 0 completed",
            ServiceInfoText.DiscoveryAttemptText(display with { UnitsCompleted = null, UnitsTotal = null }));
        Assert.Null(ServiceInfoText.DiscoveryAttemptText(display with { AttemptProgress = null }));
        Assert.Null(ServiceInfoText.DiscoveryAttemptText(display with { PhaseId = "post.compute_rankings" }));
    }

    [Theory]
    [InlineData(1.0, false)]
    [InlineData(1.49, false)]
    [InlineData(1.5, true)]
    [InlineData(2.25, true)]
    public void StateRowStacksAtLargeText(double scale, bool stacked) => Assert.Equal(stacked, ServiceInfoText.StacksStateRow(scale));

    [Fact]
    public void PublicationTimeAndFreeze()
    {
        Assert.Equal("Sep 28, 2026, 3:04 PM UTC", ServiceInfoText.LastPublished(Info(Updating()), TimeZoneInfo.Utc));
        Assert.Equal(ServiceInfoText.PublicationUnavailable, ServiceInfoText.LastPublished(Info(Updating(), publishedAt: null)));
        Assert.Null(ServiceInfoText.ParseDate("not a date"));
        Assert.Null(ServiceInfoText.ParseDate(" "));
        var custom = TimeZoneInfo.CreateCustomTimeZone("Test", TimeSpan.FromHours(-7), "Test Zone", "Test Standard Time");
        Assert.Equal("TST", ServiceInfoText.ZoneAbbreviation(custom, DateTimeOffset.UtcNow));
        var odd = TimeZoneInfo.CreateCustomTimeZone("Odd", TimeSpan.FromHours(5.5), "Odd", "Oddtime");
        Assert.Equal("UTC+05:30", ServiceInfoText.ZoneAbbreviation(odd, new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.FromHours(5.5))));
        var west = TimeZoneInfo.CreateCustomTimeZone("West", TimeSpan.FromHours(-3), "West", "West");
        Assert.Equal("UTC−03:00", ServiceInfoText.ZoneAbbreviation(west, new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.FromHours(-3))));

        var info = Info(Updating());
        Assert.Null(ServiceInfoText.FreezeNotice(new ServiceInfoSnapshot(info, null)));
        Assert.StartsWith("Paused while new scores publish", ServiceInfoText.FreezeNotice(new ServiceInfoSnapshot(info, " scrape ")), StringComparison.Ordinal);
        var frozen = Info(Updating(), publication: new ServicePublicationState(null, true, "maintenance"));
        Assert.StartsWith("Paused for service maintenance", ServiceInfoText.FreezeNotice(new ServiceInfoSnapshot(frozen, "")), StringComparison.Ordinal);
        var frozenNoReason = Info(Updating(), publication: new ServicePublicationState(null, true, null));
        Assert.NotNull(ServiceInfoText.FreezeNotice(new ServiceInfoSnapshot(frozenNoReason, null)));
    }
    #endregion

    #region View model
    private const string UpdatingBody = """
        {"contractVersion":2,"postgresConnectionTarget":"secret","currentUpdate":{"status":"updating","scrapeId":42,"operationId":"op",
         "phaseId":"post.compute_rankings","subphaseId":"per_instrument_rankings","phaseAttempt":1,
         "subphaseProgress":{"schemaVersion":1,"id":"per_instrument_rankings","epoch":1,"sequence":3,"kind":"exact","unitsKind":"leaderboards","unitsCompleted":250,"unitsTotal":1000,"unitsTotalFinal":true,"percent":25}},
         "lastCompletedUpdate":{"publishedAt":"2026-09-28T15:04:05Z"},"workerStatus":{"status":"online"}}
        """;

    private static (FakeService Service, FakeTimeProvider Time, List<string> Paths) Fake(Func<HttpRequestMessage, HttpResponseMessage?> route)
    {
        var paths = new List<string>();
        var service = new FakeService
        {
            Override = r =>
            {
                lock (paths) paths.Add(r.RequestUri!.AbsolutePath);
                return route(r);
            },
        };
        return (service, new FakeTimeProvider(), paths);
    }

    [Fact]
    public void Apply_UpdatingAndFailure()
    {
        var vm = new SettingsServiceInfoViewModel(new FakeService().Client(), new FakeTimeProvider(), () => TimeZoneInfo.Utc);
        Assert.Equal(("Loading", ServiceProcessState.Loading, true), (vm.StateDescription, vm.ProcessState, vm.ShowsSpinner));
        Assert.Null(vm.LastPublished);
        Assert.False(vm.HasLastPublished);
        vm.Apply(new ServiceInfoSnapshot(Info(Updating(sub: Sub(250, 1000, 25))), "publish"));
        Assert.Equal("Computing Rankings", vm.StateDescription);
        Assert.Equal(("Updating", true), (vm.ProcessStateText, vm.ShowsSpinner));
        Assert.Equal("Computing Rankings · Calculating Instrument Rankings", vm.PhaseTitle);
        Assert.True(vm.HasPhase && vm.HasBar && !vm.IsIndeterminate && !vm.HasAttempt && vm.HasLastPublished);
        Assert.Equal((25.0, "25.0%", "250 of 1,000 leaderboards completed"), (vm.BarPercent, vm.ProgressText, vm.UnitsText));
        Assert.Equal("Computing Rankings · Calculating Instrument Rankings. 25.0%. 250 of 1,000 leaderboards completed", vm.PhaseAccessibleName);
        Assert.Equal("Sep 28, 2026, 3:04 PM UTC", vm.LastPublished);

        vm.Apply(new ServiceInfoSnapshot(Info(Updating(sub: Sub(1, 10, 10, final: false))), null));
        Assert.True(vm.IsIndeterminate);
        Assert.Equal(ServiceInfoText.ProgressIndeterminate, vm.ProgressText);

        vm.Apply(new ServiceInfoSnapshot(Info(new ServiceCurrentUpdate("idle")), null));
        Assert.Equal(("Waiting for the Next Update", ServiceProcessState.Idle, false, false), (vm.StateDescription, vm.ProcessState, vm.HasPhase, vm.HasBar));

        vm.ApplyFailure();
        Assert.Equal(("Failed to load data", ServiceProcessState.Stopped, null, false), (vm.StateDescription, vm.ProcessState, vm.LastPublished, vm.HasLastPublished));
        Assert.Equal("", vm.PhaseAccessibleName);
    }

    [Fact]
    public void Apply_DiscoveryPrintsTheAttemptLineAndSpeaksIt()
    {
        var vm = new SettingsServiceInfoViewModel(new FakeService().Client(), new FakeTimeProvider(), () => TimeZoneInfo.Utc);
        var sub = new ServiceSubphaseProgress(1, "discover_bands", 1, 1, "exact", "accounts", 1240, 5000, true, 24.8);
        vm.Apply(new ServiceInfoSnapshot(Info(Discovery(Attempts(12, 1), completed: 1240, total: 5000) with { SubphaseId = "discover_bands", SubphaseProgress = sub }), null));
        const string attempt = "12 attempted this pass · 1 temporarily unavailable · 1,240 of 5,000 completed";
        Assert.Equal(attempt, vm.AttemptText);
        Assert.True(vm.HasAttempt);
        Assert.EndsWith(". 24.8%. 1,240 of 5,000 accounts completed. " + attempt, vm.PhaseAccessibleName, StringComparison.Ordinal);

        vm.Apply(new ServiceInfoSnapshot(Info(new ServiceCurrentUpdate("idle")), null));
        Assert.False(vm.HasAttempt);
    }

    [Fact]
    public async Task Poll_EveryFiveSeconds_UntilStopped()
    {
        var (service, time, paths) = Fake(r => r.RequestUri!.AbsolutePath == "/api/service-info" ? Wire.Ok(UpdatingBody) : null);
        var vm = new SettingsServiceInfoViewModel(service.Client(), time);
        vm.Start();
        vm.Start();
        Assert.True(vm.IsPolling);
        await Async.Until(() => vm.ProcessState == ServiceProcessState.Updating);
        Assert.Equal(25, vm.BarPercent);
        Assert.Single(paths);
        await Async.Advance(time, TimeSpan.FromSeconds(5));
        await Async.Until(() => paths.Count == 2);
        vm.Background = true;
        await Async.Advance(time, TimeSpan.FromSeconds(5));
        await Async.Advance(time, TimeSpan.FromSeconds(5));
        Assert.Equal(3, paths.Count);
        vm.Background = true;
        vm.Background = false;
        await Async.Until(() => paths.Count == 4);
        vm.Stop();
        Assert.False(vm.IsPolling);
        await Async.Advance(time, TimeSpan.FromSeconds(10));
        Assert.Equal(4, paths.Count);
        Assert.All(service.Handler.Requests, r => Assert.DoesNotContain(r.Headers.Keys, k => k.StartsWith("x-fst-selected", StringComparison.OrdinalIgnoreCase)));
    }

    [Fact]
    public async Task Poll_FailuresAndTimeout()
    {
        var (service, time, _) = Fake(r => r.RequestUri!.AbsolutePath == "/api/service-info" ? Wire.Response(HttpStatusCode.InternalServerError) : null);
        var vm = new SettingsServiceInfoViewModel(service.Client(), time);
        await vm.PollOnceAsync(CancellationToken.None);
        Assert.Equal("Failed to load data", vm.StateDescription);

        var hang = new FakeService();
        hang.Handler.Responder = async (request, token) =>
        {
            await Task.Delay(Timeout.Infinite, token);
            return Wire.Ok("{}");
        };
        var slow = new SettingsServiceInfoViewModel(hang.Client(), time);
        var pending = slow.PollOnceAsync(CancellationToken.None);
        await Async.Advance(time, TimeSpan.FromSeconds(4));
        await pending;
        Assert.Equal(ServiceProcessState.Stopped, slow.ProcessState);

        using var stop = new CancellationTokenSource();
        var cancelled = new SettingsServiceInfoViewModel(hang.Client(), time);
        var pendingStop = cancelled.PollOnceAsync(stop.Token);
        stop.Cancel();
        await pendingStop;
        Assert.Equal(ServiceProcessState.Loading, cancelled.ProcessState);
    }

    [Theory]
    [InlineData("""{"contractVersion":2}""")]
    [InlineData("""{"currentUpdate":{"status":""}}""")]
    [InlineData("""not json""")]
    public async Task ServiceInfo_RejectsMalformedBodies(string body)
    {
        var (service, _, _) = Fake(_ => Wire.Ok(body));
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetServiceInfoAsync());
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, error.Kind);
    }

    [Fact]
    public async Task ServiceInfo_CapturesFreezeHeader()
    {
        var (service, _, _) = Fake(_ => Wire.Ok(UpdatingBody, (ServiceFreezeReason.Header, "scrape")));
        var snapshot = await service.Client().GetServiceInfoAsync();
        Assert.Equal("scrape", snapshot.FreezeReasonHeader);
        Assert.Equal("updating", snapshot.Info.CurrentUpdate!.Status);
    }

    [Theory]
    [InlineData("""{"version":" 1.2.3 "}""", "1.2.3")]
    [InlineData("""{"version":""}""", null)]
    [InlineData("""{"version":"bad\u0001"}""", null)]
    [InlineData("""{}""", null)]
    public async Task ServiceVersion_Validates(string body, string? expected)
    {
        var (service, _, _) = Fake(_ => Wire.Ok(body));
        if (expected is null)
            await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetServiceVersionAsync());
        else
            Assert.Equal(expected, await service.Client().GetServiceVersionAsync());
    }

    [Fact]
    public async Task Settings_ActivateReadsVersionOnceAndPolls()
    {
        var versionCalls = 0;
        var (service, time, paths) = Fake(r => r.RequestUri!.AbsolutePath switch
        {
            "/api/version" => Interlocked.Increment(ref versionCalls) == 1 ? Wire.Response(HttpStatusCode.ServiceUnavailable) : Wire.Ok("""{"version":"9.9.9"}"""),
            "/api/service-info" => Wire.Ok(UpdatingBody),
            _ => null,
        });
        var vm = new SettingsViewModel(service.Session(time), "1.0.0");
        vm.Activate();
        await Async.Until(() => vm.ServiceVersion == "Unavailable");
        Assert.True(vm.ServiceInfo.IsPolling);
        vm.Deactivate();
        Assert.False(vm.ServiceInfo.IsPolling);
        vm.Activate();
        await Async.Until(() => vm.ServiceVersion == "9.9.9");
        vm.Activate();
        await Async.Settle();
        Assert.Equal(2, versionCalls);
        vm.Deactivate();
        Assert.Equal("https://festivalscoretracker.com", vm.ServiceOrigin);
        Assert.Contains(vm.QuickLinks.Items, i => i.Section.Id == "service-info" && i.Section.Title == "Service Info");
    }
    #endregion
}
