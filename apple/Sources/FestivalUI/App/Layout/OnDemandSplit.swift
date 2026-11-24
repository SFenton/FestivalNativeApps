import SwiftUI
import FestivalAppSupport
import FestivalCore
import FestivalDesign

// MARK: - Environment

/// Which half of an on-demand split a page is in.
enum SplitPaneRole: Sendable, Equatable {
    /// The list page's half (or the whole width while nothing is open).
    case leading
    /// The open item's half.
    case trailing
}

extension EnvironmentValues {
    /// The open item's route while a list page shows it in the trailing pane, else nil.
    /// List rows read it through ``SwiftUI/View/listDetailSelectable(_:)``.
    @Entry var listDetailSelection: AppRoute?
    /// Opens a route in the trailing pane; set on a list page only while the window
    /// allows a split. ``ListDetailLink`` uses it instead of pushing.
    @Entry var listDetailSelect: ListDetailSelectAction?
    /// The pane a page is in while a split is possible; nil in one full-width stack.
    @Entry var splitPane: SplitPaneRole?
    /// The row to give assistive-technology focus back to after the trailing pane closed.
    @Entry var listDetailFocusReturn: ListDetailFocusReturn?
    /// The list page beside this page while it is the root of a split's trailing pane;
    /// nil full width, in the leading pane and on pages pushed inside the trailing pane.
    /// Song Detail's boards drop the repeated song header beside it (#342;
    /// ``SongLeaderboardBoardLine/showsSongHeader(besideList:)``).
    @Entry var splitDetailBesideList: OnDemandSplitPolicy.ListPage?
    /// Whether the page is a split's sub-page: the item opened in the trailing pane
    /// beside its list page (even while a profile pushed over it covers the list), or a
    /// page pushed inside that pane while it is still half width. False full width and
    /// on pages pushed after a covering profile. Full leaderboards stay one column here
    /// (pattern `wide-columns` R1, issue #353; ``WideColumns/count(layout:size:besideList:)``).
    @Entry var splitPaneSubPage = false
}

/// Asks the leading pane's row for `route` to take assistive-technology focus: the
/// trailing pane just closed (Close, Escape, Back), so focus goes back to the item the
/// person opened rather than the top of the window. A new `token` asks again.
struct ListDetailFocusReturn: Equatable, Sendable {
    let route: AppRoute
    let token: Int
}

/// Opens a route in the trailing pane of the list page on top of the leading pane.
///
/// Equatable by section and list page only: the action always writes the same section
/// path, so a re-created closure must not count as a change (toolbar/rail churn).
struct ListDetailSelectAction: Equatable {
    let section: FestivalSection
    /// The list page whose detail routes this action opens; nil accepts every route
    /// (the shelved dual-source regions).
    let page: OnDemandSplitPolicy.ListPage?
    let action: (AppRoute) -> Void
    let closeAction: (() -> Void)?

    /// Create an action.
    ///
    /// - Parameters:
    ///   - section: Section whose path the action writes.
    ///   - page: List page on top, deciding which routes open in the trailing pane.
    ///   - close: Closes the trailing pane back to its placeholder, or nil where the
    ///     host has no placeholder to return to.
    ///   - action: Writes the route.
    init(
        section: FestivalSection, page: OnDemandSplitPolicy.ListPage? = nil,
        close: (() -> Void)? = nil, action: @escaping (AppRoute) -> Void
    ) {
        self.section = section
        self.page = page
        self.closeAction = close
        self.action = action
    }

    /// Whether a route opens in the trailing pane (else it is pushed full width).
    ///
    /// - Parameter route: A route a row on the list page opens.
    /// - Returns: True for the list page's detail routes.
    func accepts(_ route: AppRoute) -> Bool { page?.accepts(route) ?? true }

    /// Open a route in the trailing pane.
    ///
    /// - Parameter route: The detail route (for example `.rivalDetail`).
    func callAsFunction(_ route: AppRoute) { action(route) }

