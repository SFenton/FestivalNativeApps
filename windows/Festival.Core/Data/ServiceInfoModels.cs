using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Service info wire
/// <summary>
/// The subset of <c>GET /api/service-info</c> natives read (contract version 2; <c>FSTService/Api/HealthEndpoints.cs</c>).
/// The body also carries infrastructure detail (<c>postgresConnectionTarget</c>, <c>serviceInstance</c>, worker instance
/// IDs); those fields are deliberately not declared, so they are never decoded, stored or logged. Numbers decode as
/// <see cref="double"/> so a server-side widening never fails the read.
/// </summary>
/// <param name="ContractVersion">Contract version.</param>
/// <param name="PhasePlan">Ordered phase plan.</param>
/// <param name="LastCompletedUpdate">Last scrape that reached publication.</param>
/// <param name="CurrentUpdate">Running (or last failed) update; required.</param>
/// <param name="ActiveScrapeId">Active scrape.</param>
/// <param name="Publication">Publication pointers and read freeze.</param>
/// <param name="WorkerStatus">Scraper worker heartbeat summary.</param>
/// <param name="NextScheduledUpdateAt">Next scheduled update.</param>
public sealed record ServiceInfo(
    [property: JsonPropertyName("contractVersion")] double? ContractVersion,
    [property: JsonPropertyName("phasePlan")] ServicePhasePlan? PhasePlan,
    [property: JsonPropertyName("lastCompletedUpdate")] ServiceCompletedUpdate? LastCompletedUpdate,
    [property: JsonPropertyName("currentUpdate")] ServiceCurrentUpdate? CurrentUpdate,
    [property: JsonPropertyName("activeScrapeId")] double? ActiveScrapeId,
    [property: JsonPropertyName("publication")] ServicePublicationState? Publication,
    [property: JsonPropertyName("workerStatus")] ServiceWorkerStatus? WorkerStatus,
    [property: JsonPropertyName("nextScheduledUpdateAt")] string? NextScheduledUpdateAt);

/// <summary>Ordered phase plan used to label the current phase.</summary>
/// <param name="Version">Plan version.</param>
/// <param name="Phases">Phases.</param>
public sealed record ServicePhasePlan(
    [property: JsonPropertyName("version")] string? Version,
    [property: JsonPropertyName("phases")] List<ServicePhaseDescriptor>? Phases);

/// <summary>One phase in the plan.</summary>
/// <param name="Id">Stable phase ID.</param>
/// <param name="Label">Service label.</param>
public sealed record ServicePhaseDescriptor(
    [property: JsonPropertyName("id")] string? Id,
    [property: JsonPropertyName("label")] string? Label);

/// <summary>The last scrape that reached publication.</summary>
/// <param name="PublishedAt">Publication time.</param>
/// <param name="CompletedAt">Completion time.</param>
public sealed record ServiceCompletedUpdate(
    [property: JsonPropertyName("publishedAt")] string? PublishedAt,
    [property: JsonPropertyName("completedAt")] string? CompletedAt);

/// <summary>Subphase progress (<c>schemaVersion</c> 1).</summary>
/// <param name="SchemaVersion">Schema version.</param>
/// <param name="Id">Subphase ID.</param>
/// <param name="Epoch">Epoch.</param>
/// <param name="Sequence">Monotonic sequence within the epoch.</param>
/// <param name="Kind"><c>exact</c>, <c>indeterminate</c> or <c>not_applicable</c>.</param>
/// <param name="UnitsKind">Unit kind.</param>
/// <param name="UnitsCompleted">Completed units.</param>
/// <param name="UnitsTotal">Total units.</param>
/// <param name="UnitsTotalFinal">Whether the total is final.</param>
/// <param name="Percent">Percent.</param>
public sealed record ServiceSubphaseProgress(
    [property: JsonPropertyName("schemaVersion")] double? SchemaVersion,
    [property: JsonPropertyName("id")] string? Id,
    [property: JsonPropertyName("epoch")] double? Epoch,
    [property: JsonPropertyName("sequence")] double? Sequence,
    [property: JsonPropertyName("kind")] string? Kind,
    [property: JsonPropertyName("unitsKind")] string? UnitsKind,
    [property: JsonPropertyName("unitsCompleted")] double? UnitsCompleted,
    [property: JsonPropertyName("unitsTotal")] double? UnitsTotal,
    [property: JsonPropertyName("unitsTotalFinal")] bool? UnitsTotalFinal,
    [property: JsonPropertyName("percent")] double? Percent);

/// <summary>Registered-player band discovery attempt counts (<c>schemaVersion</c> 1).</summary>
/// <param name="SchemaVersion">Schema version.</param>
/// <param name="AttemptedThisPass">Accounts attempted in this pass.</param>
/// <param name="RetryableUnavailableThisPass">Attempted accounts that were temporarily unavailable.</param>
public sealed record ServiceAttemptProgressWire(
    [property: JsonPropertyName("schemaVersion")] double? SchemaVersion,
    [property: JsonPropertyName("attemptedThisPass")] double? AttemptedThisPass,
    [property: JsonPropertyName("retryableUnavailableThisPass")] double? RetryableUnavailableThisPass);

