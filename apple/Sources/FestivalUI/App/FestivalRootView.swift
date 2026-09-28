import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign
#if os(iOS)
import UIKit
#endif

/// Platform-owned tab and sidebar navigation with a shared Songs path.
public struct FestivalRootView: View {
    @State private var selected: FestivalSection
    /// One independent navigation path per root section (web per-tab route history).
    @State private var paths: [FestivalSection: [AppRoute]] = [:]
    @State private var drawerPresented = false
    @State private var songsSearchText = ""
    @State private var songsSettledSearch = ""
    @State private var songsInstrument: Instrument?
    @State private var songsNotice: String?
    @State private var session: FestivalSession
    @State private var rootProfilePresented = false
    @AppStorage("fst.settings.showLead") private var showLead = true
    @AppStorage("fst.settings.showBass") private var showBass = true
    @AppStorage("fst.settings.showDrums") private var showDrums = true
    @AppStorage("fst.settings.showVocals") private var showVocals = true
    @AppStorage("fst.settings.showProLead") private var showProLead = true
    @AppStorage("fst.settings.showProBass") private var showProBass = true
    @AppStorage("fst.settings.showKaraoke") private var showKaraoke = true
    @AppStorage("fst.settings.showProCymbals") private var showProCymbals = true
    @AppStorage("fst.settings.showProDrums") private var showProDrums = true
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.accessibility.reduceMotion") private var reduceMotion = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast

    /// Create an adaptive root using native, platform-owned navigation controls.
    public init() {
        var initialSection = FestivalSection.songs
        var selectionStorage: UserDefaults? = .standard
        var initialRoute: AppRoute?
        var debugSelectedPlayer: SelectedPlayerIdentity?
        #if DEBUG
        let debug = DebugLaunchRoute(environment: ProcessInfo.processInfo.environment)
        if let tab = debug.section { initialSection = tab }
        initialRoute = debug.route
        _drawerPresented = State(initialValue: debug.opensDrawer)
        _rootProfilePresented = State(initialValue: debug.opensProfileSheet)
        if ProcessInfo.processInfo.environment["FST_UI_TEST_CLEAR_PROFILE"] == "1" {
            UserDefaults.standard.removeObject(forKey: SelectedPlayerIdentity.storageKey)
        }
        // In memory only: never written to `selectionStorage`. Parallel lanes share
        // one simulator, and writing this to real `UserDefaults.standard` (the
        // previous behavior) let one lane's debug launch clobber another lane's
        // actually-persisted selection.
        debugSelectedPlayer = debug.debugSelectedPlayer()
        if debug.anonymous { selectionStorage = nil }
        #endif
        let factory: @Sendable () throws -> FestivalAPI = {
            try Self.makeClient(environment: ProcessInfo.processInfo.environment)
        }
        let session = FestivalSession(
            factory: factory, selectionStorage: selectionStorage,
            debugSelectedPlayer: debugSelectedPlayer
        )
        _session = State(initialValue: session)
        // A deep link or restored tab may name a section the stored profile hides.
        let visible = FestivalTabPolicy.sections(
            profile: session.selectedPlayer == nil ? .none : .player,
            regularWidth: !Self.isCompactPhone
        )
        let resolved = FestivalTabPolicy.resolve(initialSection, in: visible)
        _selected = State(initialValue: resolved)
        if let initialRoute { _paths = State(initialValue: [resolved: [initialRoute]]) }
    }

    /// Use the public HTTPS service unless Debug explicitly selects a fixture.
    ///
    /// - Parameter environment: Launch environment containing optional debug fixture choices.
    /// - Returns: One keyless publication-aware client for the selected origin.
    /// - Throws: Invalid service URLs, unsupported fixture scenarios or insecure origins.
    nonisolated static func makeClient(environment: [String: String]) throws -> FestivalAPI {
        #if DEBUG
        let address = environment["FST_API_BASE_URL"] ?? "https://festivalscoretracker.com"
        #else
        let address = "https://festivalscoretracker.com"
        #endif
        guard let url = URL(string: address) else {
            throw FestivalAPIError.invalidResource
        }
        #if DEBUG
        let scenario: FixtureScenario?
        if let raw = environment["FST_FIXTURE_SCENARIO"] {
            guard let parsed = FixtureScenario(rawValue: raw) else {
                throw FestivalAPIError.invalidResource
            }
            scenario = parsed
        } else {
            scenario = nil
        }
        // FST_DEBUG_FORCE_FREEZE=1: answer each API path's first read with a
        // synthetic scrape-freeze 503 so the "Scores are updating" state can be captured.
        if environment["FST_DEBUG_FORCE_FREEZE"] == "1" {
            return try FestivalAPI(
                baseURL: url, fixtureScenario: scenario,
                transport: ForcedFreezeTransport(wrapping: URLSessionHTTPTransport())
            )
        }
        return try FestivalAPI(baseURL: url, fixtureScenario: scenario)
        #else
        return try FestivalAPI(baseURL: url)
        #endif
    }

