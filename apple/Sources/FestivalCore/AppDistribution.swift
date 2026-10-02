import Foundation
import Observation
import StoreKit

// MARK: - Distribution channel

/// How this copy of the app was installed. TestFlight and the App Store ship the same binary, so
/// tester-only content (the What's New "Changes since release …" list) must be chosen at run time.
public enum AppDistribution: String, Sendable, Equatable {
    /// Installed from the App Store (also the provisional answer while detection fails).
    case appStore
    /// Installed from TestFlight (sandbox receipt or StoreKit's sandbox environment).
    case testFlight
    /// A Debug or Xcode-installed build.
    case development

    /// Whether What's New shows the tester list instead of the release notes.
    public var showsTesterNotes: Bool { self != .appStore }

    /// The best known channel: nil while the first detection is still pending (see
    /// ``AppDistributionResolver/channel``).
    @MainActor public static var resolved: AppDistribution? { AppDistributionResolver.shared.channel }

    /// Detect (or reuse) the install channel through ``AppDistributionResolver/shared``.
    ///
    /// - Returns: The definitive channel, or a provisional `.appStore` when StoreKit is slow or fails.
    @MainActor
    public static func current() async -> AppDistribution {
        await AppDistributionResolver.shared.current()
    }

    /// Map an override value to a channel.
    ///
    /// - Parameter value: `appstore`, `testflight` or `development` (any case).
    /// - Returns: The channel, or nil for anything else.
    static func parse(_ value: String?) -> AppDistribution? {
        switch value?.lowercased() {
        case "appstore": .appStore
        case "testflight": .testFlight
        case "development": .development
        default: nil
        }
    }

    /// Map a StoreKit environment to a channel.
    ///
    /// - Parameter environment: `AppTransaction.environment`.
    /// - Returns: `.testFlight` for sandbox, `.development` for Xcode, else `.appStore`.
    static func channel(for environment: AppStore.Environment) -> AppDistribution {
        switch environment {
        case .sandbox: .testFlight
        case .xcode: .development
        default: .appStore
        }
    }

    /// Read the channel from the App Store receipt's file name, without StoreKit.
    ///
    /// iOS/iPadOS TestFlight installs carry `StoreKit/sandboxReceipt`; App Store installs carry
    /// `StoreKit/receipt`. macOS uses `_MASReceipt/receipt` for both, so it always needs StoreKit.
    ///
    /// - Parameter url: `Bundle.main.appStoreReceiptURL`.
    /// - Returns: `.testFlight` for a sandbox receipt, else nil (unknown).
    static func receiptChannel(_ url: URL?) -> AppDistribution? {
        url?.lastPathComponent == "sandboxReceipt" ? .testFlight : nil
    }

    /// StoreKit's answer, or nil when `AppTransaction` fails.
    static func storeKitChannel() async -> AppDistribution? {
        guard let result = try? await AppTransaction.shared else { return nil }
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            return channel(for: transaction.environment)
        }
    }
}

// MARK: - Resolver

/// Once-per-process install-channel detection that never hides tester notes behind a slow StoreKit.
///
/// Order: a fixed channel (Debug: `FST_DEBUG_DISTRIBUTION`, default `.development`), then the
/// sandbox receipt (instant TestFlight on iOS/iPadOS), then `AppTransaction` bounded by
/// ``timeout``. Only a definitive answer is cached. A timeout or StoreKit error publishes a
/// provisional `.appStore` so a waiting caller can show something; a timed-out probe keeps running
/// and upgrades ``channel`` when it answers, and a failed probe is retried on the next call.
/// Views observe ``channel`` and must treat nil as pending, never as the App Store.
@MainActor
@Observable
public final class AppDistributionResolver {
    /// The app's resolver.
    public static let shared = AppDistributionResolver.live()

    /// Longest wait for StoreKit before answering a provisional `.appStore`.
    public static let defaultTimeout: Duration = .seconds(10)

    /// Best known channel; nil until the first detection answers (pending).
    public private(set) var channel: AppDistribution?
    /// Whether ``channel`` is definitive and cached for the process.
    public private(set) var isFinal = false

