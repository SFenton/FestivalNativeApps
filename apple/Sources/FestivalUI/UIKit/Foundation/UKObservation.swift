#if os(iOS)
import FentonAppleCore
import UIKit

/// Preserves Festival's unlabeled initializer while delegating observation
/// tracking and scheduling to the shared FentonAppleCore binding.
@MainActor
final class UKObservation {
    private let binding: FentonObservation

    init(_ apply: @escaping @MainActor () -> Void) {
        binding = FentonObservation(apply)
    }

    func cancel() {
        binding.cancel()
    }
}

/// Preserves the Festival bag API while keeping binding lifetime management shared.
@MainActor
final class UKObservationBag {
    private let bag = FentonObservationBag()

    init() {}

    func observe(_ apply: @escaping @MainActor () -> Void) {
        bag.observe(apply)
    }

    func removeAll() {
        bag.removeAll()
    }
}
#endif
