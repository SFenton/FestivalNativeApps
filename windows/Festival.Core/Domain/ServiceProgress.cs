using System.Globalization;
using System.Text;

namespace Festival.Core.Domain;

#region Progress reduction
/// <summary>How a progress bar renders.</summary>
public enum ServiceBarKind
{
    /// <summary>Determinate percent.</summary>
    Exact,
    /// <summary>Total not yet known.</summary>
    Indeterminate,
    /// <summary>No bar for this subphase.</summary>
    NotApplicable,
}

/// <summary>Monotonic bar state (web <c>ServiceBarProgress</c>).</summary>
/// <param name="Identity">Operation/phase/attempt/subphase/epoch identity.</param>
/// <param name="Id">Subphase ID.</param>
/// <param name="Sequence">Sequence within the identity.</param>
/// <param name="Kind">Bar kind.</param>
/// <param name="Percent">0–100 when <see cref="ServiceBarKind.Exact"/>.</param>
/// <param name="UnitsKind">Unit kind.</param>
/// <param name="UnitsCompleted">Completed units.</param>
/// <param name="UnitsTotal">Total units.</param>
public sealed record ServiceBarProgress(
    string Identity, string? Id, double Sequence, ServiceBarKind Kind, double? Percent,
    string? UnitsKind, double? UnitsCompleted, double? UnitsTotal);

/// <summary>Validated band discovery attempt counts (web <c>ServiceAttemptProgress</c>).</summary>
/// <param name="AttemptedThisPass">Accounts attempted in this pass.</param>
/// <param name="RetryableUnavailableThisPass">Attempted accounts that were temporarily unavailable (never more than attempted).</param>
public sealed record ServiceAttemptProgress(long AttemptedThisPass, long RetryableUnavailableThisPass);

/// <summary>What the Service Info card renders for one poll (web <c>ServiceProgressDisplay</c>).</summary>
public sealed record ServiceProgressDisplay
{
    /// <summary>Nothing running.</summary>
    public static ServiceProgressDisplay Empty { get; } = new();

    /// <summary>Phase percent (monotonic within an attempt).</summary>
    public double? PhasePercent { get; init; }

    /// <summary>Phase ID.</summary>
    public string? PhaseId { get; init; }

    /// <summary>Phase-level completed units (finite), used by the discovery attempt line.</summary>
    public double? UnitsCompleted { get; init; }

    /// <summary>Phase-level total units (finite), used by the discovery attempt line.</summary>
    public double? UnitsTotal { get; init; }

    /// <summary>Attempt counts (monotonic within a phase attempt), when valid.</summary>
    public ServiceAttemptProgress? AttemptProgress { get; init; }

    /// <summary>Subphase ID.</summary>
    public string? SubphaseId { get; init; }

    /// <summary>Attempt.</summary>
    public double? PhaseAttempt { get; init; }

    /// <summary>Ordinal.</summary>
    public double? PhaseOrdinal { get; init; }

    /// <summary>Whether this poll restarted the phase.</summary>
    public bool Restarted { get; init; }

    /// <summary>Whether an out-of-order payload was ignored.</summary>
    public bool StalePayloadIgnored { get; init; }

    /// <summary>Bar.</summary>
    public ServiceBarProgress? BarProgress { get; init; }
}

/// <summary>Memory carried between polls so progress never moves backwards within one phase attempt.</summary>
/// <param name="OperationIdentity">Operation identity.</param>
/// <param name="PhaseId">Phase.</param>
/// <param name="PhaseAttempt">Attempt.</param>
/// <param name="PhaseOrdinal">Ordinal.</param>
/// <param name="LastProgressTimestamp">Newest progress timestamp seen.</param>
/// <param name="Display">Last display.</param>
public sealed record ServiceProgressMemory(
    string? OperationIdentity, string? PhaseId, double? PhaseAttempt, double? PhaseOrdinal,
    DateTimeOffset? LastProgressTimestamp, ServiceProgressDisplay Display);

