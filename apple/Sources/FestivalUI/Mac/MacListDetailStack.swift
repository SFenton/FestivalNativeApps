#if os(macOS)
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Mac stack

/// One `NavigationStack` with every `AppRoute` destination, for a Mac pane.
struct MacStack<Root: View>: View {
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @Binding var stackPath: [AppRoute]
    /// The destination's whole path, for screens that pop or replace.
    @Binding var fullPath: [AppRoute]
    let isVisible: Bool
    /// Whether this pane carries the window's global toolbar group (the leading or only
    /// pane): toolbar items placed outside a `NavigationStack` disappear once a page is
    /// pushed, so every page of this pane adds them.
    let providesGlobalToolbar: Bool
    /// Widest root content (``MacLayoutPolicy/pageMaxWidth(for:isShopRoot:)``).
    let rootMaxWidth: CGFloat
    /// The on-demand split context of a list page's pane: arrow keys and Return then
    /// open rows in the trailing pane (``MacKeyboardNavigation``).
    let paneContext: SplitPaneContext?
    /// Closes the trailing pane (Escape), while one is open beside this pane.
    let close: (() -> Void)?
    /// Whether a profile in the trailing pane covers this (list) pane (issue #352): its
    /// keys and page tools stand down while it is hidden.
    let isCovered: Bool
    let root: Root

    /// Create a pane stack.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - stackPath: This pane's path.
    ///   - fullPath: The destination's whole path.
    ///   - isVisible: Whether the destination is on screen.
    ///   - providesGlobalToolbar: Whether its pages carry the global toolbar group.
    ///   - rootMaxWidth: Widest root content.
    ///   - paneContext: The split context of a list page's pane, or nil.
    ///   - close: Closes the trailing pane, or nil.
    ///   - isCovered: Whether a profile in the trailing pane covers this pane.
    ///   - root: Pane root.
    init(
        session: FestivalSession, visibleInstruments: Set<Instrument>,
        stackPath: Binding<[AppRoute]>, fullPath: Binding<[AppRoute]>, isVisible: Bool,
        providesGlobalToolbar: Bool = true, rootMaxWidth: CGFloat = MacLayoutPolicy.pageMaxWidth(for: nil),
        paneContext: SplitPaneContext? = nil, close: (() -> Void)? = nil, isCovered: Bool = false,
        @ViewBuilder root: () -> Root
    ) {
        self.session = session
        self.visibleInstruments = visibleInstruments
        _stackPath = stackPath
        _fullPath = fullPath
        self.isVisible = isVisible
        self.providesGlobalToolbar = providesGlobalToolbar
        self.rootMaxWidth = rootMaxWidth
        self.paneContext = paneContext
        self.close = close
        self.isCovered = isCovered
        self.root = root()
    }

    var body: some View {
        MacColumnLayoutReader { columnLayout in
            stack(columnLayout: columnLayout)
        }
        // Each pane publishes its own layout, so its pages pick one or two card
        // columns and readable widths from the pane's width, not the window's.
        .publishesDeviceLayout(usesSidebarShell: true)
    }

    /// The pane's `NavigationStack`. Pushed pages get the pane layout explicitly:
    /// an environment value published around the stack did not reach its pushed
    /// destinations (Band Detail read the default zero-width compact layout).
    private func stack(columnLayout: DeviceLayout) -> some View {
        let isList = paneContext?.selection != nil
        return NavigationStack(path: $stackPath) {
            root
                .modifier(MacKeyboardNavigation(
                    selection: paneContext?.selection, select: paneContext?.select, push: push,
                    isTop: stackPath.isEmpty, close: close, isEnabled: !isCovered
                ))
                .splitPaneContext(paneContext)
                .environment(\.macPageIsTop, stackPath.isEmpty)
                .environment(\.macColumnIsList, isList)
                .modifier(MacPageWidth(maxWidth: rootMaxWidth))
                // A covered page's own toolbar tools (Rank By, Quick Links) would join the
                // window toolbar beside the profile's: pages place them only without a
                // page-tools registry, so a covered pane hands its pages one nobody shows.
                .environment(\.pageToolsRegistry, isCovered ? coveredTools : nil)
                .modifier(MacGlobalToolbar(isEnabled: providesGlobalToolbar))
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(
                        route: route, session: session, visibleInstruments: visibleInstruments,
                        path: $fullPath, isVisible: isVisible
                    )
                    .modifier(MacKeyboardNavigation(
                        selection: paneContext?.selection, select: paneContext?.select, push: push,
                        isTop: stackPath.last == route, close: close, isEnabled: !isCovered
                    ))
                    .splitPaneContext(paneContext?.pushedPage)
                    .environment(\.macPageIsTop, stackPath.last == route)
                    .environment(\.macColumnIsList, isList)
                    .modifier(MacPageWidth(maxWidth: MacLayoutPolicy.pageMaxWidth(for: route)))
                    .modifier(MacGlobalToolbar(isEnabled: providesGlobalToolbar))
                    .environment(\.deviceLayout, columnLayout)
                }
        }
    }

    /// Collects (and discards) a covered page's tools.
    @State private var coveredTools = PageToolsRegistry()

    /// Return on a keyboard-highlighted row: push in this pane.
    private func push(_ route: AppRoute) {
        stackPath.append(route)
    }
}

