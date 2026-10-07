import SwiftUI
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
    /// Tells the root shell whether a section's trailing pane is open (Escape and the
    /// iPad menu bar's Close); nil outside the root shell.
    @Entry var splitOpenReporter: SplitOpenReporter?
    /// The root `TabView`'s bar is hidden on every page (the iPad flyout shell).
    @Entry var hidesRootTabBar = false
    /// The row to give assistive-technology focus back to after the trailing pane closed.
    @Entry var listDetailFocusReturn: ListDetailFocusReturn?
}

/// Asks the leading pane's row for `route` to take assistive-technology focus: the
/// trailing pane just closed (Close, Escape, Back), so focus goes back to the item the
/// person opened rather than the top of the window. A new `token` asks again.
struct ListDetailFocusReturn: Equatable, Sendable {
    let route: AppRoute
    let token: Int
}

extension View {
    /// Hide the root tab bar on this page in the iPad flyout shell; a no-op elsewhere
    /// (iPhone and compact windows keep their tab bar untouched).
    ///
    /// - Returns: The page.
    func rootTabBarVisibility() -> some View {
        modifier(RootTabBarVisibility())
    }
}

/// Implementation of ``SwiftUI/View/rootTabBarVisibility()``.
private struct RootTabBarVisibility: ViewModifier {
    @Environment(\.hidesRootTabBar) private var hidden

