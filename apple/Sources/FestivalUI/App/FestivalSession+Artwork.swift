import Foundation
import OSLog

// MARK: - Shared background coordination

extension FestivalSession {
    /// Weakly keyed store so each session owns exactly one background coordinator.
    @MainActor
    private enum BackgroundRegistry {
        struct Entry {
            weak var session: FestivalSession?
            let coordinator: FestivalBackgroundCoordinator
        }

        static var entries: [ObjectIdentifier: Entry] = [:]
    }

    /// The single background coordinator shared by every page of this session.
    ///
    /// Stored outside `FestivalSession` so the background lane owns it without
    /// editing the session's main file.
    var backgroundCoordinator: FestivalBackgroundCoordinator {
        let key = ObjectIdentifier(self)
        if let entry = BackgroundRegistry.entries[key], entry.session === self {
            return entry.coordinator
        }
        BackgroundRegistry.entries = BackgroundRegistry.entries.filter {
            $0.value.session != nil
        }
        let created = FestivalBackgroundCoordinator(session: self)
        BackgroundRegistry.entries[key] = .init(session: self, coordinator: created)
        return created
    }

    /// Load the catalogue for the carousel when no page has done so yet.
    ///
    /// Waits briefly so a Songs tab that is already loading the catalogue wins,
    /// then retries with bounded exponential backoff until art paths arrive.
    ///
    /// - Parameter grace: Delay before the first independent load.
    func loadArtworkCatalogIfNeeded(grace: Duration = .milliseconds(800)) async {
        guard artworkPaths.isEmpty else { return }
        do {
            try await Task.sleep(for: grace)
        } catch {
            return
        }
        var delay: Duration = .seconds(2)
        while !Task.isCancelled && artworkPaths.isEmpty {
            do {
                _ = try await catalog()
                return
            } catch is CancellationError {
                return
            } catch {
                Logger(
                    subsystem: "com.sfenton.festivalscoretracker",
                    category: "artwork-background"
                ).error("Carousel catalogue unavailable: \(error.localizedDescription)")
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            delay = min(delay * 2, .seconds(60))
        }
    }
}