/// <summary>
/// Port of the web's <c>reduceServiceProgress</c> (<c>pages/settings/serviceProgress.ts</c>, via Apple
/// <c>ServiceProgressReducer</c>): percentages are clamped and monotonic within an operation/phase/attempt, stale
/// out-of-order payloads are ignored, and a restarted attempt resets the bar.
/// </summary>
public static class ServiceProgressReducer
{
    /// <summary>Reduces one poll against the previous memory.</summary>
    /// <param name="previous">Memory from the last poll.</param>
    /// <param name="info">New body.</param>
    /// <returns>Display for this poll and memory for the next.</returns>
    public static (ServiceProgressDisplay Display, ServiceProgressMemory Memory) Reduce(ServiceProgressMemory? previous, ServiceInfo info)
    {
        var current = info.CurrentUpdate ?? new ServiceCurrentUpdate("idle");
        var identity = OperationIdentity(info);
        if (current.Status != "updating")
            return (ServiceProgressDisplay.Empty, new ServiceProgressMemory(null, null, null, null, null, ServiceProgressDisplay.Empty));

        var isV2 = info.ContractVersion == 2 || current.ContractVersion == 2 || current.PhaseId is not null;
        var timestamp = ServiceInfoText.ParseDate(current.LastProgressAt ?? current.UpdatedAt ?? current.HeartbeatAt);
        var sameOperation = previous?.OperationIdentity is not null && previous.OperationIdentity == identity;
        var phaseId = current.PhaseId;
        var phaseAttempt = Finite(current.PhaseAttempt);
        var phaseOrdinal = Finite(current.PhaseOrdinal);
        var samePhase = sameOperation && previous!.PhaseId is not null && previous.PhaseId == phaseId;
        var attemptChanged = samePhase && previous!.PhaseAttempt is not null && phaseAttempt is not null && previous.PhaseAttempt != phaseAttempt;
        var ordinalRestart = sameOperation && previous!.PhaseOrdinal is not null && phaseOrdinal is not null && phaseOrdinal < previous.PhaseOrdinal;
        var restarted = attemptChanged || ordinalRestart;

        if (previous is not null && sameOperation && !restarted && timestamp is { } stamp &&
            previous.LastProgressTimestamp is { } last && stamp < last)
        {
            var kept = previous.Display with { StalePayloadIgnored = true, Restarted = false };
            return (kept, previous with { Display = kept });
        }

        var unitsTotalFinal = isV2 && current.UnitsTotalFinal == true;
        var rawPhasePercent = unitsTotalFinal ? Clamp(Finite(current.PhasePercent)) : null;
        var previousPhasePercent = samePhase && !restarted ? previous!.Display.PhasePercent : null;
        double? phasePercent = rawPhasePercent is { } raw ? Math.Max(raw, previousPhasePercent ?? raw) : null;
        var previousAttempt = samePhase && !restarted ? previous!.Display.AttemptProgress : null;
        var attemptProgress = NormalizeAttemptProgress(current.AttemptProgress) is { } attempts
            ? new ServiceAttemptProgress(
                Math.Max(previousAttempt?.AttemptedThisPass ?? 0, attempts.AttemptedThisPass),
                Math.Max(previousAttempt?.RetryableUnavailableThisPass ?? 0, attempts.RetryableUnavailableThisPass))
            : null;

        var display = new ServiceProgressDisplay
        {
            PhasePercent = phasePercent,
            PhaseId = phaseId,
            UnitsCompleted = Finite(current.UnitsCompleted),
            UnitsTotal = Finite(current.UnitsTotal),
            AttemptProgress = attemptProgress,
            SubphaseId = current.SubphaseId,
            PhaseAttempt = phaseAttempt,
            PhaseOrdinal = phaseOrdinal,
            Restarted = restarted,
            BarProgress = ReduceBar(previous?.Display.BarProgress, info, current, identity, phaseId, phaseAttempt, phasePercent),
        };
        return (display, new ServiceProgressMemory(identity, phaseId, phaseAttempt, phaseOrdinal,
            timestamp ?? previous?.LastProgressTimestamp, display));
    }

    /// <summary>Stable identity of the running operation (<c>scrapeId:operationId:planVersion</c>).</summary>
    /// <param name="info">Body.</param>
    /// <returns>Identity, or <see langword="null"/> when neither a scrape nor an operation ID is known.</returns>
    public static string? OperationIdentity(ServiceInfo info)
    {
        var current = info.CurrentUpdate;
        var scrapeId = current?.ScrapeId ?? info.ActiveScrapeId;
        if (scrapeId is null && current?.OperationId is null) return null;
        return string.Join(':',
            scrapeId is { } id ? Format(id) : current?.StartedAt ?? "none",
            current?.OperationId ?? "legacy",
            current?.PhasePlanVersion ?? info.PhasePlan?.Version ?? "unversioned");
    }

