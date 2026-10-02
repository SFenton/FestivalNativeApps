import Foundation

// MARK: - Wire model

/// The subset of `GET /api/service-info` natives read (contract version 2).
///
/// Source: `FSTService/Api/HealthEndpoints.cs` `MapGet("/api/service-info")`. The response also
/// carries infrastructure detail (`postgresConnectionTarget`, `serviceInstance`, worker
/// instance ids); natives deliberately do not decode, store or log those fields. Every numeric
/// field decodes as `Double` so a server-side widening never fails the whole read.
public struct ServiceInfo: Decodable, Sendable, Equatable {
    /// One phase in the service's published phase plan.
    public struct PhaseDescriptor: Decodable, Sendable, Equatable {
        public let id: String
        public let label: String?
    }

    /// Ordered phase plan used to label the current phase.
    public struct PhasePlan: Decodable, Sendable, Equatable {
        public let version: String?
        public let phases: [PhaseDescriptor]?
    }

    /// The last scrape that reached publication.
    public struct CompletedUpdate: Decodable, Sendable, Equatable {
        public let publishedAt: String?
        public let completedAt: String?
    }

    /// Subphase progress (`schemaVersion` 1).
    public struct SubphaseProgress: Decodable, Sendable, Equatable {
        public let schemaVersion: Double?
        public let id: String?
        public let epoch: Double?
        public let sequence: Double?
        public let kind: String?
        public let unitsKind: String?
        public let unitsCompleted: Double?
        public let unitsTotal: Double?
        public let unitsTotalFinal: Bool?
        public let percent: Double?
    }

    /// Per-pass lookup counts (`schemaVersion` 1) the registered-band discovery phase reports
    /// beside its durable completion (`PhaseAttemptProgressInfo`).
    public struct AttemptProgress: Decodable, Sendable, Equatable {
        public let schemaVersion: Double?
        public let attemptedThisPass: Double?
        public let retryableUnavailableThisPass: Double?
    }

    /// The running (or last failed) update.
    public struct CurrentUpdate: Decodable, Sendable, Equatable {
        /// `idle`, `updating`, `failed` or `stalled` (unknown values are kept verbatim).
        public let status: String
        public let scrapeId: Double?
        public let startedAt: String?
        public let phase: String?
        public let subOperation: String?
        public let contractVersion: Double?
        public let operationId: String?
        public let phaseId: String?
        public let phaseStatus: String?
        public let subphaseId: String?
        public let phasePlanVersion: String?
        public let phaseOrdinal: Double?
        public let phaseAttempt: Double?
        public let unitsKind: String?
        public let unitsCompleted: Double?
        public let unitsTotal: Double?
        public let unitsTotalFinal: Bool?
        public let phasePercent: Double?
        public let subphaseProgress: SubphaseProgress?
        public let attemptProgress: AttemptProgress?
        public let lastProgressAt: String?
        public let updatedAt: String?
        public let heartbeatAt: String?
    }

    /// Publication pointers and the public-read freeze.
    public struct PublicationState: Decodable, Sendable, Equatable {
        public let publishedAt: String?
        public let publicReadsFrozen: Bool?
        public let freezeReason: String?
    }

    /// Scraper worker heartbeat summary.
    public struct WorkerStatus: Decodable, Sendable, Equatable {
        /// `online`, `offline`, `stale`, `starting`, `stopping` or `unknown`.
        public let status: String?
    }

    public let contractVersion: Double?
    public let phasePlan: PhasePlan?
    public let lastCompletedUpdate: CompletedUpdate?
    public let currentUpdate: CurrentUpdate
    public let activeScrapeId: Double?
    public let publication: PublicationState?
    public let workerStatus: WorkerStatus?
    public let nextScheduledUpdateAt: String?
}

/// A service-info read plus the freeze header observed on it.
public struct ServiceInfoSnapshot: Sendable, Equatable {
    /// Decoded body.
    public let info: ServiceInfo
    /// `X-FST-Public-Read-Freeze-Reason`, when the service stamped one.
    public let freezeReasonHeader: String?

    /// Create a snapshot.
    ///
    /// - Parameters:
    ///   - info: Decoded body.
    ///   - freezeReasonHeader: Response freeze header, if any.
    public init(info: ServiceInfo, freezeReasonHeader: String?) {
        self.info = info
        self.freezeReasonHeader = freezeReasonHeader
    }
}

