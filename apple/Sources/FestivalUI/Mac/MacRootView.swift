#if os(macOS)
import AppKit
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Mac root

/// The macOS window: a `NavigationSplitView` with the web's sidebar destinations and
/// the selected player in the sidebar footer, a detail column per destination (two
/// populated columns where a list page allows, ``MacListDetailStack``), and one shell
/// owned set of global toolbar items (Search, notifications bell, profile).
///
/// Decisions and HIG citations: `.agents/design/apple/macos.md`.
public struct MacRootView: View {
    let model: MacAppModel
    @State private var songsSearchText = ""
    @State private var songsSettledSearch = ""
    @State private var songsInstrument: Instrument?
    @State private var songsNotice: String?
    @State private var pendingSheetRoute: AppRoute?
    /// The Search sheet's opening size for the window's current shape.
    @State private var searchSheetSize = WideColumns.macNarrowSheet
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
    @FocusedValue(\.macPageCommands) private var pageCommands
    @Environment(\.openSettings) private var openSettings

    /// Create the window content.
    ///
    /// - Parameter model: The app model shared with the commands and Settings window.
    public init(model: MacAppModel) {
        self.model = model
    }

    private var session: FestivalSession { model.session }
    private var navigation: MacNavigationModel { model.navigation }
    private var highContrast: Bool { moreContrast || systemContrast == .increased }

    private var visibleDestinations: [MacDestination] {
        MacSidebarPolicy.destinations(hasPlayer: session.selectedPlayer != nil, hideShop: hideShop)
    }

