import Foundation

// MARK: - ReappearanceLoadGate

/// Remembers which load key a view has already loaded, so a `NavigationStack`
/// reappearance does not reload it.
///
/// SwiftUI restarts `.task(id:)` every time a view reappears — for example on Back
/// from a pushed page — even when the id is unchanged. A section that unconditionally
/// resets to `.loading` there swaps its loaded rows for a spinner of a different
/// height and fades them in again, so the page jumps under the pop transition (#39).
/// Hold one gate in `@State`, skip the load while ``needsLoad(for:)`` is false, and
/// call ``markLoaded(_:)`` only after a successful read: a failed or cancelled read
/// leaves the gate open so the next appearance (or Retry) tries again, and a new key
/// (another instrument, account or publication) always loads.
public struct ReappearanceLoadGate<Key: Equatable & Sendable>: Equatable, Sendable {
    /// The key whose read last succeeded, or nil before the first success.
    public private(set) var loadedKey: Key?

    /// Creates a gate that has loaded nothing yet.
    public init() {}

    /// Whether a view showing `key` still has to load.
    ///
    /// - Parameter key: The view's current load key (its `.task(id:)` value).
    /// - Returns: False only when `key` already loaded successfully.
    public func needsLoad(for key: Key) -> Bool {
        loadedKey != key
    }

    /// Record that `key` loaded successfully; later appearances with it skip the load.
    ///
    /// - Parameter key: The key the successful read was made for.
    public mutating func markLoaded(_ key: Key) {
        loadedKey = key
    }

    /// Forget the loaded key, so the next appearance loads again.
    public mutating func reset() {
        loadedKey = nil
    }
}
