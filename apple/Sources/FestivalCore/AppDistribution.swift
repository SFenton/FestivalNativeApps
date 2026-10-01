import Foundation
import StoreKit

// MARK: - Distribution channel

/// How this copy of the app was installed. TestFlight and the App Store ship the same binary, so
/// tester-only content (the What's New "New since …" sections) must be chosen at run time.
public enum AppDistribution: String, Sendable, Equatable {
    /// Installed from the App Store (also the fallback when detection fails).
    case appStore
    /// Installed from TestFlight (StoreKit's sandbox environment).
    case testFlight
    /// A Debug or Xcode-installed build.
    case development

    /// Whether What's New shows tester sections instead of the release section.
    public var showsTesterNotes: Bool { self != .appStore }

    /// Longest wait for StoreKit before falling back to `.appStore`.
    static let detectionTimeout: Duration = .seconds(3)

    /// The resolved channel after the first `current()` call; nil before.
    @MainActor public private(set) static var resolved: AppDistribution?

    /// Resolve (once per process) and return the install channel.
    ///
    /// - Parameter environment: Process environment; Debug builds honor
    ///   `FST_DEBUG_DISTRIBUTION=appstore|testflight|development`.
    /// - Returns: The cached or newly detected channel.
    @MainActor
    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> AppDistribution {
        if let resolved { return resolved }
        let found = await detect(environment: environment)
        resolved = found
        return found
    }

    /// Detect the channel without caching.
    ///
    /// Debug builds never call StoreKit (an app without a receipt may ask the user to sign in), so they
    /// report `.development` unless `FST_DEBUG_DISTRIBUTION` overrides it. Release builds read
    /// `AppTransaction.environment` and fall back to `.appStore` on error or timeout.
    ///
    /// - Parameter environment: Process environment.
    /// - Returns: Detected channel.
    static func detect(environment: [String: String]) async -> AppDistribution {
        #if DEBUG
        return parse(environment["FST_DEBUG_DISTRIBUTION"]) ?? .development
        #else
        return await withTaskGroup(of: AppDistribution?.self) { group in
            group.addTask { await storeKitChannel() }
            group.addTask {
                try? await Task.sleep(for: detectionTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .appStore
        }
        #endif
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

    private static func storeKitChannel() async -> AppDistribution {
        guard let result = try? await AppTransaction.shared else { return .appStore }
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            return channel(for: transaction.environment)
        }
    }
}