    /// <summary>Reduces the bar for one poll.</summary>
    /// <param name="previous">Previous bar.</param>
    /// <param name="info">Body.</param>
    /// <param name="current">Current update.</param>
    /// <param name="identity">Operation identity.</param>
    /// <param name="phaseId">Phase.</param>
    /// <param name="phaseAttempt">Attempt.</param>
    /// <param name="phasePercent">Phase percent.</param>
    /// <returns>Bar.</returns>
    private static ServiceBarProgress ReduceBar(
        ServiceBarProgress? previous, ServiceInfo info, ServiceCurrentUpdate current, string? identity, string? phaseId,
        double? phaseAttempt, double? phasePercent)
    {
        _ = info;
        string[] prefix = [identity ?? "none", phaseId ?? "none", phaseAttempt is { } a ? Format(a) : "none"];
        if (current.SubphaseProgress is { } raw)
        {
            var epoch = Finite(raw.Epoch) ?? 0;
            var sequence = Finite(raw.Sequence) ?? 0;
            var expectedId = current.SubphaseId;
            var id = raw.Id ?? expectedId;
            var barIdentity = string.Join(':', [.. prefix, id ?? "none", Format(epoch)]);
            var sameIdentity = previous?.Identity == barIdentity;
            if (previous is not null && sameIdentity && sequence < previous.Sequence) return previous;

            var supported = raw.SchemaVersion == 1;
            var matching = expectedId is null || id == expectedId;
            var kind = ServiceBarKind.Indeterminate;
            if (supported && matching && raw.Kind is "exact" or "not_applicable")
                kind = raw.Kind == "exact" ? ServiceBarKind.Exact : ServiceBarKind.NotApplicable;
            var completed = Finite(raw.UnitsCompleted);
            var total = Finite(raw.UnitsTotal);
            double? exactPercent = null;
            if (kind == ServiceBarKind.Exact && raw.UnitsTotalFinal == true && total is > 0 &&
                completed is { } done && done >= 0 && done <= total)
                exactPercent = Clamp(Finite(raw.Percent));
            if (kind == ServiceBarKind.Exact && exactPercent is null) kind = ServiceBarKind.Indeterminate;
            var percent = exactPercent;
            if (kind == ServiceBarKind.Exact && sameIdentity && previous!.Percent is { } prior && exactPercent is { } value)
                percent = Math.Max(prior, value);
            var exact = kind == ServiceBarKind.Exact;
            return new ServiceBarProgress(barIdentity, id, sequence, kind, percent,
                exact ? raw.UnitsKind : null, exact ? completed : null, exact ? total : null);
        }
        if (current.SubphaseId is { } subphaseId)
            return new ServiceBarProgress(string.Join(':', [.. prefix, subphaseId, "legacy"]), subphaseId, 0,
                ServiceBarKind.Indeterminate, null, null, null, null);
        return new ServiceBarProgress(string.Join(':', [.. prefix, "phase"]), null, 0,
            phasePercent is not null ? ServiceBarKind.Exact : ServiceBarKind.Indeterminate, phasePercent,
            current.UnitsKind, Finite(current.UnitsCompleted), Finite(current.UnitsTotal));
    }

    /// <summary>
    /// Web <c>normalizeAttemptProgress</c>: schema 1, finite whole non-negative counts, unavailable never above
    /// attempted, and counts small enough to stay exact.
    /// </summary>
    /// <param name="value">Wire counts.</param>
    /// <returns>Validated counts, or <see langword="null"/> when any rule fails.</returns>
    public static ServiceAttemptProgress? NormalizeAttemptProgress(ServiceAttemptProgressWire? value)
    {
        if (value?.SchemaVersion != 1) return null;
        if (Finite(value.AttemptedThisPass) is not { } attempted || Finite(value.RetryableUnavailableThisPass) is not { } unavailable)
            return null;
        if (attempted != Math.Floor(attempted) || unavailable != Math.Floor(unavailable)) return null;
        if (attempted < 0 || unavailable < 0 || unavailable > attempted || attempted >= MaxCount) return null;
        return new ServiceAttemptProgress((long)attempted, (long)unavailable);
    }

