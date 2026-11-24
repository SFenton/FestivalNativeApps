#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Page registration

/// A page's declared background: the UIKit counterpart of `.festivalBackground(_:session:visible:)`.
///
/// The window root draws the one shared backdrop (``UKBackgroundView``); a page only says
/// which mode it wants, and the most recently appeared, still visible page wins, which
/// resolves tab switches and pushes/pops without pages knowing about each other. Forward
/// the controller's lifecycle:
///
/// ```swift
/// private lazy var background = UKBackgroundRegistration(session: context.session, mode: .carousel)
/// override func viewWillAppear(_ animated: Bool) {
///     super.viewWillAppear(animated)
///     background.viewWillAppear()
/// }
/// override func viewDidDisappear(_ animated: Bool) {
///     super.viewDidDisappear(animated)
///     background.viewDidDisappear()
/// }
/// ```
///
/// Song Detail and the song leaderboards use `mode: .song(art)` and call
/// ``update(mode:)`` when their song's art path becomes known. UIKit calls the incoming
/// page's `viewWillAppear` before the outgoing page's `viewDidDisappear`, as SwiftUI calls
/// `onAppear` before `onDisappear`, so a pop animates the shared backdrop from the song's
/// cover back to the carousel. The page's own view must be transparent so the root's
/// backdrop shows through.
@MainActor
final class UKBackgroundRegistration {
    private let coordinator: FestivalBackgroundCoordinator
    private let token = UUID()
    private var mode: ArtworkBackgroundMode
    private var visible: Bool
    private var appeared = false

    /// Whether this page claims the background. False for a split's trailing pane, whose
    /// parent page decides the split's background (`SplitPaneChrome.registersBackground`).
    var registers: Bool {
        didSet {
            guard registers != oldValue, appeared else { return }
            if registers {
                coordinator.appear(token, mode: mode, visible: visible)
            } else {
                coordinator.disappear(token)
            }
        }
    }

    /// Declares a page's background.
    ///
    /// - Parameters:
    ///   - session: Owner of the shared coordinator.
    ///   - mode: `.carousel` for the animated album wall, `.song(art)` for a fixed album.
    ///   - visible: False while the page is covered, so it never claims the background.
    ///   - registers: False for a trailing split pane.
    init(
        session: FestivalSession, mode: ArtworkBackgroundMode, visible: Bool = true,
        registers: Bool = true
    ) {
        coordinator = session.backgroundCoordinator
        self.mode = mode
        self.visible = visible
        self.registers = registers
    }

    deinit {
        // A released page must not keep claiming the backdrop.
        let coordinator = coordinator, token = token
        Task { @MainActor in coordinator.disappear(token) }
    }

    /// Forward from `viewWillAppear(_:)`.
    func viewWillAppear() {
        appeared = true
        if registers { coordinator.appear(token, mode: mode, visible: visible) }
    }

    /// Forward from `viewDidDisappear(_:)`.
    func viewDidDisappear() {
        appeared = false
        coordinator.disappear(token)
    }

    /// Change the declared mode (a song's art path arrived) without re-ordering the page.
    ///
    /// - Parameter mode: The new mode.
    func update(mode: ArtworkBackgroundMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        if appeared && registers { coordinator.update(token, mode: mode, visible: visible) }
    }

    /// Change the page's own visibility (regaining it counts as a fresh appearance).
    ///
    /// - Parameter visible: False while the page is covered in its own stack.
    func update(visible: Bool) {
        guard visible != self.visible else { return }
        self.visible = visible
        if appeared && registers { coordinator.update(token, mode: mode, visible: visible) }
    }

    /// Whether another visible page currently owns the background.
    var isCovered: Bool { coordinator.isCovered(token) }
}

// MARK: - Sheet coverage

/// Pauses the backdrop beneath a presented sheet: the UIKit counterpart of
/// `pausesFestivalBackdrop()`. Hold one per sheet and forward its controller's lifecycle;
/// the pause is balanced even if both calls repeat.
@MainActor
final class UKSheetCoverageToken {
    private var registered = false

    init() {}

    deinit {
        if registered { Task { @MainActor in FestivalSheetCoverage.shared.end() } }
    }

    /// Forward from `viewWillAppear(_:)` (or the presentation).
    func begin() {
        guard !registered else { return }
        registered = true
        FestivalSheetCoverage.shared.begin()
    }

    /// Forward from `viewDidDisappear(_:)` (or the dismissal).
    func end() {
        guard registered else { return }
        registered = false
        FestivalSheetCoverage.shared.end()
    }
}
#endif