/// <summary>The running (or last failed) update.</summary>
/// <param name="Status"><c>idle</c>, <c>updating</c>, <c>failed</c> or <c>stalled</c> (unknown values kept verbatim).</param>
/// <param name="ScrapeId">Scrape ID.</param>
/// <param name="StartedAt">Start time.</param>
/// <param name="Phase">Legacy phase name.</param>
/// <param name="SubOperation">Legacy sub-operation.</param>
/// <param name="ContractVersion">Contract version.</param>
/// <param name="OperationId">Operation ID.</param>
/// <param name="PhaseId">Phase ID.</param>
/// <param name="PhaseStatus">Phase status.</param>
/// <param name="SubphaseId">Subphase ID.</param>
/// <param name="PhasePlanVersion">Plan version.</param>
/// <param name="PhaseOrdinal">Phase ordinal.</param>
/// <param name="PhaseAttempt">Attempt within the phase.</param>
/// <param name="UnitsKind">Unit kind.</param>
/// <param name="UnitsCompleted">Completed units.</param>
/// <param name="UnitsTotal">Total units.</param>
/// <param name="UnitsTotalFinal">Whether the total is final.</param>
/// <param name="PhasePercent">Phase percent.</param>
/// <param name="SubphaseProgress">Subphase progress.</param>
/// <param name="LastProgressAt">Last progress time.</param>
/// <param name="UpdatedAt">Update time.</param>
/// <param name="HeartbeatAt">Heartbeat time.</param>
/// <param name="AttemptProgress">Band discovery attempt counts, when the phase reports them.</param>
public sealed record ServiceCurrentUpdate(
    [property: JsonPropertyName("status")] string? Status,
    [property: JsonPropertyName("scrapeId")] double? ScrapeId = null,
    [property: JsonPropertyName("startedAt")] string? StartedAt = null,
    [property: JsonPropertyName("phase")] string? Phase = null,
    [property: JsonPropertyName("subOperation")] string? SubOperation = null,
    [property: JsonPropertyName("contractVersion")] double? ContractVersion = null,
    [property: JsonPropertyName("operationId")] string? OperationId = null,
    [property: JsonPropertyName("phaseId")] string? PhaseId = null,
    [property: JsonPropertyName("phaseStatus")] string? PhaseStatus = null,
    [property: JsonPropertyName("subphaseId")] string? SubphaseId = null,
    [property: JsonPropertyName("phasePlanVersion")] string? PhasePlanVersion = null,
    [property: JsonPropertyName("phaseOrdinal")] double? PhaseOrdinal = null,
    [property: JsonPropertyName("phaseAttempt")] double? PhaseAttempt = null,
    [property: JsonPropertyName("unitsKind")] string? UnitsKind = null,
    [property: JsonPropertyName("unitsCompleted")] double? UnitsCompleted = null,
    [property: JsonPropertyName("unitsTotal")] double? UnitsTotal = null,
    [property: JsonPropertyName("unitsTotalFinal")] bool? UnitsTotalFinal = null,
    [property: JsonPropertyName("phasePercent")] double? PhasePercent = null,
    [property: JsonPropertyName("subphaseProgress")] ServiceSubphaseProgress? SubphaseProgress = null,
    [property: JsonPropertyName("lastProgressAt")] string? LastProgressAt = null,
    [property: JsonPropertyName("updatedAt")] string? UpdatedAt = null,
    [property: JsonPropertyName("heartbeatAt")] string? HeartbeatAt = null,
    [property: JsonPropertyName("attemptProgress")] ServiceAttemptProgressWire? AttemptProgress = null);

/// <summary>Publication pointers and the public-read freeze.</summary>
/// <param name="PublishedAt">Publication time.</param>
/// <param name="PublicReadsFrozen">Whether public reads are frozen.</param>
/// <param name="FreezeReason">Freeze reason.</param>
public sealed record ServicePublicationState(
    [property: JsonPropertyName("publishedAt")] string? PublishedAt,
    [property: JsonPropertyName("publicReadsFrozen")] bool? PublicReadsFrozen,
    [property: JsonPropertyName("freezeReason")] string? FreezeReason);

/// <summary>Scraper worker heartbeat summary.</summary>
/// <param name="Status"><c>online</c>, <c>offline</c>, <c>stale</c>, <c>starting</c>, <c>stopping</c> or <c>unknown</c>.</param>
public sealed record ServiceWorkerStatus([property: JsonPropertyName("status")] string? Status);

/// <summary><c>GET /api/version</c> body.</summary>
/// <param name="Version">Service build version.</param>
public sealed record ServiceVersionBody([property: JsonPropertyName("version")] string? Version);

/// <summary>A service-info read plus the freeze header observed on it.</summary>
/// <param name="Info">Decoded body.</param>
/// <param name="FreezeReasonHeader"><c>X-FST-Public-Read-Freeze-Reason</c>, when stamped.</param>
public sealed record ServiceInfoSnapshot(ServiceInfo Info, string? FreezeReasonHeader);
#endregion