    /// Close the trailing pane (pattern `split-panes` R6: the open item's row left the
    /// list). Does nothing while no item is open.
    func close() { closeAction?() }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.section == rhs.section && lhs.page == rhs.page }
}

/// What every page of a split's stack needs: its pane width (for its own width class),
/// the open item and the select action (leading pane), its menu-bar role, and the
/// split's shared chrome (one backdrop, one top-scrim height; `SplitPaneChrome`).
struct SplitPaneContext: Equatable {
    /// The pane's width while the split is open, else nil (the window's layout applies).
    var paneWidth: CGFloat?
    /// The pane this stack is.
    var role: SplitPaneRole
    /// The open item (leading pane only).
    var selection: AppRoute?
    /// Opens a row's route in the trailing pane (leading pane only).
    var select: ListDetailSelectAction?
    /// The split's shared top-scrim height (iOS), or nil.
    var topScrim: SplitTopScrim?
    /// The row to refocus after the trailing pane closed (leading pane only).
    var focusReturn: ListDetailFocusReturn?
    /// The list page beside the pane (trailing pane's detail root only; pages pushed
    /// after it get nil through ``pushedPage``).
    var besideList: OnDemandSplitPolicy.ListPage?
    /// Whether the trailing pane covers the list page (a profile is open in it; issue
    /// #352), so its leading edge is the window's rather than the divider's.
    var coversList = false
    /// Whether this is the trailing pane's open item (its root), not a page pushed
    /// after it (``pushedPage``).
    var isOpenItem = true

    /// The context for a page pushed inside this pane: the same pane, but no longer the
    /// item opened beside the list page.
    var pushedPage: SplitPaneContext {
        var context = self
        context.besideList = nil
        context.isOpenItem = false
        return context
    }

    /// Whether a page with this context is a split's sub-page
    /// (``SwiftUI/EnvironmentValues/splitPaneSubPage``): the trailing pane's open item,
    /// or a page pushed inside the trailing pane while it sits beside the list page.
    var isSubPage: Bool { role == .trailing && (isOpenItem || !coversList) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.paneWidth == rhs.paneWidth && lhs.role == rhs.role && lhs.selection == rhs.selection
            && lhs.select == rhs.select && lhs.topScrim === rhs.topScrim && lhs.focusReturn == rhs.focusReturn
            && lhs.besideList == rhs.besideList && lhs.coversList == rhs.coversList
            && lhs.isOpenItem == rhs.isOpenItem
    }
}

extension View {
    /// Give one page of a split's stack its pane context (applied per page: custom
    /// environment values set on a `NavigationStack` did not reach its pushed pages on
    /// iOS 27.1). A no-op with no context, so iPhone pages are unchanged.
    ///
    /// - Parameter context: The pane context, or nil outside a split.
    /// - Returns: The page with pane environment.
    func splitPaneContext(_ context: SplitPaneContext?) -> some View {
        modifier(SplitPaneContextModifier(context: context))
    }
}

