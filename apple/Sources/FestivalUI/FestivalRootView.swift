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
    @State private var songsPath: [SongRoute] = []
    @State private var songsSearchText = ""
    @State private var songsSettledSearch = ""
    @State private var songsInstrument: Instrument?
    @State private var songsNotice: String?
    @State private var session: FestivalSession
    @AppStorage("fst.settings.showLead") private var showLead = true
    @AppStorage("fst.settings.showBass") private var showBass = true
    @AppStorage("fst.settings.showDrums") private var showDrums = true
    @AppStorage("fst.settings.showVocals") private var showVocals = true
    @AppStorage("fst.settings.showProLead") private var showProLead = true
    @AppStorage("fst.settings.showProBass") private var showProBass = true
    @AppStorage("fst.settings.showKaraoke") private var showKaraoke = true
    @AppStorage("fst.settings.showProCymbals") private var showProCymbals = true
    @AppStorage("fst.settings.showProDrums") private var showProDrums = true
    @AppStorage("fst.accessibility.reduceMotion") private var reduceMotion = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast

    /// Create an adaptive root using native, platform-owned navigation controls.
    public init() {
        _selected = State(initialValue: .songs)
        let factory: @Sendable () throws -> FestivalAPI = {
            try Self.makeClient(environment: ProcessInfo.processInfo.environment)
        }
        _session = State(initialValue: FestivalSession(factory: factory))
    }

    /// Build only approved loopback debug scenarios; Release always targets HTTPS.
    ///
    /// - Parameter environment: Launch environment containing optional debug fixture choices.
    /// - Returns: One keyless publication-aware client for the selected origin.
    /// - Throws: Invalid service URLs, unsupported fixture scenarios or insecure origins.
    nonisolated static func makeClient(environment: [String: String]) throws -> FestivalAPI {
        #if DEBUG
        let address = environment["FST_API_BASE_URL"] ?? "http://127.0.0.1:8765"
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
        Group {
            #if os(macOS)
            NavigationSplitView {
                sidebar
            } detail: {
                content(for: selected)
            }
            #else
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationSplitView {
                    sidebar
                } detail: {
                    content(for: selected)
                }
            } else {
                TabView(selection: $selected) {
                    ForEach(FestivalSection.allCases) { section in
                        content(for: section)
                            .tabItem {
                                Label(section.title, systemImage: section.symbol)
                            }
                            .tag(section)
                            .accessibilityIdentifier("fst.nav.\(section.rawValue)")
                    }
                }
            }
            #endif
        }
        .tint(moreContrast || systemContrast == .increased
            ? BrandTokens.textPrimary : BrandTokens.accentBlue)
        .preferredColorScheme(.dark)
        .transaction { transaction in
            if reduceMotion || systemReduceMotion {
                transaction.animation = nil
            }
        }
        .onChange(of: session.publicationRevision) { _, _ in
            if !songsPath.isEmpty {
                songsNotice = "Published scores changed. Returned to Songs to avoid outdated details."
                songsPath.removeAll()
            }
        }
        .onChange(of: visibleInstruments) { _, shown in
            if let songsInstrument, !shown.contains(songsInstrument) {
                songsNotice = "\(songsInstrument.label) was hidden. Showing all instruments."
                self.songsInstrument = nil
            }
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

    /// Keep visible root destinations as a native, Dynamic Type-aware sidebar.
    private var sidebar: some View {
        Group {
            #if os(macOS)
            List(selection: $selected) {
                ForEach(FestivalSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                        .accessibilityIdentifier("fst.nav.\(section.rawValue)")
                }
            }
            #else
            List(FestivalSection.allCases) { section in
                Button {
                    selected = section
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
    }

    /// Display a distinct native destination for each root tab.
    ///
    /// - Parameter section: Destination associated with the active tab or sidebar item.
    /// - Returns: The view that owns the destination's navigation state.
    @ViewBuilder private func content(for section: FestivalSection) -> some View {
        switch section {
        case .songs:
            SongNavigationRoot(
                session: session, path: $songsPath,
                searchText: $songsSearchText, settledSearch: $songsSettledSearch,
                selectedInstrument: $songsInstrument, navigationNotice: $songsNotice,
                visibleInstruments: visibleInstruments,
                highContrast: moreContrast || systemContrast == .increased,
                isVisible: selected == .songs
            )
        case .leaderboards:
            NavigationStack {
                ContentUnavailableView(
                    "Leaderboards overview migration in progress", systemImage: "list.number"
                )
                .navigationTitle("Leaderboards")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ArtworkBackground(
                    mode: .carousel, session: session, visible: selected == .leaderboards
                ))
            }
        case .settings:
            NavigationStack {
                SettingsScreen(session: session, isVisible: selected == .settings)
            }
        }
    }
}

// MARK: - Navigation sections

enum FestivalSection: String, CaseIterable, Identifiable, Sendable {
    case songs
    case leaderboards
    case settings

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .songs: "music.note.list"
        case .leaderboards: "list.number"
        case .settings: "gearshape"
        }
    }
}