// MARK: - Endpoints

/// Operational, unpinned reads used by Settings. Both are pure: `/api/service-info` runs one
/// `SELECT` (`MetaDatabase.GetServiceRuntimeState`) plus in-process progress; `/api/version`
/// reads assembly metadata. Neither is publication-bound, so neither answers a freeze 503.
enum SettingsServiceEndpoint: ServiceEndpoint {
    case serviceInfo
    case version

    /// Build the endpoint URL.
    ///
    /// - Parameter baseURL: Validated service origin.
    /// - Returns: `/api/service-info` or `/api/version`.
    func url(relativeTo baseURL: URL) throws -> URL {
        let api = baseURL.appendingPathComponent("api")
        switch self {
        case .serviceInfo: return api.appendingPathComponent("service-info")
        case .version: return api.appendingPathComponent("version")
        }
    }
}

/// `GET /api/version` body.
private struct ServiceVersionBody: Decodable {
    let version: String
}

extension FestivalAPI {
    /// Read live scrape, worker and publication state for the Settings Service Info card.
    ///
    /// - Returns: Decoded state and any freeze header.
    /// - Throws: Transport, mapped status or `invalidResponse` for a malformed body.
    public func serviceInfo() async throws -> ServiceInfoSnapshot {
        let response = try await fetchJSON(SettingsServiceEndpoint.serviceInfo, as: ServiceInfo.self)
        return ServiceInfoSnapshot(info: response.value, freezeReasonHeader: response.freezeReason)
    }

    /// Read the service build version string for Settings → Version.
    ///
    /// - Returns: A short printable version string.
    /// - Throws: Transport, mapped status or `invalidResponse` for an empty, oversized or
    ///   non-printable-ASCII value.
    public func serviceVersion() async throws -> String {
        let response = try await fetchJSON(SettingsServiceEndpoint.version, as: ServiceVersionBody.self)
        let value = response.value.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 64,
              value.unicodeScalars.allSatisfy({ (0x20..<0x7F).contains($0.value) })
        else { throw FestivalAPIError.invalidResponse }
        return value
    }
}

// MARK: - Progress reduction

/// Monotonic progress bar state, ported from the web's `ServiceBarProgress`.
public struct ServiceBarProgress: Sendable, Equatable {
    /// `exact`, `indeterminate` or `not_applicable`.
    public enum Kind: String, Sendable {
        case exact
        case indeterminate
        case notApplicable = "not_applicable"
    }

    public let identity: String
    public let id: String?
    public let sequence: Double
    public let kind: Kind
    /// 0–100 only when `kind == .exact`.
    public let percent: Double?
    public let unitsKind: String?
    public let unitsCompleted: Double?
    public let unitsTotal: Double?
}

/// Validated per-pass lookup counts, the web's `ServiceAttemptProgress`.
public struct ServiceAttemptProgress: Sendable, Equatable {
    public var attemptedThisPass: Int
    public var retryableUnavailableThisPass: Int

    /// Create counts.
    ///
    /// - Parameters:
    ///   - attemptedThisPass: Lookups attempted in the current pass.
    ///   - retryableUnavailableThisPass: Of those, lookups that were temporarily unavailable.
    public init(attemptedThisPass: Int, retryableUnavailableThisPass: Int) {
        self.attemptedThisPass = attemptedThisPass
        self.retryableUnavailableThisPass = retryableUnavailableThisPass
    }
}

/// What the Service Info card renders for one poll, the web's `ServiceProgressDisplay`
/// (ETA and overall percent are not shown by the web card either, so they are not ported).
public struct ServiceProgressDisplay: Sendable, Equatable {
    public var phasePercent: Double?
    public var phaseId: String?
    /// Phase-level unit counts (the discovery-attempt line reports these as "completed").
    public var unitsCompleted: Double?
    public var unitsTotal: Double?
    /// Registered-band discovery lookup counts, monotonic within one phase attempt.
    public var attemptProgress: ServiceAttemptProgress?
    public var subphaseId: String?
    public var phaseAttempt: Double?
    public var phaseOrdinal: Double?
    public var restarted = false
    public var stalePayloadIgnored = false
    public var barProgress: ServiceBarProgress?

