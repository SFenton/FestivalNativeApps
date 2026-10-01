import Foundation
import SwiftUI
import FestivalCore

// MARK: - Debug mode

/// How the launch "What's New" sheet behaves, driven by `FST_DEBUG_WHATS_NEW` (sibling of
/// `FST_DEBUG_FIRST_RUN`, see `FirstRunDebugMode`).
///
/// Debug builds default to `.off` so other lanes' screenshot and XCUITest runs never meet an
/// unexpected launch sheet; Release always behaves as `.normal`.
enum WhatsNewDebugMode: Equatable, Sendable {
    /// Never auto-present (Debug default). Settings replay still works.
    case off
    /// Real gate: present when the stored changelog hash differs (`on`, Release).
    case normal
    /// Forget the stored dismissal once at launch, then behave as `.normal` (`fresh`).
    case fresh
    /// Present on every launch regardless of the stored dismissal (`force`).
    case force

    /// Resolve from the process environment.
    ///
    /// - Parameter environment: Process environment (injectable for tests).
    /// - Returns: `.off` by default in Debug; always `.normal` in Release.
    static func resolve(environment: [String: String]) -> WhatsNewDebugMode {
        #if DEBUG
        switch environment["FST_DEBUG_WHATS_NEW"] {
        case "on": .normal
        case "fresh": .fresh
        case "force": .force
        default: .off
        }
        #else
        .normal
        #endif
    }
}

// MARK: - Gate

/// Pure launch gate for the "What's New" sheet, mirroring the web's `App.tsx`
/// `hasNewChangelog && !changelogDismissed && !activeCarouselKey`.
enum WhatsNewGate {
    /// Slot key claimed in `FirstRunCenter` while the sheet is up, so no first-run carousel can
    /// present over it (and vice versa).
    static let slotKey = "whats-new"

    /// Delay before checking, so a launch page's first-run carousel (evaluated in `onAppear`)
    /// claims the shared slot first — the web shows the carousel before the changelog.
    static let settleDelay: Duration = .milliseconds(700)

    /// Whether this launch owes the user the sheet.
    ///
    /// - Parameters:
    ///   - mode: Resolved debug mode.
    ///   - hasUnseenChangelog: `ChangelogSeenStore.shouldShow()` after any `.fresh` reset.
    /// - Returns: True when the sheet should present once the carousel slot is free.
    static func isPending(mode: WhatsNewDebugMode, hasUnseenChangelog: Bool) -> Bool {
        switch mode {
        case .off: false
        case .force: true
        case .normal, .fresh: hasUnseenChangelog
        }
    }

    /// App version shown in the title and stored on dismissal.
    ///
    /// - Parameter info: Bundle info dictionary.
    /// - Returns: `CFBundleShortVersionString`, or an empty string.
    static func appVersion(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        (info?["CFBundleShortVersionString"] as? String) ?? ""
    }
}

// MARK: - Launcher

/// Once-per-process launch state for the sheet: resolves the gate once (a `.fresh` reset or a
/// presentation happens once per launch, not once per root re-creation), claims the shared
/// first-run slot to present, and records dismissal.
@MainActor
final class WhatsNewLauncher {
    /// The app's launcher; tests create their own.
    static let shared = WhatsNewLauncher()

    private let store: ChangelogSeenStore
    private let environment: [String: String]
    private let changelogHash: String
    private(set) var resolved = false
    private(set) var pending = false

    /// Create a launcher.
    ///
    /// - Parameters:
    ///   - store: Dismissal persistence.
    ///   - environment: Launch environment for `WhatsNewDebugMode`.
    ///   - changelogHash: Hash of the changelog to gate on (the bundled `WhatsNew.json` in the app).
    init(
        store: ChangelogSeenStore = ChangelogSeenStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        changelogHash: String = Changelog.currentHash
    ) {
        self.store = store
        self.environment = environment
        self.changelogHash = changelogHash
    }

    /// Resolve the gate the first time only.
    ///
    /// - Returns: Whether the sheet is still owed this launch.
    @discardableResult
    func resolveIfNeeded() -> Bool {
        if !resolved {
            resolved = true
            let mode = WhatsNewDebugMode.resolve(environment: environment)
            if mode == .fresh { store.reset() }
            pending = WhatsNewGate.isPending(mode: mode, hasUnseenChangelog: store.shouldShow(hash: changelogHash))
        }
        return pending
    }

    /// Claim the one-sheet slot and consume the pending presentation.
    ///
    /// - Parameter center: Session first-run coordinator.
    /// - Returns: True when the caller should present now.
    func claim(in center: FirstRunCenter) -> Bool {
        guard pending, center.claim(WhatsNewGate.slotKey) else { return false }
        pending = false
        return true
    }

    /// Persist dismissal (the web writes `{ version, hash }` on Dismiss) and free the slot.
    ///
    /// - Parameters:
    ///   - center: Session first-run coordinator.
    ///   - version: App version shown in the sheet.
    func finish(in center: FirstRunCenter, version: String = WhatsNewGate.appVersion()) {
        store.markSeen(version: version, hash: changelogHash)
        center.release(WhatsNewGate.slotKey)
    }
}

// MARK: - Launch presentation

/// Presents "What's New" once per changelog after the launch page's first-run carousel, and
/// persists dismissal. Applied once at the app root (`FestivalRootView`).
struct WhatsNewLaunchModifier: ViewModifier {
    let session: FestivalSession
    var launcher: WhatsNewLauncher = .shared

    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .task { await presentWhenSettled() }
            .onChange(of: session.firstRunCenter.activeKey) { _, key in
                guard key == nil else { return }
                Task { await presentWhenSettled() }
            }
            .whatsNewPresentation(isPresented: $presented, onDismiss: { launcher.finish(in: session.firstRunCenter) }) {
                WhatsNewSheet(
                    version: WhatsNewGate.appVersion(),
                    entries: Changelog.displayEntries()
                ) { presented = false }
            }
    }

    /// Wait for the launch carousel to claim the slot, then present if nothing else holds it.
    @MainActor private func presentWhenSettled() async {
        guard launcher.resolveIfNeeded(), !presented else { return }
        try? await Task.sleep(for: WhatsNewGate.settleDelay)
        guard !presented, launcher.claim(in: session.firstRunCenter) else { return }
        presented = true
    }
}

extension View {
    /// Present the "What's New" changelog once per changelog version at launch.
    ///
    /// - Parameter session: Shared session (its first-run coordinator arbitrates the one
    ///   onboarding sheet at a time).
    /// - Returns: The content with the launch presentation attached.
    func whatsNew(session: FestivalSession) -> some View {
        modifier(WhatsNewLaunchModifier(session: session))
    }
}