    public var body: some View {
        @Bindable var navigation = navigation
        ZStack {
            FestivalBackgroundHost(session: session)
                .ignoresSafeArea()
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
            } detail: {
                detail
                    .id(navigation.refreshGeneration)
            }
        }
        .frame(minWidth: MacWindowMetrics.minimum.width, minHeight: MacWindowMetrics.minimum.height)
        // Only a change of sheet size invalidates the root, not every live-resize step.
        .onGeometryChange(for: CGSize.self) { WideColumns.macSheetSize(window: $0.size) } action: {
            searchSheetSize = $0
        }
        .tint(highContrast ? BrandTokens.textPrimary : BrandTokens.accentBlue)
        .preferredColorScheme(.dark)
        .environment(\.festivalSession, session)
        // Continuous decoration pauses while the window cannot be seen (minimized,
        // covered, another Space), as the Windows app does.
        .environment(\.festivalWindowVisible, model.isWindowVisible)
        .environment(\.shellOwnsGlobalToolbar, true)
        .environment(\.macAppModel, model)
        .environment(\.songRowsAllowSingleLine, true)
        .environment(\.refreshCommandRegistry, model.refreshRegistry)
        .environment(\.openProfile, OpenProfileAction { navigation.profilePresented = true })
        // The model reads its visible rows live, so the captured flag never goes stale.
        .environment(\.profileButtonAction, ProfileButtonHandler(statisticsVisible: true) {
            navigation.pressProfileButton(hasPlayer: session.selectedPlayer != nil)
        })
        .environment(\.openGlobalSearch, OpenGlobalSearchAction { navigation.searchPresented = true })
        .environment(\.pushRoute, PushRouteAction { navigation.push($0) })
        .environment(\.playerStatNavigator, PlayerStatNavigator(
            push: { navigation.push($0) }, showSongs: { showSongs($0) }
        ))
        .transaction { transaction in
            if reduceMotion || systemReduceMotion { transaction.animation = nil }
        }
        .sheet(isPresented: $navigation.profilePresented, onDismiss: pushPendingSheetRoute) {
            ProfileSelectionSheet(session: session) { pendingSheetRoute = $0 }
                .macSheetFrame(width: 560, height: 640)
                .festivalSheet()
        }
        .sheet(isPresented: $navigation.searchPresented, onDismiss: pushPendingSheetRoute) {
            // Wide landscape windows open a two-column sheet (pattern `wide-columns`,
            // issue #350); it resizes down to one column.
            GlobalSearchSheet(session: session) { pendingSheetRoute = $0 }
                .macSheetFrame(
                    width: searchSheetSize.width, height: searchSheetSize.height,
                    minWidth: WideColumns.macNarrowSheet.width - 60, minHeight: 520
                )
                .festivalSheet()
        }
        .sheet(isPresented: $navigation.notificationsPresented, onDismiss: pushPendingSheetRoute) {
            NotificationsSheet(session: session) { pendingSheetRoute = $0 }
                .macSheetFrame(width: 560, height: 680)
                .festivalSheet(.large)
        }
        .whatsNewPresentation(isPresented: $navigation.whatsNewPresented) {
            WhatsNewChannelSheet(version: WhatsNewGate.appVersion()) {
                ChangelogSeenStore().markSeen(version: WhatsNewGate.appVersion())
                navigation.whatsNewPresented = false
            }
            .macSheetFrame(width: 620, height: 720)
        }
        .whatsNew(session: session)
        .background {
            MacWindowConfigurator(
                selectionText: { model.navigation.selectionCopyText },
                onFullScreenChange: { model.isFullScreen = $0 },
                onVisibilityChange: { visible in
                    if model.isWindowVisible != visible { model.isWindowVisible = visible }
                }
            )
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: MacDebugHooks.localCommandName)) { note in
            if let command = note.object as? MacDebugCommand { run(command) }
        }
        #endif
        .onChange(of: visibleDestinations, initial: true) { _, visible in
            navigation.update(visible: visible)
        }
        // A new publication never navigates (issue #304): pages refresh in place
        // (`PublicationRefreshBoundary`), re-reading `Song`-valued routes.
        .publicationLiveUpdates(session: session)
        .onChange(of: visibleInstruments) { _, shown in
            if let songsInstrument, !shown.contains(songsInstrument) {
                songsNotice = "\(songsInstrument.label) was hidden. Showing all instruments."
                self.songsInstrument = nil
            }
        }
        // A deselect or player/band switch returns Songs to every instrument with the
        // saved filters and sort reset (web `resetSongSettingsForDeselect`, issue #359).
        .onChange(of: session.songSettingsResetRevision) { _, _ in
            songsInstrument = nil
        }
    }

    private func pushPendingSheetRoute() {
        guard let route = pendingSheetRoute else { return }
        pendingSheetRoute = nil
        if let destination = MacSidebarPolicy.destination(for: route),
           navigation.visible.contains(destination) {
            navigation.select(destination)
        } else {
            navigation.push(route)
        }
    }

    #if DEBUG
    /// Carry out a `tools/mac_app.py command` (Debug evidence driver).
    private func run(_ command: MacDebugCommand) {
        switch command {
        case let .select(destination, number):
            if let destination { navigation.select(destination) }
            if let number { navigation.selectShortcut(number) }
        case let .route(raw):
            guard let route = DebugLaunchRoute(environment: ["FST_DEBUG_ROUTE": raw]).route else { return }
            if let destination = MacSidebarPolicy.destination(for: route) {
                navigation.select(destination)
            } else {
                navigation.push(route)
            }
        case .back: navigation.goBack()
        case .refresh: model.refresh()
        case .search: navigation.searchPresented = true
        case .profile: navigation.profilePresented = true
        case .notifications: navigation.notificationsPresented = true
        case .whatsNew: navigation.whatsNewPresented = true
        case .sort: pageCommands?.sort?()
        case .filter: pageCommands?.filter?()
        case .settings: openSettings()
        case let .song(target):
            let selected = MacCopyPolicy.selectedRoute(
                path: navigation.currentPath, section: navigation.selected.section,
                split: navigation.splitDestinations.contains(navigation.selected)
            )
            guard case let .songDetail(song) = selected else { return }
            switch target {
            case "leaderboard": navigation.push(.songLeaderboard(song, .lead, 1))
            case "history": navigation.push(.playerHistory(song, .lead))
            default: NotificationCenter.default.post(name: MacDebugHooks.openPathsName, object: nil)
            }
        case .menus:
            // Titles and shortcuts; enabled states reflect the key window, so they read
            // as disabled while the app is in the background (never activated here).
            let lines = NSApplication.shared.mainMenu.map { MacDebugHooks.describe($0) } ?? []
            try? lines.joined(separator: "\n")
                .write(toFile: MacDebugHooks.menuDumpPath, atomically: true, encoding: .utf8)
        case let .settingsPane(pane):
            UserDefaults.standard.set(pane.rawValue, forKey: SettingsPane.storageKey)
            openSettings()
        case let .key(name, modifiers): MacDebugHooks.sendKey(name, modifiers: modifiers)
        case .minimize: MacDebugHooks.setMainWindowMinimized(true)
        case .restore: MacDebugHooks.setMainWindowMinimized(false)
        case .dismiss:
            navigation.searchPresented = false
            navigation.profilePresented = false
            navigation.notificationsPresented = false
            navigation.whatsNewPresented = false
        }
    }
    #endif

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: Binding<MacDestination?>(
            get: { navigation.selected },
            set: { if let next = $0 { navigation.select(next) } }
        )) {
            ForEach(Array(navigation.visible.enumerated()), id: \.element) { index, destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
                    .help(index < 9 ? "\(destination.title) (⌘\(index + 1))" : destination.title)
                    .accessibilityIdentifier(destination.accessibilityIdentifier)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MacSidebarProfileFooter(model: model)
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        let destination = navigation.selected
        switch destination {
        case .songs:
            listDetail(.songs, destination: destination) { rootIsTop in
                SongsScreen(
                    session: session, searchText: $songsSearchText, settledSearch: $songsSettledSearch,
                    selectedInstrument: $songsInstrument, navigationNotice: $songsNotice,
                    visibleInstruments: visibleInstruments, highContrast: highContrast,
                    isVisible: rootIsTop,
                    openShop: { navigation.select(.shop) }
                )
                // Skips the page's body when its column re-runs without a change (#325).
                .equatable()
                .firstRun(.songs, session: session)
            }
        case .rivals:
            listDetail(.rivals, destination: destination) { _ in
                RivalsScreen(session: session, showsRootTrailingItems: true)
                    .refreshesOnPublication(session: session)
                    .firstRun(.rivals, session: session)
                    .id(session.selectedPlayer?.accountId)
            }
        case .leaderboards:
            listDetail(.leaderboards, destination: destination) { _ in
                LeaderboardsScreen(session: session)
                    .refreshesOnPublication(session: session)
                    .firstRun(.leaderboards, session: session)
            }
        case .suggestions:
            stack(destination) {
                SuggestionsScreen(session: session, visibleInstruments: visibleInstruments)
                    .refreshesOnPublication(session: session)
                    .firstRun(.suggestions, session: session)
            }
        case .statistics:
            stack(destination) {
                StatisticsScreen(session: session)
                    .refreshesOnPublication(session: session)
                    .firstRun(.statistics, session: session)
            }
        case .compete:
            stack(destination) {
                CompeteScreen(session: session)
                    .refreshesOnPublication(session: session)
                    .firstRun(.compete, session: session)
            }
        case .shop:
            stack(destination) {
                ShopScreen(session: session, isVisible: navigation.currentPath.isEmpty)
                    .refreshesOnPublication(session: session)
                    .firstRun(.shop, session: session)
            }
        }
    }

    private func pathBinding(_ destination: MacDestination) -> Binding<[AppRoute]> {
        Binding {
            ProfileRoutePolicy.resolve(
                navigation.paths[destination] ?? [], hasPlayer: session.selectedPlayer != nil
            )
        } set: { navigation.paths[destination] = $0 }
    }

    private func stack<Root: View>(
        _ destination: MacDestination, @ViewBuilder root: () -> Root
    ) -> some View {
        let path = pathBinding(destination)
        return MacStack(
            session: session, visibleInstruments: visibleInstruments,
            stackPath: path, fullPath: path, isVisible: true,
            rootMaxWidth: MacLayoutPolicy.pageMaxWidth(for: nil, isShopRoot: destination == .shop)
        ) { root() }
        .onAppear { navigation.splitDestinations.remove(destination) }
    }

    private func listDetail<Root: View>(
        _ section: FestivalSection, destination: MacDestination,
        @ViewBuilder root: @escaping (Bool) -> Root
    ) -> some View {
        MacListDetailStack(
            section: section, session: session, visibleInstruments: visibleInstruments,
            path: pathBinding(destination), isVisible: true,
            onSplitChange: { isSplit in
                if isSplit {
                    navigation.splitDestinations.insert(destination)
                } else {
                    navigation.splitDestinations.remove(destination)
                }
            },
            root: root
        )
    }

    // MARK: Songs presets

    /// Show Songs with a player-page stat tile's preset (web `navigateToSongs`).
    private func showSongs(_ preset: SongsFilterPreset) {
        let saved = SongsPresetStore.apply(
            preset, visibleInstruments: visibleInstruments, instrument: songsInstrument
        )
        songsInstrument = saved.instrument
        songsSearchText = ""
        songsSettledSearch = ""
        songsNotice = nil
        navigation.paths[.songs] = []
        if navigation.selected != .songs { navigation.select(.songs) }
    }

    private var visibleInstruments: Set<Instrument> {
        let preferences: [(Instrument, Bool)] = [
            (.lead, showLead), (.bass, showBass), (.drums, showDrums),
            (.vocals, showVocals), (.proLead, showProLead), (.proBass, showProBass),
            (.karaoke, showKaraoke), (.proCymbals, showProCymbals), (.proDrums, showProDrums),
        ]
        return Set(preferences.compactMap { $0.1 ? $0.0 : nil })
    }
}