/// Implementation of ``SwiftUI/View/splitPaneContext(_:)``. Transforms rather than sets,
/// so its structure never changes and outer values pass through without a context.
private struct SplitPaneContextModifier: ViewModifier {
    let context: SplitPaneContext?

    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.deviceLayout) { layout in
                if let width = context?.paneWidth { layout = layout.column(width: width) }
            }
            .transformEnvironment(\.splitPane) { role in
                if let context { role = context.role }
            }
            .transformEnvironment(\.listDetailSelection) { selection in
                if let context { selection = context.selection }
            }
            .transformEnvironment(\.listDetailSelect) { select in
                if let context { select = context.select }
            }
            .transformEnvironment(\.listDetailFocusReturn) { focusReturn in
                if let context { focusReturn = context.focusReturn }
            }
            .transformEnvironment(\.splitDetailBesideList) { page in
                if let context { page = context.besideList }
            }
            .transformEnvironment(\.splitPaneSubPage) { subPage in
                if let context { subPage = context.isSubPage }
            }
            // One backdrop behind both panes: the page draws none and its navigation
            // container is clear (`SplitPaneChrome`).
            .modifier(SplitNavigationContainerBackground(clear: sharesBackdrop))
            .transformEnvironment(\.splitSharesBackdrop) { shares in
                if context != nil { shares = sharesBackdrop }
            }
            .transformEnvironment(\.splitTopScrim) { scrim in
                if let context { scrim = context.topScrim }
            }
            // The edge facing the divider is mid-window: a safe-area inset there belongs
            // to the window's far edge (the iPhone Duo vertical bar gave the leading pane
            // 84 pt of dead space beside the hinge), so the page lays out to the band.
            .ignoresSafeArea(.container, edges: SplitPaneChrome.edgesFacingDivider(
                role: context?.role, isOpen: sideBySide
            ))
            #if os(iOS)
            // Full-page bar margins at the pane's mid-window edges.
            .background {
                if context != nil {
                    SplitPaneBarMargins()
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
            #endif
    }

    private var sharesBackdrop: Bool { context != nil && SplitPaneChrome.sharesBackdrop }

    /// Whether the panes sit side by side, as ``SplitPaneChrome/edgesFacingDivider(role:isOpen:)``
    /// reads it for this pane.
    private var sideBySide: Bool {
        guard let context else { return false }
        return context.role == .trailing ? !context.coversList : context.paneWidth != nil
    }
}

// MARK: - Split layout

/// The two panes of an on-demand split, laid out by ``OnDemandSplitPolicy/Geometry``:
/// the leading pane fills the container until an item opens, then springs to the
/// leading half while the trailing pane slides in from the trailing edge (Reduce
/// Motion: a crossfade). The panes meet at a band at the exact midpoint, or the iPhone
/// Duo hinge, with no drawn divider (#344; a hairline only under the system's or the app's
/// Increase Contrast at a midpoint, ``OnDemandSplitPolicy/drawsDividerLine(_:increasedContrast:)``). Shared by
/// iPad, iPhone Duo and the Mac content area.
///
/// With a `backdrop` it draws the session's one backdrop behind both panes and the
/// divider band (the pages inside draw none; `SplitPaneChrome`), whether or not an item
/// is open, so opening and closing never change the image under the list.
///
/// While `covered` (a profile is open in the trailing pane; issue #352) the trailing
/// pane widens over the whole container and the leading pane keeps its frame, alive but
/// hidden from sight, touch and assistive technologies, so Back finds the list page as
/// it was. The views keep one structure in every state, so neither stack is rebuilt.
struct OnDemandSplitLayout<Leading: View, Trailing: View>: View {
    /// Pane geometry while the trailing pane shows, else nil (leading fills the width).
    let geometry: OnDemandSplitPolicy.Geometry?
    /// How the trailing pane covers the list page.
    let cover: OnDemandSplitPolicy.Cover
    /// The shared backdrop to draw behind both panes, or nil (pages draw their own).
    let backdrop: FestivalBackgroundCoordinator?
    /// The leading page's top-scrim height, drawn across the divider band too.
    let topScrimHeight: CGFloat?
    let leading: Leading
    let trailing: Trailing

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @AppStorage("fst.accessibility.moreContrast") private var appMoreContrast = false

    /// Create the layout.
    ///
    /// - Parameters:
    ///   - geometry: Pane geometry while an item is open, else nil.
    ///   - cover: How the trailing pane covers the list page (ignored without `geometry`).
    ///   - backdrop: The shared backdrop to draw behind both panes, or nil.
    ///   - topScrimHeight: The leading page's top-scrim height, or nil.
    ///   - leading: The list page's stack.
    ///   - trailing: The open item's stack (built only while `geometry` is set).
    init(
        geometry: OnDemandSplitPolicy.Geometry?, cover: OnDemandSplitPolicy.Cover = .none,
        backdrop: FestivalBackgroundCoordinator? = nil, topScrimHeight: CGFloat? = nil,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.geometry = geometry
        self.cover = geometry == nil ? .none : cover
        self.backdrop = backdrop
        self.topScrimHeight = topScrimHeight
        self.leading = leading()
        self.trailing = trailing()
    }

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// System or in-app Increase Contrast (#480: the app's toggle had left the band clear).
    private var increasedContrast: Bool { colorSchemeContrast == .increased || appMoreContrast }