    /// Supply a fixture client and initial screen for hosted navigation tests.
    ///
    /// - Parameters:
    ///   - initialSection: Initial platform navigation destination.
    ///   - clientFactory: Fixture-backed API client provider.
    init(initialSection: FestivalSection, clientFactory: @escaping @Sendable () throws -> FestivalAPI) {
        _selected = State(initialValue: initialSection)
        _session = State(initialValue: FestivalSession(factory: clientFactory))
    }

    /// Use system split navigation on iPad/macOS and adaptive tabs on iPhone.
    public var body: some View {
        ZStack {
            FestivalBackgroundHost(session: session)
                .ignoresSafeArea()
            shell
            if drawerPresented && usesDrawer {
                FestivalDrawer(
                    session: session, visibleSections: visibleSections, hideShop: hideShop,
                    onIntent: handleDrawer, onClose: closeDrawer
                )
                .transition(reduceMotion || systemReduceMotion
                    ? .opacity : .move(edge: .leading).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .tint(moreContrast || systemContrast == .increased
            ? BrandTokens.textPrimary : BrandTokens.accentBlue)
        .publishesDeviceLayout(usesSidebarShell: !usesDrawer)
    }

    // MARK: - Platform shell

    /// True on compact iPhone, where the hamburger drawer replaces the web sidebar.
    private var usesDrawer: Bool { Self.isCompactPhone }

    /// iPhone idiom (tabs + drawer) versus iPad/macOS (split view + sidebar).
    private static var isCompactPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom != .pad
        #else
        false
        #endif
    }

    /// Profile kind driving conditional tabs.
    private var profileKind: FestivalProfileKind {
        session.selectedPlayer == nil ? .none : .player
    }

    /// Root sections currently visible (web `BottomNav` rules).
    private var visibleSections: [FestivalSection] {
        FestivalTabPolicy.sections(profile: profileKind, regularWidth: !usesDrawer)
    }

    /// Platform navigation (tabs on iPhone, split view on iPad/macOS).
    private var shell: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                sidebar
            } detail: {
                content(for: selected)
            }
            #else
            if !usesDrawer {
                NavigationSplitView {
                    sidebar
                } detail: {
                    content(for: selected)
                }
            } else {
                tabs
            }
            #endif
        }
        .environment(\.openProfile, OpenProfileAction { rootProfilePresented = true })
        .environment(\.openDrawer, usesDrawer ? OpenDrawerAction { openDrawer() } : nil)
        .preferredColorScheme(.dark)
        .transaction { transaction in
            if reduceMotion || systemReduceMotion {
                transaction.animation = nil
            }
        }
        .sheet(isPresented: $rootProfilePresented) {
            // Passed directly rather than through `\.openRoute`: a custom `@Entry`
            // environment value set here does not reliably reach this sheet's own
            // content once SwiftUI hosts it as a separate presentation (verified
            // empirically — see `ProfileSelectionSheet.openRoute`'s doc comment).
            ProfileSelectionSheet(session: session) { route in
                paths[selected, default: []].append(route)
            }
            .festivalSheet()
        }
        .onChange(of: visibleSections) { _, visible in
            let resolved = FestivalTabPolicy.resolve(selected, in: visible)
            if resolved != selected { selected = resolved }
        }
        .onChange(of: session.publicationRevision) { _, _ in
            if !songsPath.isEmpty {
                songsNotice = "Published scores changed. Returned to Songs to avoid outdated details."
                songsPath.removeAll()
            }
        }
        .onChange(of: session.selectionRevision) { _, _ in
            if !songsPath.isEmpty {
                songsNotice = "Selected profile changed. Returned to Songs to avoid mixed scores."
                songsPath.removeAll()
            }
            // Profile hubs show the previous identity's data; start them fresh.
            for section in [FestivalSection.suggestions, .statistics, .compete, .rivals] {
                paths[section] = nil
            }
        }
        .onChange(of: visibleInstruments) { _, shown in
            if let songsInstrument, !shown.contains(songsInstrument) {
                songsNotice = "\(songsInstrument.label) was hidden. Showing all instruments."
                self.songsInstrument = nil
            }
        }
        .onChange(of: hideShop) { _, hidden in
            guard hidden else { return }
            for (section, path) in paths {
                guard let index = path.firstIndex(of: .shop) else { continue }
                paths[section] = Array(path.prefix(index))
                if section == .songs {
                    songsNotice = "Item Shop was hidden. Returned to Songs."
                }
            }
        }
    }

    /// Compact iPhone tabs: the iOS 18+ `Tab` API (Liquid Glass tab bar on 26),
    /// classic `.tabItem` on iOS 17.
    @ViewBuilder private var tabs: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            TabView(selection: tabSelection) {
                ForEach(visibleSections) { section in
                    Tab(section.title, systemImage: section.symbol, value: section) {
                        content(for: section)
                            .accessibilityIdentifier("fst.nav.\(section.rawValue)")
                    }
                }
            }
        } else {
            TabView(selection: tabSelection) {
                ForEach(visibleSections) { section in
                    content(for: section)
                        .tabItem { Label(section.title, systemImage: section.symbol) }
                        .tag(section)
                        .accessibilityIdentifier("fst.nav.\(section.rawValue)")
                }
            }
        }
    }

    /// Tab selection that pops a re-tapped tab to its root and clears Statistics on leave.
    private var tabSelection: Binding<FestivalSection> {
        Binding {
            selected
        } set: { next in
            select(next)
        }
    }

    /// Change the root section with web tab semantics.
    ///
    /// - Parameter next: Section chosen by a tab, sidebar row or drawer item.
    private func select(_ next: FestivalSection) {
        if next == selected {
            paths[next] = []
        } else if FestivalTabPolicy.resetsPathOnLeave(selected) {
            paths[selected] = []
        }
        selected = next
    }

    /// Binding into one section's navigation path.
    ///
    /// - Parameter section: Root section owning the stack.
    /// - Returns: Read/write binding that defaults to an empty path.
    private func path(for section: FestivalSection) -> Binding<[AppRoute]> {
        Binding {
            paths[section] ?? []
        } set: { value in
            paths[section] = value
        }
    }

    /// Songs path, used by publication/profile invalidation notices.
    private var songsPath: [AppRoute] {
        get { paths[.songs] ?? [] }
        nonmutating set { paths[.songs] = newValue }
    }

    // MARK: - Drawer

    private func openDrawer() {
        withAnimation(reduceMotion || systemReduceMotion ? nil : .smooth(duration: 0.3)) {
            drawerPresented = true
        }
    }

    private func closeDrawer() {
        withAnimation(reduceMotion || systemReduceMotion ? nil : .smooth(duration: 0.25)) {
            drawerPresented = false
        }
    }

    /// Carry out a drawer intent on the root-owned navigation state.
    ///
    /// - Parameter intent: Row chosen in the drawer.
    private func handleDrawer(_ intent: DrawerIntent) {
        closeDrawer()
        switch intent {
        case let .push(route):
            paths[selected, default: []].append(route)
        case let .select(section):
            if selected != section { select(section) }
            paths[section] = []
        case .chooseProfile:
            rootProfilePresented = true
        case .deselectProfile:
            session.deselectPlayer()
        }
    }

    /// Share one persisted visibility policy with the filter menu and Detail links.
    private var visibleInstruments: Set<Instrument> {
        let preferences: [(Instrument, Bool)] = [
            (.lead, showLead), (.bass, showBass), (.drums, showDrums),
            (.vocals, showVocals), (.proLead, showProLead), (.proBass, showProBass),
            (.karaoke, showKaraoke), (.proCymbals, showProCymbals),
            (.proDrums, showProDrums),
        ]
        return Set(preferences.compactMap { $0.1 ? $0.0 : nil })
    }

    // MARK: - Wide-layout sidebar

    /// Keep visible root destinations as a native, Dynamic Type-aware sidebar.
    private var sidebar: some View {
        Group {
            #if os(macOS)
            List(selection: Binding<FestivalSection?>(
                get: { selected }, set: { if let next = $0 { select(next) } }
            )) {
                ForEach(visibleSections) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                        .accessibilityIdentifier("fst.nav.\(section.rawValue)")
                }
            }
            #else
            List(visibleSections) { section in
                Button {
                    select(section)
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(selected == section ? BrandTokens.accentBlue : .clear)
                            .frame(width: 3, height: 24)
                            .accessibilityHidden(true)
                        Label(section.title, systemImage: section.symbol)
                            .fontWeight(selected == section ? .semibold : .regular)
                            .foregroundStyle(BrandTokens.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowBackground(BrandTokens.cardBackground)
                .accessibilityAddTraits(selected == section ? .isSelected : [])
                .accessibilityIdentifier("fst.nav.\(section.rawValue)")
            }
            #endif
        }
        .navigationTitle("Festival")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarProfileAction
        }
    }

    /// Retain the visible selected identity in native wide-layout navigation.
    private var sidebarProfileAction: some View {
        Button {
            rootProfilePresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: session.selectedPlayer == nil
                    ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                    .foregroundStyle(BrandTokens.accentBlue)
                    .accessibilityHidden(true)
                Text(session.selectedPlayer?.displayName ?? "Choose Profile")
                    .foregroundStyle(BrandTokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.selectedPlayer.map {
            "Profile: \($0.displayName). Change profile"
        } ?? "Choose Profile")
        .accessibilityIdentifier("fst.profile.sidebar")
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Section content

    /// Display a distinct native destination for each root tab.
    ///
    /// Every root except Songs gets `festivalRootChrome` here; Songs applies it itself
    /// (Lane S) because it merges the chrome with its own search/sort/filter toolbar.
    ///
    /// - Parameter section: Destination associated with the active tab or sidebar item.
    /// - Returns: The view that owns the destination's navigation state.
    @ViewBuilder private func content(for section: FestivalSection) -> some View {
        switch section {
        case .songs:
            SongNavigationRoot(
                session: session, path: path(for: .songs),
                searchText: $songsSearchText, settledSearch: $songsSettledSearch,
                selectedInstrument: $songsInstrument, navigationNotice: $songsNotice,
                visibleInstruments: visibleInstruments,
                highContrast: moreContrast || systemContrast == .increased,
                isVisible: selected == .songs
            )
            .firstRun(.songs, session: session)
        case .suggestions:
            tabStack(.suggestions) {
                SuggestionsScreen(session: session, visibleInstruments: visibleInstruments)
                    .firstRun(.suggestions, session: session)
            }
        case .leaderboards:
            tabStack(.leaderboards) {
                LeaderboardsScreen(session: session).firstRun(.leaderboards, session: session)
            }
        case .compete:
            tabStack(.compete) {
                CompeteScreen(session: session).firstRun(.compete, session: session)
            }
        case .rivals:
            tabStack(.rivals) {
                RivalsScreen(session: session).firstRun(.rivals, session: session)
            }
        case .statistics:
            tabStack(.statistics) {
                StatisticsScreen(session: session).firstRun(.statistics, session: session)
            }
        case .settings:
            tabStack(.settings) {
                SettingsScreen(session: session, isVisible: selected == .settings)
            }
        }
    }

    /// Wrap a root screen in its own `FestivalTabStack` with shared root chrome.
    ///
    /// - Parameters:
    ///   - section: Section owning the stack and path.
    ///   - root: Root screen of the section.
    /// - Returns: The navigation stack for the section.
    private func tabStack<Root: View>(
        _ section: FestivalSection, @ViewBuilder root: () -> Root
    ) -> some View {
        FestivalTabStack(
            session: session, visibleInstruments: visibleInstruments,
            path: path(for: section), isVisible: selected == section
        ) {
            root().festivalRootChrome(session: session)
        }
    }
}


// MARK: - Debug launch routing

#if DEBUG
/// Parses `FST_DEBUG_TAB` / `FST_DEBUG_ROUTE` so `tools/ios_sim.py` can open any page directly.
///
/// Route syntax: `player:<accountId>`, `leaderboards`, `fullRankings:<Instrument rawValue>`,
/// `shop`, `rivals`, `statistics`, `suggestions`, `compete`, `bands`, `licenses`,
/// `allRivals:<scope>`, `rivalDetail:<rivalId>[:<scope>]`, `rivalry:<rivalId>:<mode>[:<scope>]`.
/// `<scope>` is `RivalScope.debugToken`: `song:<instrument>[,<instrument>…]`,
/// `leaderboard:<instrument>:<rankBy>` or `combo:<token>:<instrument>[,<instrument>…]`.
/// Song routes need a loaded `Song`; the Songs lane handles `FST_DEBUG_SONG` itself.
///
/// Shell extras: `FST_DEBUG_DRAWER=1` opens the hamburger drawer, `FST_DEBUG_SHEET=profile`
/// opens profile selection, and `FST_DEBUG_PROFILE=<accountId>:<displayName>` selects a
/// player **in memory only** before the session loads (so profile-only tabs can be
/// captured) — it is never written to `UserDefaults`, so it cannot clobber another
/// lane's real persisted selection on the shared simulator.
/// `FST_DEBUG_ANONYMOUS=1` ignores any stored profile for this launch without deleting it.
struct DebugLaunchRoute {
    let section: FestivalSection?
    let route: AppRoute?
    let opensDrawer: Bool
    let opensProfileSheet: Bool
    let profile: (accountId: String, displayName: String)?
    let anonymous: Bool

    /// Parse the launch environment.
    ///
    /// - Parameter environment: Process environment.
    init(environment: [String: String]) {
        section = environment["FST_DEBUG_TAB"].flatMap(FestivalSection.init(rawValue:))
        opensDrawer = environment["FST_DEBUG_DRAWER"] == "1"
        opensProfileSheet = environment["FST_DEBUG_SHEET"] == "profile"
        anonymous = environment["FST_DEBUG_ANONYMOUS"] == "1"
        if let raw = environment["FST_DEBUG_PROFILE"] {
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            profile = parts.count == 2 ? (parts[0], parts[1]) : nil
        } else {
            profile = nil
        }
        guard let raw = environment["FST_DEBUG_ROUTE"] else {
            route = nil
            return
        }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : nil
        switch parts.first {
        case "player": route = arg.map { .player(accountId: $0, displayName: nil) }
        case "playerBands": route = arg.map { .playerBands(accountId: $0, displayName: nil) }
        case "leaderboards": route = .leaderboards
        case "fullRankings":
            route = .fullRankings(
                instrument: arg.flatMap(Instrument.init(rawValue:)) ?? .lead, rankBy: "adjusted"
            )
        case "bandRankings": route = .bandRankings(bandType: arg ?? "Band_Duets")
        case "shop": route = .shop
        case "rivals": route = .rivals
        case "allRivals":
            route = arg.flatMap(RivalScope.init(debugToken:)).map { .allRivals(scope: $0) }
        case "rivalDetail":
            if let arg {
                let pieces = arg.split(separator: ":", maxSplits: 1).map(String.init)
                let scope = pieces.count > 1 ? RivalScope(debugToken: pieces[1]) : nil
                route = .rivalDetail(rivalId: pieces[0], name: nil, scope: scope)
            } else {
                route = nil
            }
        case "rivalry":
            if let arg {
                let pieces = arg.split(separator: ":", maxSplits: 2).map(String.init)
                if pieces.count >= 2 {
                    let scope = pieces.count > 2 ? RivalScope(debugToken: pieces[2]) : nil
                    route = .rivalry(rivalId: pieces[0], mode: pieces[1], name: nil, scope: scope)
                } else {
                    route = nil
                }
            } else {
                route = nil
            }
        case "statistics": route = .statistics
        case "suggestions": route = .suggestions
        case "compete": route = .compete
        case "bands": route = .bands
        case "band": route = arg.map { .band(bandId: $0, name: nil) }
        case "licenses": route = .licenses
        default: route = nil
        }
    }

    /// Build the debug profile as an in-memory-only selected identity.
    ///
    /// Never touches `UserDefaults`: `FestivalSession(debugSelectedPlayer:)` seeds
    /// `selectedPlayer` directly, so this launch shows a selected state without
    /// reading or overwriting whatever another lane's process may have persisted
    /// to the shared simulator's real `UserDefaults.standard`.
    ///
    /// - Returns: A validated identity for a well-formed `FST_DEBUG_PROFILE`, else nil.
    func debugSelectedPlayer() -> SelectedPlayerIdentity? {
        guard let profile else { return nil }
        return try? SelectedPlayerIdentity(
            searchResult: PlayerSearchResult(
                accountId: profile.accountId, displayName: profile.displayName
            )
        )
    }
}
#endif