    static let empty = ServiceProgressDisplay()
}

/// Memory carried between polls so progress never moves backwards within one phase attempt.
public struct ServiceProgressMemory: Sendable, Equatable {
    public let operationIdentity: String?
    public let phaseId: String?
    public let phaseAttempt: Double?
    public let phaseOrdinal: Double?
    public let lastProgressTimestamp: Date?
    public let display: ServiceProgressDisplay
}

/// Port of `reduceServiceProgress` (`pages/settings/serviceProgress.ts`): percentages are
/// clamped and monotonic within an operation/phase/attempt, stale out-of-order payloads are
/// ignored, and a restarted attempt resets the bar.
public enum ServiceProgressReducer {
    /// Reduce one poll against the previous memory.
    ///
    /// - Parameters:
    ///   - previous: Memory from the last poll, or nil.
    ///   - info: New service-info body.
    /// - Returns: Display for this poll and memory for the next.
    public static func reduce(
        _ previous: ServiceProgressMemory?, _ info: ServiceInfo
    ) -> (display: ServiceProgressDisplay, memory: ServiceProgressMemory) {
        let current = info.currentUpdate
        let identity = operationIdentity(info)
        guard current.status == "updating" else {
            let memory = ServiceProgressMemory(
                operationIdentity: nil, phaseId: nil, phaseAttempt: nil, phaseOrdinal: nil,
                lastProgressTimestamp: nil, display: .empty
            )
            return (.empty, memory)
        }
        let isV2 = info.contractVersion == 2 || current.contractVersion == 2 || current.phaseId != nil
        let timestamp = ServiceInfoText.parseDate(
            current.lastProgressAt ?? current.updatedAt ?? current.heartbeatAt
        )
        let sameOperation = previous?.operationIdentity != nil && previous?.operationIdentity == identity
        let phaseId = current.phaseId
        let phaseAttempt = finite(current.phaseAttempt)
        let phaseOrdinal = finite(current.phaseOrdinal)
        let samePhase = sameOperation && previous?.phaseId != nil && previous?.phaseId == phaseId
        let attemptChanged = samePhase && previous?.phaseAttempt != nil && phaseAttempt != nil
            && previous?.phaseAttempt != phaseAttempt
        let ordinalRestart = sameOperation && previous?.phaseOrdinal != nil && phaseOrdinal != nil
            && phaseOrdinal! < previous!.phaseOrdinal!
        let restarted = attemptChanged || ordinalRestart

        if let previous, sameOperation, !restarted, let timestamp,
           let last = previous.lastProgressTimestamp, timestamp < last {
            var display = previous.display
            display.stalePayloadIgnored = true
            display.restarted = false
            return (display, ServiceProgressMemory(
                operationIdentity: previous.operationIdentity, phaseId: previous.phaseId,
                phaseAttempt: previous.phaseAttempt, phaseOrdinal: previous.phaseOrdinal,
                lastProgressTimestamp: previous.lastProgressTimestamp, display: display
            ))
        }

        let unitsTotalFinal = isV2 && current.unitsTotalFinal == true
        let rawPhasePercent = unitsTotalFinal ? clamp(finite(current.phasePercent)) : nil
        let previousPhasePercent = samePhase && !restarted ? previous?.display.phasePercent : nil
        let phasePercent = rawPhasePercent.map { max($0, previousPhasePercent ?? $0) }

        var display = ServiceProgressDisplay()
        display.phasePercent = phasePercent
        display.phaseId = phaseId
        display.subphaseId = current.subphaseId
        display.phaseAttempt = phaseAttempt
        display.phaseOrdinal = phaseOrdinal
        display.restarted = restarted
        display.unitsCompleted = finite(current.unitsCompleted)
        display.unitsTotal = finite(current.unitsTotal)
        let previousAttempt = samePhase && !restarted ? previous?.display.attemptProgress : nil
        display.attemptProgress = normalizedAttemptProgress(current.attemptProgress).map { raw in
            ServiceAttemptProgress(
                attemptedThisPass: max(previousAttempt?.attemptedThisPass ?? 0, raw.attemptedThisPass),
                retryableUnavailableThisPass: max(
                    previousAttempt?.retryableUnavailableThisPass ?? 0, raw.retryableUnavailableThisPass
                )
            )
        }
        display.barProgress = reduceBar(
            previous: previous?.display.barProgress, info: info, identity: identity,
            phaseId: phaseId, phaseAttempt: phaseAttempt, phasePercent: phasePercent,
            unitsTotalFinal: unitsTotalFinal
        )
        let memory = ServiceProgressMemory(
            operationIdentity: identity, phaseId: phaseId, phaseAttempt: phaseAttempt,
            phaseOrdinal: phaseOrdinal,
            lastProgressTimestamp: timestamp ?? previous?.lastProgressTimestamp, display: display
        )
        return (display, memory)
    }