    /// <summary>Counts at or above this cannot be represented exactly and are rejected.</summary>
    private const double MaxCount = 1e15;

    /// <summary>Drops NaN/∞.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Finite value or <see langword="null"/>.</returns>
    private static double? Finite(double? value) => value is { } v && double.IsFinite(v) ? v : null;

    /// <summary>Clamps to 0–100.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Clamped value.</returns>
    private static double? Clamp(double? value) => value is { } v ? Math.Clamp(v, 0, 100) : null;

    /// <summary>Integral doubles print without a decimal point, as JavaScript would.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Text.</returns>
    internal static string Format(double value) =>
        value == Math.Round(value) && Math.Abs(value) < 1e15
            ? ((long)value).ToString(CultureInfo.InvariantCulture)
            : value.ToString(CultureInfo.InvariantCulture);
}
#endregion

#region Presentation
/// <summary>Worker/process state shown beside "Leaderboard Service State".</summary>
public enum ServiceProcessState
{
    /// <summary>First read pending.</summary>
    Loading,
    /// <summary>An update is running.</summary>
    Updating,
    /// <summary>Waiting for the next update.</summary>
    Idle,
    /// <summary>Worker missing, offline, stale or stopping (or the read failed).</summary>
    Stopped,
}

/// <summary>Copy and label rules for the Service Info card (web <c>SettingsServiceProgress.tsx</c> + <c>serviceInfo.en.json</c>).</summary>
public static class ServiceInfoText
{
    /// <summary>Section title.</summary>
    public const string Title = "Service Info";

    /// <summary>Section hint.</summary>
    public const string Hint = "Live leaderboard update status, exact phase progress when available, and publication timing.";

    /// <summary>First row title.</summary>
    public const string ServiceStateTitle = "Leaderboard Service State";

    /// <summary>Publication row title.</summary>
    public const string LastPublishedTitle = "Last Successful Publication";

    /// <summary>No publication yet.</summary>
    public const string PublicationUnavailable = "No successful publication yet";

    /// <summary>Unknown-total caption.</summary>
    public const string ProgressIndeterminate = "In progress — total not yet known";

    /// <summary>Title Case state label.</summary>
    /// <param name="state">State.</param>
    /// <returns>Label.</returns>
    public static string Label(this ServiceProcessState state) => state switch
    {
        ServiceProcessState.Loading => "Loading",
        ServiceProcessState.Updating => "Updating",
        ServiceProcessState.Idle => "Idle",
        _ => "Stopped",
    };

    /// <summary>Stopped when the worker is missing/offline/stale/stopping, else updating or idle.</summary>
    /// <param name="info">Body.</param>
    /// <returns>State.</returns>
    public static ServiceProcessState ProcessState(ServiceInfo info) => info.WorkerStatus?.Status switch
    {
        null or "offline" or "stale" or "stopping" => ServiceProcessState.Stopped,
        _ => info.CurrentUpdate?.Status == "updating" ? ServiceProcessState.Updating : ServiceProcessState.Idle,
    };

    private static readonly Dictionary<string, string> ServiceStates = new(StringComparer.Ordinal)
    {
        ["idle"] = "Waiting for the Next Update",
        ["updating"] = "Leaderboard Update in Progress",
        ["failed"] = "Last Leaderboard Update Failed",
        ["stalled"] = "Leaderboard Update Stalled",
        ["unavailable"] = "Leaderboard Updater Unavailable",
    };

    /// <summary>Human description of the update status (used when not actively updating).</summary>
    /// <param name="info">Body.</param>
    /// <param name="state">Resolved state.</param>
    /// <returns>Sentence.</returns>
    public static string ServiceState(ServiceInfo info, ServiceProcessState state)
    {
        var status = info.CurrentUpdate?.Status ?? "";
        if (state == ServiceProcessState.Stopped && status is not ("failed" or "stalled")) return ServiceStates["unavailable"];
        return ServiceStates.TryGetValue(status, out var label) ? label : FallbackLabel(status);
    }

