import Foundation

// MARK: - First-run coordination

extension FestivalSession {
    /// Weakly keyed store so each session owns exactly one first-run coordinator, following the
    /// same pattern as `backgroundCoordinator` in `FestivalSession+Artwork.swift`. Kept outside
    /// `FestivalSession` so the First-Run Experiences lane owns it without editing the session's
    /// main file.
    @MainActor
    private enum FirstRunRegistry {
        struct Entry {
            weak var session: FestivalSession?
            let center: FirstRunCenter
        }

        static var entries: [ObjectIdentifier: Entry] = [:]
    }

    /// The single first-run coordinator shared by every page of this session: it holds the
    /// persisted seen-state store and arbitrates "one carousel at a time" across every page that
    /// applies `.firstRun(page:session:)`, mirroring the web's `activeCarouselKey`.
    var firstRunCenter: FirstRunCenter {
        let key = ObjectIdentifier(self)
        if let entry = FirstRunRegistry.entries[key], entry.session === self {
            return entry.center
        }
        FirstRunRegistry.entries = FirstRunRegistry.entries.filter { $0.value.session != nil }
        let created = FirstRunCenter()
        FirstRunRegistry.entries[key] = FirstRunRegistry.Entry(session: self, center: created)
        return created
    }
}