    /// Stable identity of the running operation (`scrapeId:operationId:planVersion`).
    ///
    /// - Parameter info: Service-info body.
    /// - Returns: Identity, or nil when neither a scrape nor an operation id is known.
    static func operationIdentity(_ info: ServiceInfo) -> String? {
        let current = info.currentUpdate
        let scrapeId = current.scrapeId ?? info.activeScrapeId
        if scrapeId == nil && current.operationId == nil { return nil }
        return [
            scrapeId.map(format) ?? current.startedAt ?? "none",
            current.operationId ?? "legacy",
            current.phasePlanVersion ?? info.phasePlan?.version ?? "unversioned",
        ].joined(separator: ":")
    }

    // swiftlint:disable:next function_parameter_count
    private static func reduceBar(
        previous: ServiceBarProgress?, info: ServiceInfo, identity: String?, phaseId: String?,
        phaseAttempt: Double?, phasePercent: Double?, unitsTotalFinal: Bool
    ) -> ServiceBarProgress {
        let current = info.currentUpdate
        let prefix = [identity ?? "none", phaseId ?? "none", phaseAttempt.map(format) ?? "none"]
        if let raw = current.subphaseProgress {
            let epoch = finite(raw.epoch) ?? 0
            let sequence = finite(raw.sequence) ?? 0
            let expectedId = current.subphaseId
            let id = raw.id ?? expectedId
            let barIdentity = (prefix + [id ?? "none", format(epoch)]).joined(separator: ":")
            let sameIdentity = previous?.identity == barIdentity
            if let previous, sameIdentity, sequence < previous.sequence { return previous }

            let supported = raw.schemaVersion == 1
            let matching = expectedId == nil || id == expectedId
            var kind: ServiceBarProgress.Kind = .indeterminate
            if supported, matching, let rawKind = raw.kind,
               rawKind == "exact" || rawKind == "not_applicable" {
                kind = rawKind == "exact" ? .exact : .notApplicable
            }
            let completed = finite(raw.unitsCompleted)
            let total = finite(raw.unitsTotal)
            var exactPercent: Double?
            if kind == .exact, raw.unitsTotalFinal == true, let total, total > 0,
               let completed, completed >= 0, completed <= total {
                exactPercent = clamp(finite(raw.percent))
            }
            if kind == .exact && exactPercent == nil { kind = .indeterminate }
            var percent = exactPercent
            if kind == .exact, sameIdentity, let prior = previous?.percent, let value = exactPercent {
                percent = max(prior, value)
            }
            return ServiceBarProgress(
                identity: barIdentity, id: id, sequence: sequence, kind: kind, percent: percent,
                unitsKind: kind == .exact ? raw.unitsKind : nil,
                unitsCompleted: kind == .exact ? completed : nil,
                unitsTotal: kind == .exact ? total : nil
            )
        }
        if let subphaseId = current.subphaseId {
            return ServiceBarProgress(
                identity: (prefix + [subphaseId, "legacy"]).joined(separator: ":"), id: subphaseId,
                sequence: 0, kind: .indeterminate, percent: nil, unitsKind: nil,
                unitsCompleted: nil, unitsTotal: nil
            )
        }
        return ServiceBarProgress(
            identity: (prefix + ["phase"]).joined(separator: ":"), id: nil, sequence: 0,
            kind: phasePercent != nil ? .exact : .indeterminate, percent: phasePercent,
            unitsKind: current.unitsKind, unitsCompleted: finite(current.unitsCompleted),
            unitsTotal: finite(current.unitsTotal)
        )
    }

