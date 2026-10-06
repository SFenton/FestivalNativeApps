import Foundation
import FestivalCore
import SwiftUI

// MARK: - Live connection owner

/// Owns the one live publication socket of a ``FestivalSession`` (issue #304), like the
/// web's single shared `useAppWebSocket` connection.
///
/// Windows hold **demand** with a token while their scene is active or inactive, and give
/// it back in the background or when they close, so iPad multiple windows share one socket
/// and a backgrounded app keeps none open. Coming back to the foreground re-reads the
/// publication at once (the loop's first round), like the web's resume recovery.
@MainActor
final class PublicationLiveConnection {
    private let socket: any PublicationLiveSocket
    private let sleep: @Sendable (Duration) async throws -> Void
    private var demand: Set<UUID> = []
    private var task: Task<Void, Never>?

    /// Create an idle connection owner.
    ///
    /// - Parameters:
    ///   - socket: Opens the public `/api/ws` socket.
    ///   - sleep: Waits between reconnect attempts (injectable for tests).
    init(
        socket: any PublicationLiveSocket = URLSessionPublicationLiveSocket(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.socket = socket
        self.sleep = sleep
    }

    /// Whether the live loop is running.
    var isRunning: Bool { task != nil }

    /// Hold demand for one window; the first holder starts the loop.
    ///
    /// - Parameters:
    ///   - token: The window's stable token.
    ///   - session: The session whose publication the loop refreshes.
    func acquire(_ token: UUID, session: FestivalSession) {
        demand.insert(token)
        guard task == nil, let client = try? session.client() else { return }
        let socket = socket
        let sleep = sleep
        task = Task {
            await PublicationLiveUpdates.run(
                refresh: { try await session.refreshPublication().publicationId },
                url: { try client.liveUpdatesURL(publicationId: $0) },
                connect: { socket.connect(to: $0) },
                sleep: sleep
            )
        }
    }

    /// Give back one window's demand; the last holder stops the loop and closes the socket.
    ///
    /// - Parameter token: The window's token.
    func release(_ token: UUID) {
        demand.remove(token)
        guard demand.isEmpty else { return }
        task?.cancel()
        task = nil
    }

    /// Whether this launch keeps a live publication socket.
    ///
    /// On by default for the public service. Off for a Debug loopback fixture server
    /// (the mock service has no socket; fixture journeys change publications on demand),
    /// unless `FST_LIVE_PUBLICATION_UPDATES` is `1` (or `0` to force it off).
    ///
    /// - Parameter environment: Launch environment.
    /// - Returns: True when the root should create a live connection.
    nonisolated static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        #if DEBUG
        if let raw = environment["FST_LIVE_PUBLICATION_UPDATES"] { return raw == "1" }
        if let raw = environment["FST_API_BASE_URL"], let host = URL(string: raw)?.host,
           ["localhost", "127.0.0.1", "::1"].contains(host) {
            return false
        }
        #endif
        return true
    }
}

// MARK: - Window demand

/// Holds a window's live-update demand while its scene is not in the background.
private struct PublicationLiveUpdatesModifier: ViewModifier {
    let session: FestivalSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { update(scenePhase) }
            .onChange(of: scenePhase) { _, phase in update(phase) }
            .onDisappear { session.releaseLiveUpdates(token) }
    }

    /// Hold demand unless the scene is in the background.
    ///
    /// - Parameter phase: The window's scene phase.
    private func update(_ phase: ScenePhase) {
        if phase == .background {
            session.releaseLiveUpdates(token)
        } else {
            session.acquireLiveUpdates(token)
        }
    }
}

extension View {
    /// Keep the session's live publication socket open while this window is in the
    /// foreground (issue #304). Apply once per window root.
    ///
    /// - Parameter session: Shared app session.
    /// - Returns: The view, holding live-update demand.
    func publicationLiveUpdates(session: FestivalSession) -> some View {
        modifier(PublicationLiveUpdatesModifier(session: session))
    }
}