/// Hands the published column layout to a builder (``MacStack`` passes it to pushed
/// pages explicitly).
private struct MacColumnLayoutReader<Content: View>: View {
    @Environment(\.deviceLayout) private var layout
    let content: (DeviceLayout) -> Content

    var body: some View { content(layout) }
}

/// Centres a page at most `maxWidth` wide in its column (web page max width).
struct MacPageWidth: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content.frame(maxWidth: maxWidth)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - On-demand split (Mac content area)

/// A Mac destination's content: one stack, split on demand
/// (`.agents/design/apple/split-view.md`). A list page (Rivals, Compete, Leaderboards,
/// Song Detail) starts full width; selecting a row splits the content area right of the
/// sidebar 50/50 at its exact midpoint, fixed (no drag), and shows the item in the
/// trailing pane; Close, Escape, ⌘[ or Back return to full width. A content area
/// narrower than two 360 pt panes pushes instead (``OnDemandSplitPolicy``).
///
/// Profiles are full pages (issue #352): a player or band opened from the list page, or
/// pushed in the trailing pane, widens the trailing pane over the whole content area
/// with a Back button, while the list page waits hidden behind it with its place kept.
///
/// While a list page is on top, both panes draw their top route as their root and turn
/// pushes into path writes: inside the window's `NavigationSplitView` a page pushed in a
/// nested stack covered both panes (or never showed). The leading pane keeps the list
/// page's identity while items open and close, so it keeps its scroll position;
/// switching between one stack and the split (a list page pushed or popped to) rebuilds
/// the page.
struct MacListDetailStack<Root: View>: View {
    let section: FestivalSection
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @Binding var path: [AppRoute]
    let isVisible: Bool
    /// Reports whether the trailing pane is open (Go › Back and Edit › Copy rules).
    let onSplitChange: (Bool) -> Void
    /// Builds the root page, given whether it is the top of its pane.
    let root: (Bool) -> Root

    /// The content area's width.
    @State private var width: CGFloat = 0

    private var cut: OnDemandSplitPolicy.Cut? { OnDemandSplitPolicy.cut(section: section, path: path) }

    /// The panes the content area allows for the list page on top, or nil.
    private var geometry: OnDemandSplitPolicy.Geometry? {
        guard cut != nil else { return nil }
        return OnDemandSplitPolicy.geometry(OnDemandSplitPolicy.Context(
            container: CGRect(x: 0, y: 0, width: width, height: 1),
            isLandscape: true, isRegular: true, hinge: nil
        ))
    }

    /// The two arrangements; a fresh identity for each, so the window's split view never
    /// keeps presenting one stack's pushed page over the other.
    private enum Arrangement { case stack, split }