    /// <summary>Phase label: "Waiting for the next update" when idle, else the phase name.</summary>
    /// <param name="info">Body.</param>
    /// <param name="display">Reduced progress.</param>
    /// <returns>Label.</returns>
    public static string PhaseLabel(ServiceInfo info, ServiceProgressDisplay display)
    {
        var current = info.CurrentUpdate;
        if (current?.Status == "idle") return "Waiting for the next update";
        var descriptor = info.PhasePlan?.Phases?.FirstOrDefault(p => p.Id == display.PhaseId);
        return StableLabel(PhaseLabels, display.PhaseId, descriptor?.Label ?? current?.Phase) ?? "Waiting for progress";
    }

    /// <summary>Subphase label, or <see langword="null"/> when none or it only repeats the status.</summary>
    /// <param name="info">Body.</param>
    /// <param name="display">Reduced progress.</param>
    /// <returns>Label.</returns>
    public static string? SubphaseLabel(ServiceInfo info, ServiceProgressDisplay display)
    {
        var current = info.CurrentUpdate;
        var subphaseId = display.SubphaseId ?? current?.SubOperation;
        if (subphaseId is null || subphaseId == current?.Status) return null;
        return DynamicSubphaseLabel(subphaseId)
            ?? StableLabel(SubphaseLabels, subphaseId, FallbackLabel(current?.SubOperation ?? subphaseId));
    }

    /// <summary>"Phase · Subphase", dropping a subphase that repeats the phase.</summary>
    /// <param name="phase">Phase.</param>
    /// <param name="subphase">Subphase.</param>
    /// <returns>Title.</returns>
    public static string PhaseTitle(string phase, string? subphase) =>
        subphase is null || string.Equals(subphase.Trim(), phase.Trim(), StringComparison.OrdinalIgnoreCase)
            ? phase
            : $"{phase} · {subphase}";

    /// <summary>Units line under the bar ("1,234 of 5,000 leaderboards completed").</summary>
    /// <param name="progress">Bar.</param>
    /// <returns>Sentence or <see langword="null"/>.</returns>
    public static string? UnitsText(ServiceBarProgress? progress)
    {
        if (progress?.UnitsCompleted is not { } completed) return null;
        var unit = StableLabel(UnitLabels, progress.UnitsKind, progress.UnitsKind is { } kind ? FallbackLabel(kind) : null) ?? "items";
        return progress.UnitsTotal is { } total
            ? $"{Grouped(completed)} of {Grouped(total)} {unit} completed"
            : $"{Grouped(completed)} {unit} completed";
    }

    /// <summary>Windows text size at and above which the process state stacks under its label.</summary>
    public const double StackedStateTextScale = 1.5;

    /// <summary>
    /// Whether the "Leaderboard Service State" row stacks its process state under the label (Apple's accessibility-size
    /// rule; the shell uses the same 150% threshold) instead of squeezing the label beside it.
    /// </summary>
    /// <param name="textScale">Windows text size factor (1–2.25).</param>
    /// <returns><see langword="true"/> at 150% text and above.</returns>
    public static bool StacksStateRow(double textScale) => textScale >= StackedStateTextScale;

    /// <summary>Phase whose row adds the lookup-attempt line (web <c>discoveryAttemptText</c>).</summary>
    public const string RegisteredBandDiscoveryPhaseId = "post.registered_player_band_discovery";

    /// <summary>
    /// Band discovery attempt line (web <c>discoveryAttemptText</c>): "12 attempted this pass · 1 temporarily
    /// unavailable · 10 of 50 completed", or "… · 10 completed" without a total.
    /// </summary>
    /// <param name="display">Reduced progress.</param>
    /// <returns>Sentence, or <see langword="null"/> outside band discovery or without valid counts.</returns>
    public static string? DiscoveryAttemptText(ServiceProgressDisplay display)
    {
        if (display.PhaseId != RegisteredBandDiscoveryPhaseId || display.AttemptProgress is not { } attempts) return null;
        var head = $"{Grouped(attempts.AttemptedThisPass)} attempted this pass · {Grouped(attempts.RetryableUnavailableThisPass)} temporarily unavailable · ";
        var completed = Grouped(display.UnitsCompleted ?? 0);
        return display.UnitsTotal is { } total
            ? $"{head}{completed} of {Grouped(total)} completed"
            : $"{head}{completed} completed";
    }

    /// <summary>Percent text for a determinate bar, else the indeterminate sentence.</summary>
    /// <param name="progress">Bar.</param>
    /// <returns>"42.5%" or the indeterminate caption.</returns>
    public static string ProgressText(ServiceBarProgress? progress) =>
        progress is { Kind: ServiceBarKind.Exact, Percent: { } percent }
            ? percent.ToString("0.0", CultureInfo.InvariantCulture) + "%"
            : ProgressIndeterminate;