// MARK: - Window metrics

/// Window sizes (points). The default fits sidebar + list + detail on a 13-inch
/// display; the minimum keeps sidebar + one readable column (HIG Windows: windows
/// "adapt fluidly to different sizes").
public enum MacWindowMetrics {
    /// First-launch window size.
    public static let defaultSize = CGSize(width: 1280, height: 820)
    /// Smallest window content size.
    public static let minimum = CGSize(width: 760, height: 540)
}

// MARK: - Global toolbar

/// The shell's trailing toolbar group: Search, the bell (selected player only) and the
/// profile button. Pages step their own copies aside via `\.shellOwnsGlobalToolbar`,
/// so the unified window toolbar never shows two of each when two columns contribute.
struct MacGlobalToolbarItems: ToolbarContent {
    let model: MacAppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // "Search Festival", like Edit › Search Festival…: Songs' inline filter field
            // is the toolbar's system "Search" item, so two items named "Search" were
            // ambiguous for VoiceOver and Voice Control.
            GlobalSearchButton(title: "Search Festival") { model.navigation.searchPresented = true }
                .help("Search Festival (⌘K)")
            if model.session.selectedPlayer != nil {
                NotificationsButton(session: model.session) {
                    model.navigation.notificationsPresented = true
                }
                .help("Notifications")
            }
            RootProfileButton(session: model.session) {
                model.navigation.pressProfileButton(hasPlayer: model.session.selectedPlayer != nil)
            }
                .help(model.session.selectedPlayer.map { "Show Statistics for \($0.displayName)" } ?? "Select Profile")
        }
    }
}

