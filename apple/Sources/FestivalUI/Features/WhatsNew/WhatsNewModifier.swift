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

// MARK: - Launch presentation

/// Presents "What's New" once per changelog after the launch page's first-run carousel, and
/// persists dismissal. Applied once at the app root (`FestivalRootView`).
struct WhatsNewLaunchModifier: ViewModifier {
    let session: FestivalSession

    /// Process-wide so a `.fresh` reset or a presentation happens once per launch, not once per
    /// root re-creation (scene reconnects re-run `init`).
    @MainActor private static var launchResolved = false
    @MainActor private static var pending = false

    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .task { await presentWhenSettled() }
            .onChange(of: session.firstRunCenter.activeKey) { _, key in
                guard key == nil else { return }
                Task { await presentWhenSettled() }
            }
            .sheet(isPresented: $presented, onDismiss: finish) {
                WhatsNewSheet(
                    version: WhatsNewGate.appVersion(),
                    entries: Changelog.displayEntries()
                ) { presented = false }
            }
    }

    /// Resolve the gate once per process, wait for the launch carousel to claim the slot, then
    /// present if nothing else holds it.
    @MainActor private func presentWhenSettled() async {
        if !Self.launchResolved {
            Self.launchResolved = true
            let mode = WhatsNewDebugMode.resolve(environment: ProcessInfo.processInfo.environment)
            let store = ChangelogSeenStore()
            if mode == .fresh { store.reset() }
            Self.pending = WhatsNewGate.isPending(mode: mode, hasUnseenChangelog: store.shouldShow())
        }
        guard Self.pending, !presented else { return }
        try? await Task.sleep(for: WhatsNewGate.settleDelay)
        guard Self.pending, !presented, session.firstRunCenter.claim(WhatsNewGate.slotKey) else { return }
        Self.pending = false
        presented = true
    }

    /// Persist dismissal (the web writes `{ version, hash }` on Dismiss) and free the slot.
    @MainActor private func finish() {
        ChangelogSeenStore().markSeen(version: WhatsNewGate.appVersion())
        session.firstRunCenter.release(WhatsNewGate.slotKey)
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