    /// <summary>Last successful publication time, e.g. "Sep 28, 2026, 3:04 PM PDT".</summary>
    /// <param name="info">Body.</param>
    /// <param name="zone">Display zone (fixed in tests).</param>
    /// <returns>Text.</returns>
    public static string LastPublished(ServiceInfo info, TimeZoneInfo? zone = null)
    {
        if (ParseDate(info.LastCompletedUpdate?.PublishedAt ?? info.Publication?.PublishedAt) is not { } date)
            return PublicationUnavailable;
        zone ??= TimeZoneInfo.Local;
        var local = TimeZoneInfo.ConvertTime(date, zone);
        var english = CultureInfo.GetCultureInfo("en-US");
        return local.ToString("MMM d, yyyy, h:mm tt", english) + " " + ZoneAbbreviation(zone, local);
    }

    /// <summary>Freeze explanation from the header first, then the body.</summary>
    /// <param name="snapshot">Read.</param>
    /// <returns>Sentence while public reads are frozen, else <see langword="null"/>.</returns>
    public static string? FreezeNotice(ServiceInfoSnapshot snapshot)
    {
        var header = snapshot.FreezeReasonHeader?.Trim();
        var body = snapshot.Info.Publication;
        var reason = header is { Length: > 0 } ? header : body?.PublicReadsFrozen == true ? body.FreezeReason ?? "" : null;
        if (reason is null) return null;
        return ServiceFreezeReason.IsScoreUpdate(reason)
            ? "Paused while new scores publish. Pages show the last publication."
            : "Paused for service maintenance. Pages show the last publication.";
    }

    /// <summary>Parses an ISO-8601 timestamp (tolerates .NET's seven fractional digits).</summary>
    /// <param name="value">Text.</param>
    /// <returns>Instant or <see langword="null"/>.</returns>
    public static DateTimeOffset? ParseDate(string? value) =>
        DateTimeOffset.TryParse(value?.Trim(), CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var parsed) && value!.Trim().Length > 0
            ? parsed
            : null;

    /// <summary>Web <c>fallbackLabel</c>: <c>.</c>/<c>_</c> → space, split camelCase, capitalize word starts.</summary>
    /// <param name="id">Identifier.</param>
    /// <returns>Label.</returns>
    public static string FallbackLabel(string id)
    {
        var spaced = new StringBuilder();
        char? previous = null;
        foreach (var raw in id)
        {
            var mapped = raw is '.' or '_' ? ' ' : raw;
            if (previous is { } p && char.IsUpper(mapped) && (char.IsLower(p) || char.IsDigit(p))) spaced.Append(' ');
            spaced.Append(mapped);
            previous = mapped;
        }
        var result = new StringBuilder();
        var atWordStart = true;
        foreach (var c in spaced.ToString())
        {
            var isWord = char.IsLetterOrDigit(c);
            result.Append(atWordStart && isWord ? char.ToUpperInvariant(c) : c);
            atWordStart = !isWord;
        }
        return result.ToString().Trim();
    }

    /// <summary><c>cleanup_rank_history_&lt;scope&gt;</c> / <c>cleanup_band_rank_history_&lt;scope&gt;</c> patterns.</summary>
    /// <param name="id">Subphase ID.</param>
    /// <returns>Label or <see langword="null"/>.</returns>
    internal static string? DynamicSubphaseLabel(string id)
    {
        var normalized = id.Trim();
        string[] prefixes = ["cleanup_band_rank_history_", "cleanup_rank_history_"];
        var prefix = prefixes.FirstOrDefault(p => normalized.StartsWith(p, StringComparison.OrdinalIgnoreCase));
        if (prefix is null) return null;
        var suffix = normalized[prefix.Length..];
        if (suffix.Length == 0) return null;
        var instrument = InstrumentInfo.All.FirstOrDefault(i => i.ServiceId() == suffix, (Instrument)(-1));
        var scope = instrument >= 0 ? instrument.Label() : FallbackLabel(suffix);
        return $"Cleaning {scope} Rank History";
    }