    /// The web's `normalizeAttemptProgress`: schema 1 only, non-negative integers, and never
    /// more unavailable lookups than attempts; anything else hides the line.
    ///
    /// - Parameter value: Wire counts.
    /// - Returns: Validated counts, or nil.
    static func normalizedAttemptProgress(_ value: ServiceInfo.AttemptProgress?) -> ServiceAttemptProgress? {
        guard let value, value.schemaVersion == 1,
              let attempted = finite(value.attemptedThisPass),
              let unavailable = finite(value.retryableUnavailableThisPass),
              attempted == attempted.rounded(), unavailable == unavailable.rounded(),
              attempted >= 0, unavailable >= 0, unavailable <= attempted,
              attempted < 1e15
        else { return nil }
        return ServiceAttemptProgress(
            attemptedThisPass: Int(attempted), retryableUnavailableThisPass: Int(unavailable)
        )
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func clamp(_ value: Double?) -> Double? {
        value.map { min(100, max(0, $0)) }
    }

    /// Integral doubles print without a decimal point, as JavaScript would.
    static func format(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}

// MARK: - Presentation

/// Worker/process state shown beside "Leaderboard Service State".
public enum ServiceProcessState: String, Sendable {
    case loading
    case updating
    case idle
    case stopped

    /// Title Case label.
    public var label: String {
        switch self {
        case .loading: "Loading"
        case .updating: "Updating"
        case .idle: "Idle"
        case .stopped: "Stopped"
        }
    }
}

/// Copy and label rules for the Service Info card, ported from `SettingsServiceProgress.tsx`
/// and `serviceInfo.en.json`.
public enum ServiceInfoText {
    public static let title = "Service Info"
    public static let hint =
        "Live leaderboard update status, exact phase progress when available, and publication timing."
    public static let serviceStateTitle = "Leaderboard Service State"
    public static let lastPublishedTitle = "Last Successful Publication"
    public static let publicationUnavailable = "No successful publication yet"
    public static let progressIndeterminate = "In progress — total not yet known"

    /// Process state: stopped when the worker is missing/offline/stale/stopping.
    ///
    /// - Parameter info: Service-info body.
    /// - Returns: Updating, idle or stopped.
    public static func processState(_ info: ServiceInfo) -> ServiceProcessState {
        switch info.workerStatus?.status {
        case nil, "offline", "stale", "stopping": return .stopped
        default: return info.currentUpdate.status == "updating" ? .updating : .idle
        }
    }

    private static let serviceStates: [String: String] = [
        "idle": "Waiting for the Next Update",
        "updating": "Leaderboard Update in Progress",
        "failed": "Last Leaderboard Update Failed",
        "stalled": "Leaderboard Update Stalled",
        "unavailable": "Leaderboard Updater Unavailable",
    ]

    /// Human description of the update status (used when not actively updating).
    ///
    /// - Parameters:
    ///   - info: Service-info body.
    ///   - state: Resolved process state.
    /// - Returns: Title Case status sentence.
    public static func serviceState(_ info: ServiceInfo, state: ServiceProcessState) -> String {
        let status = info.currentUpdate.status
        if state == .stopped && status != "failed" && status != "stalled" {
            return serviceStates["unavailable"]!
        }
        return serviceStates[status] ?? fallbackLabel(status)
    }

    /// Phase label: "Waiting for the next update" when idle, else the localized phase name.
    ///
    /// - Parameters:
    ///   - info: Service-info body.
    ///   - display: Reduced progress for this poll.
    /// - Returns: Phase label.
    public static func phaseLabel(_ info: ServiceInfo, display: ServiceProgressDisplay) -> String {
        let current = info.currentUpdate
        if current.status == "idle" { return "Waiting for the next update" }
        let descriptor = info.phasePlan?.phases?.first { $0.id == display.phaseId }
        return stableLabel(phaseLabels, id: display.phaseId, fallback: descriptor?.label ?? current.phase)
            ?? "Waiting for progress"
    }

    /// Subphase label, or nil when none or it only repeats the status.
    ///
    /// - Parameters:
    ///   - info: Service-info body.
    ///   - display: Reduced progress for this poll.
    /// - Returns: Subphase label or nil.
    public static func subphaseLabel(_ info: ServiceInfo, display: ServiceProgressDisplay) -> String? {
        let current = info.currentUpdate
        guard let subphaseId = display.subphaseId ?? current.subOperation,
              subphaseId != current.status else { return nil }
        return dynamicSubphaseLabel(subphaseId)
            ?? stableLabel(subphaseLabels, id: subphaseId,
                           fallback: fallbackLabel(current.subOperation ?? subphaseId))
    }

    /// "Phase · Subphase", dropping a subphase that repeats the phase.
    ///
    /// - Parameters:
    ///   - phase: Phase label.
    ///   - subphase: Optional subphase label.
    /// - Returns: Combined row title.
    public static func phaseTitle(phase: String, subphase: String?) -> String {
        guard let subphase,
              subphase.trimmingCharacters(in: .whitespaces).lowercased()
                != phase.trimmingCharacters(in: .whitespaces).lowercased()
        else { return phase }
        return "\(phase) · \(subphase)"
    }

    /// Units line under the bar ("1,234 of 5,000 leaderboards completed").
    ///
    /// - Parameter progress: Bar progress.
    /// - Returns: Units sentence or nil when no count is known.
    public static func unitsText(_ progress: ServiceBarProgress?) -> String? {
        guard let completed = progress?.unitsCompleted else { return nil }
        let unit = stableLabel(unitLabels, id: progress?.unitsKind,
                               fallback: progress?.unitsKind.map(fallbackLabel)) ?? "items"
        let done = grouped(completed)
        if let total = progress?.unitsTotal {
            return "\(done) of \(grouped(total)) \(unit) completed"
        }
        return "\(done) \(unit) completed"
    }

    /// Registered-band discovery lookup line under the bar ("1,310 attempted this pass ·
    /// 70 temporarily unavailable · 1,240 of 5,000 completed"), shown only for that phase.
    ///
    /// - Parameter display: Reduced progress for this poll.
    /// - Returns: Attempt sentence, or nil for any other phase or without valid counts.
    public static func discoveryAttemptText(_ display: ServiceProgressDisplay) -> String? {
        guard display.phaseId == registeredBandDiscoveryPhaseId,
              let attempts = display.attemptProgress else { return nil }
        let head = "\(grouped(Double(attempts.attemptedThisPass))) attempted this pass · "
            + "\(grouped(Double(attempts.retryableUnavailableThisPass))) temporarily unavailable · "
        let completed = grouped(display.unitsCompleted ?? 0)
        guard let total = display.unitsTotal else { return head + "\(completed) completed" }
        return head + "\(completed) of \(grouped(total)) completed"
    }

    /// Phase whose card row adds the lookup-attempt line (web `discoveryAttemptText`).
    static let registeredBandDiscoveryPhaseId = "post.registered_player_band_discovery"

    /// Percent text for a determinate bar, or the indeterminate sentence.
    ///
    /// - Parameter progress: Bar progress.
    /// - Returns: "42.5%" or "In progress — total not yet known".
    public static func progressText(_ progress: ServiceBarProgress?) -> String {
        guard progress?.kind == .exact, let percent = progress?.percent else {
            return progressIndeterminate
        }
        return String(format: "%.1f%%", percent)
    }

    /// Last successful publication time.
    ///
    /// - Parameters:
    ///   - info: Service-info body.
    ///   - timeZone: Display time zone (fixed in tests).
    ///   - locale: Display locale (fixed in tests).
    /// - Returns: Formatted date/time or the "no publication" sentence.
    public static func lastPublished(
        _ info: ServiceInfo, timeZone: TimeZone = .current, locale: Locale = .current
    ) -> String {
        guard let date = parseDate(info.lastCompletedUpdate?.publishedAt ?? info.publication?.publishedAt)
        else { return publicationUnavailable }
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)
        style = style.timeZone(.specificName(.short))
        return date.formatted(style)
    }

    /// Native freeze explanation, from the response header first and the body second, using
    /// the shared `ServiceFreezeReason` vocabulary.
    ///
    /// - Parameter snapshot: One service-info read.
    /// - Returns: Sentence when public reads are frozen, else nil.
    public static func freezeNotice(_ snapshot: ServiceInfoSnapshot) -> String? {
        let header = snapshot.freezeReasonHeader?.trimmingCharacters(in: .whitespaces)
        let body = snapshot.info.publication
        let reason = (header?.isEmpty == false ? header : nil)
            ?? (body?.publicReadsFrozen == true ? (body?.freezeReason ?? "") : nil)
        guard let reason else { return nil }
        return ServiceFreezeReason.isScoreUpdate(reason)
            ? "Paused while new scores publish. Pages show the last publication."
            : "Paused for service maintenance. Pages show the last publication."
    }

    /// Parse an ISO-8601 UTC timestamp, tolerating .NET's seven fractional digits.
    ///
    /// - Parameter value: Timestamp text.
    /// - Returns: Date, or nil for missing/unparsable text.
    public static func parseDate(_ value: String?) -> Date? {
        guard var text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let dot = text.firstIndex(of: ".") {
            let digitsEnd = text[text.index(after: dot)...].firstIndex { !$0.isNumber } ?? text.endIndex
            let digits = text[text.index(after: dot)..<digitsEnd]
            text.replaceSubrange(dot..<digitsEnd, with: "." + digits.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0))
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    // MARK: Labels

    /// Web `fallbackLabel`: `.`/`_` → space, split camelCase, capitalize word starts.
    ///
    /// - Parameter id: Stable identifier.
    /// - Returns: Readable label.
    public static func fallbackLabel(_ id: String) -> String {
        var spaced = ""
        var previous: Character?
        for char in id {
            let mapped: Character = (char == "." || char == "_") ? " " : char
            if let previous, mapped.isUppercase, previous.isLowercase || previous.isNumber {
                spaced.append(" ")
            }
            spaced.append(mapped)
            previous = mapped
        }
        var result = ""
        var atWordStart = true
        for char in spaced {
            let isWord = char.isLetter || char.isNumber
            result.append(atWordStart && isWord ? Character(char.uppercased()) : char)
            atWordStart = !isWord
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Look up a stable id (`.`/`-` → `_`) in a label table.
    private static func stableLabel(_ table: [String: String], id: String?, fallback: String?) -> String? {
        guard let id else { return fallback }
        let key = id.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "-", with: "_")
        if let label = table[key] { return label }
        if let fallback, !fallback.isEmpty { return fallback }
        return fallbackLabel(id)
    }

    /// `cleanup_rank_history_<scope>` / `cleanup_band_rank_history_<scope>` patterns.
    static func dynamicSubphaseLabel(_ id: String) -> String? {
        let normalized = id.trimmingCharacters(in: .whitespaces)
        let lower = normalized.lowercased()
        let prefixes = ["cleanup_band_rank_history_", "cleanup_rank_history_"]
        guard let prefix = prefixes.first(where: lower.hasPrefix) else { return nil }
        let suffix = String(normalized.dropFirst(prefix.count))
        guard !suffix.isEmpty else { return nil }
        let scope = Instrument(rawValue: suffix)?.label ?? fallbackLabel(suffix)
        return "Cleaning \(scope) Rank History"
    }

    private static func grouped(_ value: Double) -> String {
        Int64(value.rounded()).formatted(.number.grouping(.automatic))
    }

    static let unitLabels: [String: String] = [
        "leaderboards": "leaderboards", "songs": "songs", "batches": "batches", "steps": "steps",
        "accounts": "accounts", "bands": "bands", "scopes": "scopes", "instruments": "instruments",
        "band_types": "band types", "branches": "branches", "items": "items",
        "deep_jobs": "deep-scrape jobs", "band_pages": "band pages", "pages": "pages",
        "chunks": "chunks", "indexes": "indexes",
    ]

    static let phaseLabels: [String: String] = [
        "scrape_leaderboards": "Scraping Leaderboard Scores",
        "post_rank_recompute": "Post-Scrape Enrichment",
        "post_first_seen_season": "Post-Scrape Enrichment",
        "post_account_name_resolution": "Resolving Player Names",
        "post_refresh_registered_users": "Refreshing Registered Users",
        "post_activate_shadow_snapshots_early": "Snapshot Preparation",
        "post_band_extraction": "Extracting Band Context",
        "post_legacy_band_scrape": "Fetching Legacy Band Leaderboards",
        "post_registered_player_band_discovery": "Registered Player Band Discovery",
        "post_registered_band_targeted_processing": "Registered Band Processing",
        "post_deferred_registration_sync": "Deferred Registration Sync",
        "post_band_maintenance": "Band Maintenance",
        "post_compute_rankings": "Computing Rankings",
        "post_prepare_solo_current_projection": "Preparing Current Solo Rankings",
        "post_rivals": "Computing Player Rivals",
        "post_leaderboard_rivals": "Calculating Leaderboard Rivals",
        "post_player_stats_tiers": "Computing Player Statistics",
        "post_checkpoint": "Checkpoint",
        "post_activate_shadow_snapshots": "Finalizing Updated Leaderboard Data",
        "post_seal_solo_current_projection": "Finalizing Solo Ranking Scopes",
        "post_cleanup_solo_current_projection": "Solo Projection Cleanup",
        "post_cleanup_precompute_all": "API Precompute Cleanup",
        "post_cleanup_solo_excess_entries": "Solo Entry Cleanup",
        "post_cleanup_rank_history_retention": "Solo Rank History Cleanup",
        "post_cleanup_band_rank_history_retention": "Band Rank History Cleanup",
        "post_cleanup_service_level_retention": "Retention",
        "publication_commit": "Publishing Leaderboard Update",
        "post_improvement_notifications": "Preparing Improvement Notifications",
    ]

    static let subphaseLabels: [String: String] = [
        "fetching_leaderboards": "Fetching Leaderboards",
        "persisting_scores": "Saving Retrieved Scores",
        "deep_scraping": "Fetching Extended Leaderboard Data",
        "cancelling_band_after_solo_failure": "Stopping Band Leaderboard Fetch",
        "draining_solo_writes": "Saving Leaderboard Scores",
        "dropping_solo_indexes": "Preparing Solo Score Storage",
        "flushing_solo": "Saving Solo Leaderboard Scores",
        "creating_solo_indexes": "Optimizing Solo Score Storage",
        "detecting_score_changes": "Detecting Score Changes",
        "checkpointing": "Saving Scrape Checkpoint",
        "updating_population": "Updating Leaderboard Totals",
        "awaiting_band": "Fetching Band Leaderboards",
        "skipping_band_after_timeout": "Continuing Without Band Leaderboards",
        "dropping_band_indexes": "Preparing Band Score Storage",
        "flushing_band": "Saving Band Leaderboard Scores",
        "creating_band_indexes": "Optimizing Band Score Storage",
        "discovering_season_windows": "Finding Festival Seasons",
        "building_work_list": "Preparing Player Sync Work",
        "processing_songs": "Refreshing Player Scores",
        "completing_user_actions": "Finalizing Player Sync",
        "per_song_rivals": "Calculating Player Rivals",
        "population_tiers": "Calculating Leaderboard Percentiles",
        "parallel_precompute": "Preparing Published API Data",
        "extracting_band_context": "Processing Band Score Data",
        "rebuilding_band_membership_summary": "Refreshing Band Membership",
        "per_instrument_rankings": "Calculating Instrument Rankings",
        "composite_rankings": "Calculating Overall Rankings",
        "solo_family_rankings": "Calculating Solo Rankings",
        "combo_rankings": "Calculating Combined Rankings",
        "rank_history_and_band_rankings": "Calculating Rank History and Band Rankings",
        "band_rankings": "Calculating Band Rankings",
        "rank_history_snapshots": "Saving Rank History",
        "activating_shadow_snapshots_early": "Preparing Updated Leaderboard Data",
        "registered_player_band_discovery": "Finding Registered Player Bands",
        "registered_band_targeted_processing": "Refreshing Registered Bands",
        "maintaining_band_projection": "Refreshing Band Data",
        "prune": "Removing Outdated Band Entries",
        "search_projection_refresh": "Refreshing Band Search Data",
        "current_projection_refresh": "Refreshing Current Band Rankings",
        "final_checkpoint": "Saving Final Checkpoint",
        "publication_cleanup": "Preparing Data for Publication",
        "deferred_registration_sync": "Syncing Deferred Registrations",
        "database_cleanup": "Cleaning Database",
        "cleanup_solo_excess_entries": "Removing Extra Solo Scores",
        "cleanup_service_level_retention": "Planning Data Retention",
        "cleanup_api_precompute": "Preparing API Responses",
        "cleanup_solo_current_projection": "Refreshing Current Solo Rankings",
        "cleanup_composite_rank_history": "Cleaning Overall Rank History",
        "enriching_parallel_rank_recompute": "Recomputing Changed Ranks",
        "enriching_parallel_tail": "Calculating Seasons and Resolving Names",
    ]
}