/// Adds ``MacGlobalToolbarItems`` to a page when enabled and inside the Mac window.
struct MacGlobalToolbar: ViewModifier {
    let isEnabled: Bool
    @Environment(\.macAppModel) private var model

    func body(content: Content) -> some View {
        if isEnabled, let model {
            content.toolbar { MacGlobalToolbarItems(model: model) }
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    /// The app model, set by ``MacRootView`` (nil in the Settings window and tests).
    @Entry var macAppModel: MacAppModel?
}

// MARK: - Sidebar footer

/// The selected player at the foot of the sidebar (web `PinnedSidebar` utilities): the
/// name opens Statistics, with Deselect beside it; Select Profile when anonymous.
/// The same actions are in the Profile menu and toolbar, because the sidebar's bottom
/// may be offscreen (HIG Sidebars › macOS).
struct MacSidebarProfileFooter: View {
    let model: MacAppModel

    var body: some View {
        Group {
            if let player = model.session.selectedPlayer {
                HStack(spacing: 8) {
                    Button {
                        model.navigation.select(.statistics)
                    } label: {
                        Label {
                            Text(player.displayName).lineLimit(1).truncationMode(.tail)
                        } icon: {
                            Image(systemName: "person.crop.circle.fill")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show Statistics for \(player.displayName)")
                    .accessibilityLabel("Profile: \(player.displayName). Show Statistics")
                    .accessibilityIdentifier("fst.profile.sidebar.name")
                    Button("Deselect") { model.session.deselectPlayer() }
                        .controlSize(.small)
                        .help("Deselect \(player.displayName)")
                        // Name what it acts on (HIG VoiceOver: labels convey the app's
                        // functionality), as the iPad sidebar does.
                        .accessibilityLabel("Deselect Profile")
                        .accessibilityIdentifier("fst.profile.sidebar.deselect")
                }
            } else {
                Button {
                    model.navigation.profilePresented = true
                } label: {
                    Label("Select Profile", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Select Profile (⇧⌘P)")
                .accessibilityIdentifier("fst.profile.sidebar.select")
            }
        }
        .font(.body)
        .foregroundStyle(FestivalText.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Window configuration

/// Turns AppKit window restoration off (so a crash or forced quit never leads to the
/// "reopen windows" prompt) and keeps the frame in an autosave name instead; the
/// sidebar destination is restored by ``MacNavigationModel``. Also puts
/// ``MacSelectionCopyResponder`` in the window's responder chain for Edit › Copy.
struct MacWindowConfigurator: NSViewRepresentable {
    static let autosaveName = "FestivalMainWindow"
    /// The selected row's name for Edit › Copy (``MacSelectionCopyResponder``).
    var selectionText: @MainActor () -> String? = { nil }
    /// Reports entering and leaving full screen (View › Enter/Exit Full Screen title).
    var onFullScreenChange: @MainActor (Bool) -> Void = { _ in }
    /// Reports whether any part of the window can be seen (`NSWindow.occlusionState`).
    var onVisibilityChange: @MainActor (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {
        let probe = WindowProbe()
        probe.copyResponder.selectionText = selectionText
        probe.onFullScreenChange = onFullScreenChange
        probe.onVisibilityChange = onVisibilityChange
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let probe = nsView as? WindowProbe else { return }
        probe.copyResponder.selectionText = selectionText
        probe.onFullScreenChange = onFullScreenChange
        probe.onVisibilityChange = onVisibilityChange
    }

    private final class WindowProbe: NSView {
        let copyResponder = MacSelectionCopyResponder()
        var onFullScreenChange: @MainActor (Bool) -> Void = { _ in }
        var onVisibilityChange: @MainActor (Bool) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []
        private var pendingHide: DispatchWorkItem?

        /// Report visibility: at once when the window shows, after 0.5 s when it hides
        /// (covering it flapped the state several times within a few milliseconds).
        func occlusionChanged(visible: Bool) {
            pendingHide?.cancel()
            pendingHide = nil
            guard !visible else {
                onVisibilityChange(true)
                return
            }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.onVisibilityChange(false) }
            }
            pendingHide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            for (name, isFullScreen) in [
                (NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false),
            ] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onFullScreenChange(isFullScreen) }
                })
            }
            // Minimized, fully covered, on another Space or behind a locked screen:
            // the artwork carousel and Shop pulses pause (`AnimationActivity`).
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let window else { return }
                    self?.occlusionChanged(visible: window.occlusionState.contains(.visible))
                }
            })
            DispatchQueue.main.async { [weak self, weak window] in
                MainActor.assumeIsolated {
                    guard let window else { return }
                    self?.onVisibilityChange(window.occlusionState.contains(.visible))
                }
            }
            // After the window in its responder chain: a focused text field's own
            // Copy still wins.
            if window.nextResponder !== copyResponder {
                copyResponder.nextResponder = window.nextResponder
                window.nextResponder = copyResponder
            }
            window.isRestorable = false
            window.tabbingMode = .disallowed
            #if DEBUG
            // `tools/mac_app.py launch --size` sets the size; a saved frame must not win.
            if ProcessInfo.processInfo.environment["FST_DEBUG_WINDOW_SIZE"] != nil { return }
            #endif
            if window.frameAutosaveName != MacWindowConfigurator.autosaveName {
                window.setFrameAutosaveName(MacWindowConfigurator.autosaveName)
            }
        }
    }
}
#endif