    /// <summary>Looks up a stable ID (<c>.</c>/<c>-</c> → <c>_</c>) in a label table.</summary>
    /// <param name="table">Labels.</param>
    /// <param name="id">ID.</param>
    /// <param name="fallback">Fallback.</param>
    /// <returns>Label.</returns>
    private static string? StableLabel(Dictionary<string, string> table, string? id, string? fallback)
    {
        if (id is null) return fallback;
        var key = id.Replace('.', '_').Replace('-', '_');
        if (table.TryGetValue(key, out var label)) return label;
        return fallback is { Length: > 0 } ? fallback : FallbackLabel(id);
    }

    /// <summary>Short zone name: initials of a multi-word Windows zone name ("Pacific Daylight Time" → "PDT").</summary>
    /// <param name="zone">Zone.</param>
    /// <param name="local">Local time in the zone.</param>
    /// <returns>Abbreviation.</returns>
    internal static string ZoneAbbreviation(TimeZoneInfo zone, DateTimeOffset local)
    {
        if (zone == TimeZoneInfo.Utc || zone.Id is "UTC" or "Etc/UTC") return "UTC";
        var name = zone.IsDaylightSavingTime(local) ? zone.DaylightName : zone.StandardName;
        var words = name.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length > 1 && words.All(w => char.IsLetter(w[0])))
            return string.Concat(words.Select(w => char.ToUpperInvariant(w[0])));
        var offset = local.Offset;
        return "UTC" + (offset < TimeSpan.Zero ? "−" : "+") + offset.ToString(@"hh\:mm", CultureInfo.InvariantCulture);
    }

    /// <summary>Groups a count ("1,234").</summary>
    /// <param name="value">Count.</param>
    /// <returns>Text.</returns>
    private static string Grouped(double value) =>
        ((long)Math.Round(value)).ToString("N0", CultureInfo.GetCultureInfo("en-US"));

    /// <summary>Unit labels.</summary>
    internal static readonly Dictionary<string, string> UnitLabels = new(StringComparer.Ordinal)
    {
        ["leaderboards"] = "leaderboards", ["songs"] = "songs", ["batches"] = "batches", ["steps"] = "steps",
        ["accounts"] = "accounts", ["bands"] = "bands", ["scopes"] = "scopes", ["instruments"] = "instruments",
        ["band_types"] = "band types", ["branches"] = "branches", ["items"] = "items",
        ["deep_jobs"] = "deep-scrape jobs", ["band_pages"] = "band pages", ["pages"] = "pages",
        ["chunks"] = "chunks", ["indexes"] = "indexes",
    };

    /// <summary>Phase labels.</summary>
    internal static readonly Dictionary<string, string> PhaseLabels = new(StringComparer.Ordinal)
    {
        ["scrape_leaderboards"] = "Scraping Leaderboard Scores",
        ["post_rank_recompute"] = "Post-Scrape Enrichment",
        ["post_first_seen_season"] = "Post-Scrape Enrichment",
        ["post_account_name_resolution"] = "Resolving Player Names",
        ["post_refresh_registered_users"] = "Refreshing Registered Users",
        ["post_activate_shadow_snapshots_early"] = "Snapshot Preparation",
        ["post_band_extraction"] = "Extracting Band Context",
        ["post_legacy_band_scrape"] = "Fetching Legacy Band Leaderboards",
        ["post_registered_player_band_discovery"] = "Registered Player Band Discovery",
        ["post_registered_band_targeted_processing"] = "Registered Band Processing",
        ["post_deferred_registration_sync"] = "Deferred Registration Sync",
        ["post_band_maintenance"] = "Band Maintenance",
        ["post_compute_rankings"] = "Computing Rankings",
        ["post_prepare_solo_current_projection"] = "Preparing Current Solo Rankings",
        ["post_rivals"] = "Computing Player Rivals",
        ["post_leaderboard_rivals"] = "Calculating Leaderboard Rivals",
        ["post_player_stats_tiers"] = "Computing Player Statistics",
        ["post_checkpoint"] = "Checkpoint",
        ["post_activate_shadow_snapshots"] = "Finalizing Updated Leaderboard Data",
        ["post_seal_solo_current_projection"] = "Finalizing Solo Ranking Scopes",
        ["post_cleanup_solo_current_projection"] = "Solo Projection Cleanup",
        ["post_cleanup_precompute_all"] = "API Precompute Cleanup",
        ["post_cleanup_solo_excess_entries"] = "Solo Entry Cleanup",
        ["post_cleanup_rank_history_retention"] = "Solo Rank History Cleanup",
        ["post_cleanup_band_rank_history_retention"] = "Band Rank History Cleanup",
        ["post_cleanup_service_level_retention"] = "Retention",
        ["publication_commit"] = "Publishing Leaderboard Update",
        ["post_improvement_notifications"] = "Preparing Improvement Notifications",
    };

    /// <summary>Subphase labels.</summary>
    internal static readonly Dictionary<string, string> SubphaseLabels = new(StringComparer.Ordinal)
    {
        ["fetching_leaderboards"] = "Fetching Leaderboards",
        ["persisting_scores"] = "Saving Retrieved Scores",
        ["deep_scraping"] = "Fetching Extended Leaderboard Data",
        ["cancelling_band_after_solo_failure"] = "Stopping Band Leaderboard Fetch",
        ["draining_solo_writes"] = "Saving Leaderboard Scores",
        ["dropping_solo_indexes"] = "Preparing Solo Score Storage",
        ["flushing_solo"] = "Saving Solo Leaderboard Scores",
        ["creating_solo_indexes"] = "Optimizing Solo Score Storage",
        ["detecting_score_changes"] = "Detecting Score Changes",
        ["checkpointing"] = "Saving Scrape Checkpoint",
        ["updating_population"] = "Updating Leaderboard Totals",
        ["awaiting_band"] = "Fetching Band Leaderboards",
        ["skipping_band_after_timeout"] = "Continuing Without Band Leaderboards",
        ["dropping_band_indexes"] = "Preparing Band Score Storage",
        ["flushing_band"] = "Saving Band Leaderboard Scores",
        ["creating_band_indexes"] = "Optimizing Band Score Storage",
        ["discovering_season_windows"] = "Finding Festival Seasons",
        ["building_work_list"] = "Preparing Player Sync Work",
        ["processing_songs"] = "Refreshing Player Scores",
        ["completing_user_actions"] = "Finalizing Player Sync",
        ["per_song_rivals"] = "Calculating Player Rivals",
        ["population_tiers"] = "Calculating Leaderboard Percentiles",
        ["parallel_precompute"] = "Preparing Published API Data",
        ["extracting_band_context"] = "Processing Band Score Data",
        ["rebuilding_band_membership_summary"] = "Refreshing Band Membership",
        ["per_instrument_rankings"] = "Calculating Instrument Rankings",
        ["composite_rankings"] = "Calculating Overall Rankings",
        ["solo_family_rankings"] = "Calculating Solo Rankings",
        ["combo_rankings"] = "Calculating Combined Rankings",
        ["rank_history_and_band_rankings"] = "Calculating Rank History and Band Rankings",
        ["band_rankings"] = "Calculating Band Rankings",
        ["rank_history_snapshots"] = "Saving Rank History",
        ["activating_shadow_snapshots_early"] = "Preparing Updated Leaderboard Data",
        ["registered_player_band_discovery"] = "Finding Registered Player Bands",
        ["registered_band_targeted_processing"] = "Refreshing Registered Bands",
        ["maintaining_band_projection"] = "Refreshing Band Data",
        ["prune"] = "Removing Outdated Band Entries",
        ["search_projection_refresh"] = "Refreshing Band Search Data",
        ["current_projection_refresh"] = "Refreshing Current Band Rankings",
        ["final_checkpoint"] = "Saving Final Checkpoint",
        ["publication_cleanup"] = "Preparing Data for Publication",
        ["deferred_registration_sync"] = "Syncing Deferred Registrations",
        ["database_cleanup"] = "Cleaning Database",
        ["cleanup_solo_excess_entries"] = "Removing Extra Solo Scores",
        ["cleanup_service_level_retention"] = "Planning Data Retention",
        ["cleanup_api_precompute"] = "Preparing API Responses",
        ["cleanup_solo_current_projection"] = "Refreshing Current Solo Rankings",
        ["cleanup_composite_rank_history"] = "Cleaning Overall Rank History",
        ["enriching_parallel_rank_recompute"] = "Recomputing Changed Ranks",
        ["enriching_parallel_tail"] = "Calculating Seasons and Resolving Names",
    };
}
#endregion