    var body: some View {
        let geometry = geometry
        let splitCut: OnDemandSplitPolicy.Cut? = geometry == nil ? nil : cut
        let open = splitCut?.selection != nil
        let cover = splitCut?.cover ?? .none
        Group {
            if let splitCut {
                // One backdrop behind both panes while a list page is on top, open
                // or not (`SplitPaneChrome`).
                OnDemandSplitLayout(
                    geometry: open ? geometry : nil, cover: cover,
                    backdrop: SplitPaneChrome.sharesBackdrop ? session.backgroundCoordinator : nil
                ) {
                    leadingPane(cut: splitCut, open: open && cover == .none, covered: cover != .none)
                } trailing: {
                    if let top = splitCut.detail.last {
                        trailingPane(cut: splitCut, top: top)
                    }
                }
                .id(Arrangement.split)
            } else {
                MacStack(
                    session: session, visibleInstruments: visibleInstruments,
                    stackPath: $path, fullPath: $path, isVisible: isVisible
                ) {
                    root(path.isEmpty)
                }
                .id(Arrangement.stack)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // A covering profile is the page on screen: Go › Back and Edit › Copy treat it
        // as a full page.
        .onChange(of: open && cover == .none, initial: true) { _, open in onSplitChange(open) }
    }

    /// The leading pane while a list page is on top: the list page as its root (its
    /// identity stays while items open and close, so it keeps its scroll position), a
    /// Back button when it was pushed, and rows that open the trailing pane.
    ///
    /// - Parameters:
    ///   - cut: The path's cut.
    ///   - open: Whether the trailing pane is open beside it.
    ///   - covered: Whether a profile in the trailing pane covers it.
    /// - Returns: The leading pane.
    private func leadingPane(cut: OnDemandSplitPolicy.Cut, open: Bool, covered: Bool) -> some View {
        let context = SplitPaneContext(
            paneWidth: nil, role: .leading, selection: cut.selection,
            select: ListDetailSelectAction(section: section, page: cut.page) { route in
                path = OnDemandSplitPolicy.path(selecting: route, in: path, section: section)
            }
        )
        let closeAction: (() -> Void)? = open ? { close() } : nil
        let page = cut.list.last
        return MacStack(
            session: session, visibleInstruments: visibleInstruments,
            stackPath: pushes(keeping: cut.list.count), fullPath: $path, isVisible: isVisible,
            rootMaxWidth: MacLayoutPolicy.pageMaxWidth(for: page),
            paneContext: context, close: closeAction, isCovered: covered
        ) {
            Group {
                if let page {
                    destination(page)
                } else {
                    root(true)
                }
            }
            .id(page)
            .toolbar {
                // Covered, the profile's own Back is the only one (issue #352).
                if !cut.list.isEmpty, !covered {
                    ToolbarItem(placement: .navigation) {
                        // An open item closes first (issue #347).
                        SplitListBackButton {
                            if let back = OnDemandSplitPolicy.pathAfterListBack(path, section: section) { path = back }
                        }
                    }
                }
            }
        }
    }

    /// The trailing pane: its top route as root, with Close (the item itself) or Back
    /// (a page pushed from it, or a profile covering the list page) in the window toolbar.
    private func trailingPane(cut: OnDemandSplitPolicy.Cut, top: AppRoute) -> some View {
        let covers = cut.cover != .none
        return MacStack(
            session: session, visibleInstruments: visibleInstruments,
            stackPath: pushes(keeping: path.count), fullPath: $path, isVisible: isVisible,
            providesGlobalToolbar: false, rootMaxWidth: MacLayoutPolicy.pageMaxWidth(for: top),
            // Only the item opened beside the list page knows that page (#342).
            paneContext: SplitPaneContext(
                role: .trailing, besideList: cut.detail.count == 1 && !covers ? cut.page : nil, coversList: covers
            )
        ) {
            destination(top)
                .id(top)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if cut.detail.count > 1 || covers {
                            Button {
                                path = Array(path.dropLast())
                            } label: {
                                Label("Back", systemImage: "chevron.backward")
                            }
                            .help("Back (⌘[)")
                            .accessibilityIdentifier("fst.split.back")
                        } else {
                            SplitCloseButton { close() }
                        }
                    }
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.split.trailing")
    }

    /// A pane stack's path as it sees it: always empty (the pane draws its top route as
    /// root; inside the window's `NavigationSplitView` a page pushed in a nested stack
    /// covered both panes or never showed). A link pushed there replaces everything
    /// after `count` routes with the pushed routes, through the shared write rules, so a
    /// push from the list page closes the open item and opens full width.
    ///
    /// - Parameter count: Routes of the destination path kept before the push.
    /// - Returns: The binding for the pane's `NavigationStack`.
    private func pushes(keeping count: Int) -> Binding<[AppRoute]> {
        Binding {
            []
        } set: { pushed in
            guard !pushed.isEmpty else { return }
            let kept = Array(path.prefix(max(0, count)))
            path = OnDemandSplitPolicy.path(settingList: kept + pushed, in: path, section: section)
        }
    }

    /// Close the trailing pane: back to the full-width list page.
    private func close() {
        if let list = OnDemandSplitPolicy.pathClosingDetail(path, section: section) { path = list }
    }

    private func destination(_ route: AppRoute) -> some View {
        AppRouteDestination(
            route: route, session: session, visibleInstruments: visibleInstruments,
            path: $path, isVisible: isVisible
        )
    }
}
#endif
