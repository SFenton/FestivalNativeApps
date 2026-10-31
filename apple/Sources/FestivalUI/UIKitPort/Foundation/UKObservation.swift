#if os(iOS)
import Observation
import UIKit

// MARK: - Observation binding

/// Binds UIKit to `@Observable` models (``FestivalSession`` and the screen models) the
/// way SwiftUI's view graph does: `apply` runs once now, records every observable
/// property it reads, and runs again on the main actor after any of them changes.
/// Several changes in one run-loop turn cost one re-run.
///
/// Keep the returned object for as long as the binding should live (``UKObservationBag``
/// does this for a view or controller); dropping it stops the updates.
@MainActor
final class UKObservation {
    private let apply: @MainActor () -> Void
    private var isScheduled = false
    private var isCancelled = false

    /// Starts observing.
    ///
    /// - Parameter apply: Reads observable state and writes it into views. Runs now and
    ///   after every change to what it read.
    init(_ apply: @escaping @MainActor () -> Void) {
        self.apply = apply
        run()
    }

    /// Stops the updates.
    func cancel() { isCancelled = true }

    private func run() {
        guard !isCancelled else { return }
        withObservationTracking { apply() } onChange: { [weak self] in
            // `onChange` fires in the mutation's `willSet`, on whatever thread mutated:
            // hop to the main actor and read the new value on the next turn, once for
            // any number of changes.
            Task { @MainActor [weak self] in self?.schedule() }
        }
    }

    private func schedule() {
        guard !isScheduled, !isCancelled else { return }
        isScheduled = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isScheduled = false
                self.run()
            }
        }
    }
}

/// Holds a view's or controller's observations; they end with it.
@MainActor
final class UKObservationBag {
    private var observations: [UKObservation] = []

    init() {}

    /// Observes `apply` (``UKObservation``) for the bag's lifetime.
    ///
    /// - Parameter apply: Reads observable state and writes it into views.
    func observe(_ apply: @escaping @MainActor () -> Void) {
        observations.append(UKObservation(apply))
    }

    /// Ends every observation, for a reused cell before it binds to another model.
    func removeAll() {
        observations.forEach { $0.cancel() }
        observations.removeAll()
    }
}
#endif