    func body(content: Content) -> some View {
        #if os(iOS)
        if hidden {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Reports whether a section's trailing pane is open.
///
/// Equatable as always-equal: the root re-creates the closure on each pass and it only
/// writes root-owned state (same reasoning as `OpenProfileAction`).
struct SplitOpenReporter: Equatable {
    let report: @MainActor (FestivalSection, Bool) -> Void

    /// Record whether `section` shows its trailing pane.
    @MainActor func callAsFunction(_ section: FestivalSection, isOpen: Bool) { report(section, isOpen) }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
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

    /// Create an action.
    ///
    /// - Parameters:
    ///   - section: Section whose path the action writes.
    ///   - page: List page on top, deciding which routes open in the trailing pane.
    ///   - action: Writes the route.
    init(section: FestivalSection, page: OnDemandSplitPolicy.ListPage? = nil, action: @escaping (AppRoute) -> Void) {
        self.section = section
        self.page = page
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.paneWidth == rhs.paneWidth && lhs.role == rhs.role && lhs.selection == rhs.selection
            && lhs.select == rhs.select && lhs.topScrim === rhs.topScrim && lhs.focusReturn == rhs.focusReturn
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
                role: context?.role, isOpen: context?.paneWidth != nil
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
}

// MARK: - Split layout

/// The two panes of an on-demand split, laid out by ``OnDemandSplitPolicy/Geometry``:
/// the leading pane fills the container until an item opens, then springs to the
/// leading half while the trailing pane slides in from the trailing edge (Reduce
/// Motion: a crossfade). A hairline divider sits at the exact midpoint, or the iPhone
/// Duo hinge band. Shared by iPad, iPhone Duo and the Mac content area.
///
/// With a `backdrop` it draws the session's one backdrop behind both panes and the
/// divider band (the pages inside draw none; `SplitPaneChrome`), whether or not an item
/// is open, so opening and closing never change the image under the list.
struct OnDemandSplitLayout<Leading: View, Trailing: View>: View {
    /// Pane geometry while the trailing pane shows, else nil (leading fills the width).
    let geometry: OnDemandSplitPolicy.Geometry?
    /// The shared backdrop to draw behind both panes, or nil (pages draw their own).
    let backdrop: FestivalBackgroundCoordinator?
    /// The leading page's top-scrim height, drawn across the divider band too.
    let topScrimHeight: CGFloat?
    let leading: Leading
    let trailing: Trailing

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    /// Create the layout.
    ///
    /// - Parameters:
    ///   - geometry: Pane geometry while an item is open, else nil.
    ///   - backdrop: The shared backdrop to draw behind both panes, or nil.
    ///   - topScrimHeight: The leading page's top-scrim height, or nil.
    ///   - leading: The list page's stack.
    ///   - trailing: The open item's stack (built only while `geometry` is set).
    init(
        geometry: OnDemandSplitPolicy.Geometry?,
        backdrop: FestivalBackgroundCoordinator? = nil, topScrimHeight: CGFloat? = nil,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.geometry = geometry
        self.backdrop = backdrop
        self.topScrimHeight = topScrimHeight
        self.leading = leading()
        self.trailing = trailing()
    }

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// Spring resize, or a short crossfade under Reduce Motion (HIG Motion).
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.88)
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: geometry?.leadingWidth)
                .frame(maxWidth: geometry == nil ? .infinity : nil)
            if let geometry {
                SplitDivider(width: geometry.dividerWidth, topScrimHeight: topScrimHeight)
                    .transition(.opacity)
                trailing
                    .frame(width: geometry.trailingWidth)
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
    }
}

/// The band between the panes: a hairline at its centre (the hinge itself on iPhone Duo),
/// over the panes' top-edge gradient so the darkening runs unbroken across the band.
private struct SplitDivider: View {
    let width: CGFloat
    let topScrimHeight: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
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

// MARK: - Split stack

/// A section's navigation on iOS (and the hosted macOS root used by tests; the Mac app
/// uses `MacListDetailStack`): one `FestivalTabStack` (iPhone, portrait, compact),
/// or an on-demand split in a landscape regular window (iPad, iPhone Duo inner display)
/// whenever a list page is on top (``OnDemandSplitPolicy``).
///
/// The leading pane's stack shows the path up to the list page and keeps its identity
/// whether or not an item is open, so opening and closing never rebuild the list (its
/// scroll position stays). The trailing pane has its own stack for the open item and
/// anything pushed from it, with a Close button (Escape) on its root.
struct OnDemandSplitStack<Root: View>: View {
    let section: FestivalSection
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @Binding var path: [AppRoute]
    let isVisible: Bool
    /// Builds the section root, given whether it is the top of its stack.
    let root: (Bool) -> Root

    @Environment(\.deviceLayout) private var layout
    @Environment(\.splitOpenReporter) private var openReporter
    /// The container's frame in window coordinates (for the midpoint and the hinge).
    @State private var container: CGRect = .zero
    /// The leading page's top-scrim height, shared with the trailing pane and the band.
    @State private var topScrim = SplitTopScrim()
    /// Assistive-technology focus moves: into the trailing pane when it opens, back to
    /// the opened row when it closes (`voiceover.md`).
    @State private var trailingFocus: AccessibilityFocusRequest?
    @State private var focusReturn: ListDetailFocusReturn?
    @State private var focusToken = 0
    /// The item most recently open in the trailing pane (the row to refocus on close).
    @State private var lastSelection: AppRoute?
    /// Whether the stacks are split-shaped; trails the window by a run-loop turn when a
    /// fold, rotation or resize changes what it allows (``OnDemandSplitPolicy/defersWindowChange(from:to:)``).
    @State private var appliedSplit: Bool?
    /// The last panes the window allowed, kept while a collapse is pending.
    @State private var heldGeometry: OnDemandSplitPolicy.Geometry?

    /// Create a section stack.
    ///
    /// - Parameters:
    ///   - section: Section owning the path.
    ///   - session: Shared app session.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - path: The section's navigation path.
    ///   - isVisible: Whether this section is selected.
    ///   - root: Section root screen, given whether it is the top of its stack.
    init(
        section: FestivalSection, session: FestivalSession, visibleInstruments: Set<Instrument>,
        path: Binding<[AppRoute]>, isVisible: Bool, @ViewBuilder root: @escaping (Bool) -> Root
    ) {
        self.section = section
        self.session = session
        self.visibleInstruments = visibleInstruments
        _path = path
        self.isVisible = isVisible
        self.root = root
    }

    private var cut: OnDemandSplitPolicy.Cut? { OnDemandSplitPolicy.cut(section: section, path: path) }

    /// The panes the window allows now, whatever page is on top, or nil.
    private var windowGeometry: OnDemandSplitPolicy.Geometry? {
        OnDemandSplitPolicy.geometry(OnDemandSplitPolicy.context(layout: layout, container: container))
    }

    /// What the window allows now, for deferring shape changes.
    private var windowState: OnDemandSplitPolicy.WindowState {
        OnDemandSplitPolicy.WindowState(measured: container.width > 0, allowsSplit: windowGeometry != nil)
    }

    /// The panes for the list page on top, or nil, as the stacks have applied them.
    private var geometry: OnDemandSplitPolicy.Geometry? {
        guard cut != nil else { return nil }
        return OnDemandSplitPolicy.appliedGeometry(live: windowGeometry, held: heldGeometry, applied: appliedSplit)
    }

    var body: some View {
        let _ = MainThreadStallMonitor.count("splitstack.body")
        let cut = cut
        let geometry = geometry
        let open = geometry != nil && cut?.selection != nil
        // While a split is possible (open or not) the container draws the one backdrop,
        // so opening and closing never change the image under the list.
        let sharesBackdrop = geometry != nil && SplitPaneChrome.sharesBackdrop
        OnDemandSplitLayout(
            geometry: open ? geometry : nil,
            backdrop: sharesBackdrop ? session.backgroundCoordinator : nil,
            topScrimHeight: topScrim.height
        ) {
            leadingStack(cut: geometry == nil ? nil : cut, paneWidth: open ? geometry?.leadingWidth : nil)
        } trailing: {
            if let cut, let selection = cut.selection, let geometry {
                trailingStack(cut: cut, selection: selection, width: geometry.trailingWidth)
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            if frame != container { container = frame }
        }
        .onChange(of: windowGeometry, initial: true) { _, live in
            if let live { heldGeometry = live }
        }
        .onChange(of: windowState, initial: true) { old, new in
            guard appliedSplit != nil, OnDemandSplitPolicy.defersWindowChange(from: old, to: new) else {
                appliedSplit = new.allowsSplit
                return
            }
            // Fold, rotation or resize: let the window's own update (size class, display,
            // tab bar) finish first, then push or split without animation (#346).
            DispatchQueue.main.async {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { appliedSplit = new.allowsSplit }
            }
        }
        .onChange(of: open, initial: true) { wasOpen, open in
            if isVisible { openReporter?(section, isOpen: open) }
            guard wasOpen != open else { return }
            focusToken += 1
            if open {
                trailingFocus = AccessibilityFocusRequest(target: .topHeading, token: focusToken)
            } else if geometry != nil, let lastSelection {
                // Closed in place (not a rotation to a push): back to the opened row.
                focusReturn = ListDetailFocusReturn(route: lastSelection, token: focusToken)
            }
        }
        .onChange(of: cut?.selection, initial: true) { _, selection in
            if let selection { lastSelection = selection }
        }
        .onChange(of: isVisible) { _, visible in
            if visible { openReporter?(section, isOpen: open) }
        }
    }

    // MARK: Leading pane

    /// The list page's stack: the whole path in one stack, or (split possible) the
    /// path up to the list page, its rows opening the trailing pane.
    ///
    /// - Parameters:
    ///   - cut: The path's cut while the window allows a split, else nil.
    ///   - paneWidth: The leading pane's width while an item is open.
    /// - Returns: The leading stack.
    private func leadingStack(cut: OnDemandSplitPolicy.Cut?, paneWidth: CGFloat?) -> some View {
        let binding = cut == nil ? $path : listPath
        let context = cut.map { cut in
            SplitPaneContext(
                paneWidth: paneWidth, role: .leading,
                selection: cut.selection,
                select: ListDetailSelectAction(section: section, page: cut.page) { route in open(route) },
                topScrim: topScrim,
                focusReturn: focusReturn
            )
        }
        return FestivalTabStack(
            session: session, visibleInstruments: visibleInstruments,
            path: binding, isVisible: isVisible, paneContext: context
        ) {
            root(binding.wrappedValue.isEmpty)
        }
    }

    /// The leading pane's path; writes go through ``OnDemandSplitPolicy/path(settingList:in:section:)``.
    private var listPath: Binding<[AppRoute]> {
        Binding {
            OnDemandSplitPolicy.cut(section: section, path: path)?.list ?? path
        } set: { newList in
            path = OnDemandSplitPolicy.path(settingList: newList, in: path, section: section)
        }
    }

    /// Open (or replace) the trailing pane's item.
    ///
    /// - Parameter route: A detail route of the list page on top.
    private func open(_ route: AppRoute) {
        path = OnDemandSplitPolicy.path(selecting: route, in: path, section: section)
    }

    /// Close the trailing pane: back to the full-width list page.
    private func close() {
        if let list = OnDemandSplitPolicy.pathClosingDetail(path, section: section) { path = list }
    }

    // MARK: Trailing pane

    /// The open item's stack, with a Close button on its root.
    ///
    /// - Parameters:
    ///   - cut: The path's cut.
    ///   - selection: The open item.
    ///   - width: The trailing pane's width.
    /// - Returns: The trailing stack.
    private func trailingStack(cut: OnDemandSplitPolicy.Cut, selection: AppRoute, width: CGFloat) -> some View {
        let context = SplitPaneContext(paneWidth: width, role: .trailing, topScrim: topScrim)
        return NavigationStack(path: detailTail) {
            destination(selection)
                .id(selection)
                // The same top-edge gradient as a full page, at the leading page's height.
                .modifier(TopEdgeScrim())
                .splitPaneContext(context)
                .rootTabBarVisibility()
                .menuBarColumn(isTop: isVisible && cut.detail.count == 1)
                .toolbar {
                    ToolbarItem(placement: SplitCloseButton.placement) {
                        SplitCloseButton { close() }
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route)
                        .modifier(TopEdgeScrim())
                        .splitPaneContext(context)
                        .rootTabBarVisibility()
                        .menuBarColumn(isTop: isVisible && cut.detail.last == route)
                }
        }
        // Focus lands on the pane's title once it slides in (HIG VoiceOver: inform
        // VoiceOver of layout changes).
        .accessibilityFocusMove(trailingFocus)
        // A container, so the identifier names the pane without replacing its rows' own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.split.trailing")
    }

    /// Routes after the detail root; writes go through
    /// ``OnDemandSplitPolicy/path(settingDetailTail:in:section:)``.
    private var detailTail: Binding<[AppRoute]> {
        Binding {
            Array((OnDemandSplitPolicy.cut(section: section, path: path)?.detail ?? []).dropFirst())
        } set: { tail in
            path = OnDemandSplitPolicy.path(settingDetailTail: tail, in: path, section: section)
        }
    }

    /// One route's screen, with the section's full path for screens that pop or replace.
    private func destination(_ route: AppRoute) -> some View {
        AppRouteDestination(
            route: route, session: session, visibleInstruments: visibleInstruments,
            path: $path, isVisible: isVisible
        )
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
