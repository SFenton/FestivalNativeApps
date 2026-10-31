#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Context

/// What the SwiftUI app hands down through initializers and `@Environment`, handed down
/// explicitly: every UIKit screen takes the context it was created in and passes it (or
/// a copy with one value changed) to the screens and views it creates.
///
/// Orchestrator-owned: add a field here rather than reaching for a singleton.
@MainActor
struct UKContext {
    /// The process's one session (publication, catalogue, selected profile, caches).
    var session: FestivalSession
    /// The shell that owns this screen's stack; nil in an isolated screen (a test host).
    weak var navigator: (any UKNavigating)?
    /// The section whose stack this screen is in.
    var section: FestivalSection?
    /// Window layout and shell chrome the shell publishes (``UKShellState``); nil before
    /// the shell's first layout pass and in a test host.
    var shell: UKShellState?
    /// A page in a section stack, or the inside of a sheet.
    var surface: UKSurface = .page

    /// Creates a context.
    ///
    /// - Parameters:
    ///   - session: The process's session.
    ///   - navigator: The shell, if any.
    init(session: FestivalSession, navigator: (any UKNavigating)? = nil) {
        self.session = session
        self.navigator = navigator
    }

    /// A copy with one value changed: `context.with { $0.surface = .sheet }`.
    ///
    /// - Parameter change: Edits the copy.
    /// - Returns: The edited copy.
    func with(_ change: (inout UKContext) -> Void) -> UKContext {
        var copy = self
        change(&copy)
        return copy
    }

    /// Chart instruments Settings shows (`fst.settings.show*`), as the SwiftUI shell's
    /// `visibleInstruments` computes them.
    var visibleInstruments: Set<Instrument> { UKSettings.visibleInstruments() }
}

/// Where a screen is drawn.
enum UKSurface: Sendable, Equatable {
    /// A page in a section's navigation stack, over the shared artwork background.
    case page
    /// The inside of a sheet (`festivalSheet` in SwiftUI).
    case sheet
}

// MARK: - Shell state

/// The window facts the SwiftUI shell publishes into the environment
/// (`publishesDeviceLayout`, ``ShellPresentation``), published by the UIKit shell as an
/// observable object so a page that reads it inside a ``UKObservation`` follows a fold,
/// rotation or window resize.
@MainActor
@Observable
final class UKShellState {
    /// The resolved device layout (pose, hinge, width class, safe area).
    var layout: DeviceLayout?
    /// The shell's navigation style and section set for the window.
    var presentation: ShellPresentation?
    /// The selected root section (underneath Search while it is open). Shell lane.
    var selectedSection: FestivalSection?
    /// The Search tab (or the iPad flyout's Search row) is showing. Shell lane.
    var searchActive = false
    /// The drawer or flyout is open. Shell lane.
    var drawerPresented = false
    /// Whether the section on screen has a split open beside its list page. Shell lane.
    var splitOpen = false

    init() {}
}

// MARK: - Navigation

/// What a page asks the shell to do: the UIKit counterpart of the SwiftUI path bindings,
/// `FestivalShellCommands` and the drawer intents.
@MainActor
protocol UKNavigating: AnyObject {
    /// Pushes a route on the current section's stack.
    func push(_ route: AppRoute)
    /// Pops the current section's top page.
    func pop()
    /// Replaces the top page of the current section's stack (pagers, in-place switches).
    func replaceTop(with route: AppRoute)
    /// Selects a root section (re-selecting the current one pops it to its root).
    func select(_ section: FestivalSection)
    /// Opens the app drawer (flyout).
    func openDrawer()
    /// Presents the profile sheet from the profile button.
    func presentProfile()
    // MARK: Additive (Shell lane)
    /// Opens a list row's detail: beside the list page in a split window, else pushed.
    func selectDetail(_ route: AppRoute)
    /// Closes the open item beside the list page; returns whether one was open.
    @discardableResult func closeDetail() -> Bool
    /// Presents a controller as a sheet over the window (profile, notifications, filters).
    func presentSheet(_ controller: UIViewController, detents: [UISheetPresentationController.Detent]?)
    /// Opens global search (the Search tab or the iPad flyout's Search row).
    func openSearch()
    /// Presents the notifications sheet from the bell.
    func presentNotifications()
}

extension UKNavigating {
    func selectDetail(_ route: AppRoute) { push(route) }
    @discardableResult func closeDetail() -> Bool { false }
    func presentSheet(_ controller: UIViewController, detents: [UISheetPresentationController.Detent]? = nil) {}
    func openSearch() {}
    func presentNotifications() {}
}
#endif