    /// Spring resize, or a short crossfade under Reduce Motion (HIG Motion).
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.88)
    }

    var body: some View {
        let covered = cover != .none
        // The list page keeps the width it had before the profile opened.
        let leadingWidth = cover == .overList ? nil : geometry?.leadingWidth
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                leading
                    .frame(width: leadingWidth)
                    .frame(maxWidth: leadingWidth == nil ? .infinity : nil)
                    .opacity(covered ? 0 : 1)
                    .allowsHitTesting(!covered)
                    .accessibilityHidden(while: covered)
                if let geometry, cover != .overList {
                    SplitDivider(
                        width: geometry.dividerWidth, topScrimHeight: topScrimHeight,
                        drawsLine: OnDemandSplitPolicy.drawsDividerLine(
                            geometry, increasedContrast: increasedContrast
                        )
                    )
                    .opacity(covered ? 0 : 1)
                    .transition(.opacity)
                    Color.clear
                        .frame(width: geometry.trailingWidth)
                        .accessibilityHidden(true)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if let geometry {
                trailing
                    .frame(width: covered ? Self.fullWidth(geometry) : geometry.trailingWidth)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        // Always exactly the proposed size, never the panes' sum: the container measures
        // itself to place the divider, and a stale (wider) geometry would otherwise hold
        // the container at the old width after the window narrows.
        // Not clipped: pages draw their bars and scroll content into the safe areas.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
        // One backdrop for both panes and the band, outside the animation so it never
        // moves or fades while the panes resize.
        .background {
            if let backdrop { SplitBackdrop(coordinator: backdrop) }
        }
        .animation(Self.animation(reduceMotion: reduceMotion), value: geometry)
        .animation(Self.animation(reduceMotion: reduceMotion), value: cover)
    }

    /// The container's width: both panes and the band.
    ///
    /// - Parameter geometry: The pane geometry.
    /// - Returns: The width a covering trailing pane takes.
    static func fullWidth(_ geometry: OnDemandSplitPolicy.Geometry) -> CGFloat {
        geometry.leadingWidth + geometry.dividerWidth + geometry.trailingWidth
    }
}

/// The band between the panes (the hinge itself on iPhone Duo): clear, so the shared
/// backdrop runs unbroken across it, with the panes' top-edge gradient so the darkening
/// does too. It draws a hairline at its centre only when `drawsLine` (#344).
private struct SplitDivider: View {
    let width: CGFloat
    let topScrimHeight: CGFloat?
    let drawsLine: Bool

    var body: some View {
        Rectangle()
            .fill(drawsLine ? Color.white.opacity(0.16) : Color.clear)
            .frame(width: OnDemandSplitPolicy.midpointDividerWidth)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(alignment: .top) {
                if let topScrimHeight {
                    TopEdgeScrim.gradient.frame(height: topScrimHeight)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .accessibilityIdentifier("fst.split.divider")
    }
}

/// The trailing pane's Close button (Escape; HIG Split views: a way back to one pane).
struct SplitCloseButton: View {
    let action: () -> Void

    /// Leading in the pane's bar (iOS), the window toolbar's navigation area (macOS).
    static var placement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    var body: some View {
        Button(action: action) {
            Label("Close", systemImage: "xmark")
        }
        .keyboardShortcut(.escape, modifiers: [])
        .help("Close (Esc)")
        .accessibilityIdentifier("fst.split.close")
    }
}

/// Back on the leading pane's pushed list page (Song Detail, Full Rankings, …): it
/// closes the open item first and pops the page only once nothing is open (issue #347;
/// split-view.md "Close, Escape, ⌘[ or Back" closes the trailing pane). The standard
/// chevron with no text, as the system Back (HIG Toolbars: "prefer their standard
/// symbols without text labels").
struct SplitListBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.backward")
        }
        .help("Back (⌘[)")
        .accessibilityIdentifier("fst.split.list-back")
    }
}

