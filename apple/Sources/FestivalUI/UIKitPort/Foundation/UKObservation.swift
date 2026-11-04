#if os(iOS)
import FentonAppleCore
import UIKit

/// Preserves Festival's unlabeled initializer while delegating observation
/// tracking and scheduling to the shared FentonAppleCore binding.
@MainActor
final class UKObservation {
    private let binding: ObservationBinding

    init(_ apply: @escaping @MainActor () -> Void) {
        binding = ObservationBinding(apply: apply)
    }

    func cancel() {
        binding.cancel()
    }
}

/// Preserves the Festival bag API while keeping binding lifetime management shared.
@MainActor
final class UKObservationBag {
    private let bag = ObservationBag()

    init() {}

    func observe(_ apply: @escaping @MainActor () -> Void) {
        bag.observe(apply)
    }

    func removeAll() {
        bag.removeAll()
    }
}
#endif