    @ObservationIgnored private let fixed: AppDistribution?
    @ObservationIgnored private let receiptURL: @Sendable () -> URL?
    @ObservationIgnored private let storeKit: @Sendable () async -> AppDistribution?
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private var probe: Task<AppDistribution?, Never>?

    /// Create a resolver.
    ///
    /// - Parameters:
    ///   - fixed: Channel to answer without detection (Debug override), or nil to detect.
    ///   - receiptURL: App Store receipt location (`Bundle.main.appStoreReceiptURL` in the app).
    ///   - storeKit: StoreKit probe returning nil on error (`AppTransaction` in the app).
    ///   - timeout: Longest wait for `storeKit` per call.
    public init(
        fixed: AppDistribution? = nil,
        receiptURL: @escaping @Sendable () -> URL?,
        storeKit: @escaping @Sendable () async -> AppDistribution?,
        timeout: Duration = AppDistributionResolver.defaultTimeout
    ) {
        self.fixed = fixed
        self.receiptURL = receiptURL
        self.storeKit = storeKit
        self.timeout = timeout
    }

    /// The app's resolver for a process environment.
    ///
    /// - Parameter environment: Process environment; Debug builds never call StoreKit (an app
    ///   without a receipt may ask the user to sign in) and honor
    ///   `FST_DEBUG_DISTRIBUTION=appstore|testflight|development` (default `development`).
    /// - Returns: A resolver reading the main bundle's receipt and `AppTransaction`.
    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppDistributionResolver {
        #if DEBUG
        let fixed: AppDistribution? = AppDistribution.parse(environment["FST_DEBUG_DISTRIBUTION"]) ?? .development
        #else
        let fixed: AppDistribution? = nil
        #endif
        return AppDistributionResolver(
            fixed: fixed,
            receiptURL: { Bundle.main.appStoreReceiptURL },
            storeKit: { await AppDistribution.storeKitChannel() }
        )
    }

    /// Resolve the channel, waiting at most ``timeout`` for StoreKit.
    ///
    /// - Returns: The cached or newly detected channel, or a provisional `.appStore` (not cached)
    ///   after a timeout or StoreKit error.
    public func current() async -> AppDistribution {
        if isFinal, let channel { return channel }
        if let known = fixed ?? AppDistribution.receiptChannel(receiptURL()) {
            settle(known)
            return known
        }
        let answer = await Self.first(of: self.probe ?? startProbe(), within: timeout)
        if let answer {
            settle(answer)
            return answer
        }
        if isFinal, let channel { return channel }  // the probe answered while the race was ending
        if channel == nil { channel = .appStore }
        return .appStore
    }

    /// Wait for a probe, but no longer than a limit. Unlike a task group, this returns at the limit
    /// without waiting for the probe (awaiting a `Task`'s value ignores cancellation), which keeps
    /// running and settles the resolver when it answers.
    ///
    /// - Parameters:
    ///   - probe: Running StoreKit probe.
    ///   - limit: Longest wait.
    /// - Returns: The probe's answer, or nil at the limit or when the probe failed.
    private static func first(
        of probe: Task<AppDistribution?, Never>, within limit: Duration
    ) async -> AppDistribution? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let timer = Task {
                try? await Task.sleep(for: limit)
                once.resume(nil)
            }
            Task {
                let found = await probe.value
                once.resume(found)
                timer.cancel()
            }
        }
    }

    /// Start the StoreKit probe; it settles the channel itself when it answers, even after a timeout.
    private func startProbe() -> Task<AppDistribution?, Never> {
        let storeKit = self.storeKit
        let task = Task { [weak self] () -> AppDistribution? in
            let found = await storeKit()
            self?.probeFinished(found)
            return found
        }
        probe = task
        return task
    }

    /// Record a probe's answer, or forget a failed probe so the next call retries.
    private func probeFinished(_ found: AppDistribution?) {
        if let found {
            settle(found)
        } else {
            probe = nil
            if channel == nil { channel = .appStore }
        }
    }

    /// Cache a definitive channel.
    private func settle(_ found: AppDistribution) {
        channel = found
        isFinal = true
        probe = nil
    }
}

// MARK: - First-wins continuation

/// Resumes a continuation with the first value offered and ignores the rest.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    /// Resume with `value` unless already resumed.
    func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