// MARK: - Row selection

extension View {
    /// Mark a list row as the open item while its route shows in the trailing pane: a
    /// translucent accent overlay with a leading accent bar, plus the `isSelected`
    /// accessibility trait. A no-op outside a split.
    ///
    /// - Parameter route: The detail route this row opens.
    /// - Returns: The row with its selected state.
    func listDetailSelectable(_ route: AppRoute) -> some View {
        modifier(ListDetailSelectableRow(route: route))
    }
}

/// Selected-row treatment for ``SwiftUI/View/listDetailSelectable(_:)``.
private struct ListDetailSelectableRow: ViewModifier {
    let route: AppRoute
    @Environment(\.listDetailSelection) private var selection
    @Environment(\.listDetailFocusReturn) private var focusReturn
    @AccessibilityFocusState private var focused: Bool
    #if os(macOS)
    @Environment(\.macKeyboardNavigator) private var keyboard
    #endif

    func body(content: Content) -> some View {
        let selected = selection == route
        content
            #if os(macOS)
            // An overlay: Mac Song rows are opaque material cards. Accent while the list
            // has keyboard focus, gray otherwise (HIG Focus and selection, `NSTableView`).
            .overlay {
                if selected {
                    MacSelectionHighlight(cornerRadius: 12, focused: keyboard?.hasFocus ?? true)
                }
            }
            #else
            // Behind the row's text: drawn over it, the translucent fill washed the rivals
            // pills down to 4.0–4.3:1 (iPad audit, Lane A11Y3). iOS split rows are clear
            // (Songs, the opaque cards, never splits); the accent bar stays on top.
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BrandTokens.accentBlue.opacity(0.22))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(BrandTokens.accentBlue).frame(width: 3).padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            #endif
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityFocused($focused)
            .onChange(of: focusReturn) { _, request in
                guard let request, request.route == route else { return }
                focused = true
                AccessibilityFocusTrace.shared.record("row: \(route.focusTraceName)")
            }
    }
}

/// A `NavigationLink(value:)` that opens its route in the trailing pane when the list
/// page on top can split, and shows its selected state while open.
///
/// Drop-in for list rows. Where the window allows a split and the list page accepts the
/// route it is a button that opens the trailing pane (no push); everywhere else it is
/// the plain `NavigationLink`, so iPhone and portrait are unchanged.
struct ListDetailLink<Label: View>: View {
    let value: AppRoute
    let label: Label
    @Environment(\.listDetailSelect) private var select
    #if os(macOS)
    @Environment(\.macKeyboardNavigator) private var keyboard
    #endif

    /// Create a link.
    ///
    /// - Parameters:
    ///   - value: Route pushed (or shown in the trailing pane).
    ///   - label: Row content.
    init(value: AppRoute, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    /// The row content, with the Mac's hover tint and keyboard focus ring on its card.
    @ViewBuilder private var decoratedLabel: some View {
        #if os(macOS)
        label.modifier(MacRowInteractionEffect(cornerRadius: 12))
        #else
        label
        #endif
    }

    var body: some View {
        Group {
            if let select, select.accepts(value) {
                Button {
                    select(value)
                    #if os(macOS)
                    // A clicked row gives its list keyboard focus, so ↑/↓ continue from
                    // it (`MacKeyboardNavigation`).
                    keyboard?.requestFocus()
                    #endif
                } label: { decoratedLabel }
                    #if os(macOS)
                    // Return opens a keyboard-focused row, as Space does.
                    .onKeyPress(.return) {
                        select(value)
                        return .handled
                    }
                    #endif
            } else {
                NavigationLink(value: value) { decoratedLabel }
            }
        }
        .listDetailSelectable(value)
        #if os(iOS)
        // Pointer: the row's rounded card highlights (HIG Pointing devices: "hover for
        // large ones"; no scale, rows sit edge to edge).
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hoverEffect(.highlight)
        #endif
    }
}
