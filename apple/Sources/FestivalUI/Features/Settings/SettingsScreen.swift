import SwiftUI
import FestivalCore
import FestivalDesign

/// Publication checks must disclose whether the associated Songs read was stale or unpinned.
enum SettingsServiceSummary {
    /// Present a validated bootstrap without inventing response provenance.
    ///
    /// - Parameter payload: Typed Songs result from the same publication check.
    /// - Returns: Visible success, stale-memory, or unverified-live explanation.
    static func message(for payload: CatalogPayload) -> String {
        let prefix = "Publication \(payload.observedPublicationId)"
        if payload.isStale {
            return payload.publicationId == nil
                ? "\(prefix); songs offline - last seen (publication unverified)"
                : "\(prefix); songs offline - showing verified cached data"
        }
        return payload.publicationId == nil
            ? "\(prefix); songs live (publication unverified)"
            : prefix
    }
}

/// Native, persistent first-slice preferences and additive accessibility aids.
struct SettingsScreen: View {
    @AppStorage("fst.settings.showInstrumentIcons") private var showInstrumentIcons = true
    @AppStorage("fst.settings.filterInvalidScores") private var filterInvalidScores = false
    @AppStorage("fst.settings.leeway") private var leeway = 1.0
    @AppStorage("fst.settings.pathDefaultView") private var pathDefaultView = PathDisplayMode.image
    @AppStorage("fst.settings.pathUnavailableWarningDismissed")
    private var pathWarningDismissed = false
    @AppStorage("fst.settings.experimentalRanks") private var experimentalRanks = false
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.settings.disableShopHighlighting") private var disableShopHighlighting = false

    @AppStorage("fst.settings.showLead") private var showLead = true
    @AppStorage("fst.settings.showBass") private var showBass = true
    @AppStorage("fst.settings.showDrums") private var showDrums = true
    @AppStorage("fst.settings.showVocals") private var showVocals = true
    @AppStorage("fst.settings.showProLead") private var showProLead = true
    @AppStorage("fst.settings.showProBass") private var showProBass = true
    @AppStorage("fst.settings.showKaraoke") private var showKaraoke = true
    @AppStorage("fst.settings.showProCymbals") private var showProCymbals = true
    @AppStorage("fst.settings.showProDrums") private var showProDrums = true

    @AppStorage("fst.settings.metadataScore") private var metadataScore = true
    @AppStorage("fst.settings.metadataPercentage") private var metadataPercentage = true
    @AppStorage("fst.settings.metadataPercentile") private var metadataPercentile = true
    @AppStorage("fst.settings.metadataSeason") private var metadataSeason = true
    @AppStorage("fst.settings.metadataIntensity") private var metadataIntensity = true
    @AppStorage("fst.settings.metadataDifficulty") private var metadataDifficulty = true
    @AppStorage("fst.settings.metadataStars") private var metadataStars = true
    @AppStorage("fst.settings.metadataLastPlayed") private var metadataLastPlayed = true

    @AppStorage("fst.accessibility.reduceMotion") private var reduceMotion = false
    @AppStorage("fst.accessibility.disableAnimatedArtwork") private var disableAnimatedArtwork = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false

    @State private var resetPending = false
    @State private var serviceStatus: String?

    let session: FestivalSession
    let isVisible: Bool

    /// Keep settings on the same process-scoped API session as the Songs tab.
    ///
    /// - Parameters:
    ///   - session: Shared service and artwork connection.
    ///   - isVisible: True only while the Settings destination is selected.
    init(session: FestivalSession, isVisible: Bool = true) {
        self.session = session
        self.isVisible = isVisible
    }

    var body: some View {
        Form {
            Section {
                Text("Additional options become available as their native pages are built.")
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.textSecondary)
                Toggle("Show Instrument Icons", isOn: $showInstrumentIcons)
                    .accessibilityHint(
                        "Shows score and full combo status for each enabled chart on "
                            + "unfiltered Songs cards when a player is selected"
                    )
                    .accessibilityIdentifier("fst.settings.show-instrument-icons")
                Text("Star: full combo · Check: scored · Minus: no score · "
                     + "Slash: not charted · Exclamation: inconsistent score")
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.textSecondary)
                Toggle("Filter Invalid Scores", isOn: $filterInvalidScores)
                if filterInvalidScores {
                    VStack(alignment: .leading) {
                        Text("Max Score Leeway: \(ScoreFormatting.leeway(leeway))")
                        Slider(
                            value: Binding(
                                get: { leeway },
                                set: { leeway = min(5, max(-5, ($0 * 10).rounded() / 10)) }
                            ), in: -5...5, step: 0.1
                        )
                            .accessibilityLabel("Max Score Leeway")
                            .accessibilityValue(ScoreFormatting.leeway(leeway))
                            .accessibilityIdentifier("fst.settings.leeway")
                    }
                }
                Picker("CHOpt Path Default View", selection: $pathDefaultView) {
                    Text("Image").tag(PathDisplayMode.image)
                    Text("Text").tag(PathDisplayMode.text)
                }
                .accessibilityValue(pathDefaultView.label)
                .accessibilityIdentifier("fst.settings.path-default-view")
                Toggle("Experimental Ranks", isOn: $experimentalRanks)
                    .disabled(true)
                    .accessibilityHint("Experimental ranks are not yet available")
            } header: {
                Text("App Settings").foregroundStyle(BrandTokens.textSecondary)
            }
            Section {
                Toggle("Reduce Motion", isOn: $reduceMotion)
                    .accessibilityIdentifier("fst.settings.reduce-motion")
                Toggle("Disable Animated Artwork", isOn: $disableAnimatedArtwork)
                    .accessibilityIdentifier("fst.settings.disable-artwork-animation")
                Toggle("Increase Contrast", isOn: $moreContrast)
                    .accessibilityIdentifier("fst.settings.more-contrast")
                Toggle("Reduce Transparency", isOn: $lessTransparency)
                    .accessibilityIdentifier("fst.settings.less-transparency")
                Text(
                    "Off follows system appearance; On adds an app override. "
                    + "VoiceOver and text size are managed in device Settings."
                )
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.textSecondary)
            } header: {
                Text("Accessibility").foregroundStyle(BrandTokens.textSecondary)
            }
            Section {
                Text("Hiding the shop also hides its entry. Your highlight preference is retained.")
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.textSecondary)
                Toggle("Hide Item Shop", isOn: $hideShop)
                    .accessibilityIdentifier("fst.settings.hide-shop")
                Toggle(
                    "Highlight Shop Items",
                    isOn: Binding(
                        get: { !disableShopHighlighting },
                        set: { disableShopHighlighting = !$0 }
                    )
                )
                .disabled(hideShop)
                .accessibilityIdentifier("fst.settings.shop-highlights")
            } header: {
                Text("Item Shop").foregroundStyle(BrandTokens.textSecondary)
            }
            Section {
                ForEach(Instrument.allCases) { instrument in
                    let shown = instrumentBinding(for: instrument)
                    Toggle(instrument.label, isOn: shown)
                        .disabled(shown.wrappedValue && visibleInstrumentCount <= 1)
                        .accessibilityIdentifier(
                            "fst.settings.instrument.\(instrument.rawValue)"
                        )
                }
            } header: {
                Text("Show Instruments").foregroundStyle(BrandTokens.textSecondary)
            }
            Section {
                Text(session.selectedPlayer == nil
                    ? "Select a player to customize score metadata."
                    : showInstrumentIcons
                        ? "With icons and All instruments, status chips replace score "
                            + "metadata. Turn icons off or filter one chart to show these fields."
                        : "Visible score fields update Songs cards. The source's "
                            + "metadata ordering and Last Played sort are still being ported.")
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.textSecondary)
                ForEach(MetadataField.allCases) { field in
                    Toggle(field.label, isOn: metadataBinding(for: field))
                        .disabled(session.selectedPlayer == nil && field != .intensity)
                        .accessibilityHint(metadataHint(for: field))
                        .accessibilityIdentifier("fst.settings.metadata.\(field.rawValue)")
                }
            } header: {
                Text("Show Metadata").foregroundStyle(BrandTokens.textSecondary)
            }
            Section {
                Button("Check Publication") { Task { await refreshService() } }
                if let serviceStatus {
                    Text(serviceStatus)
                        .accessibilityIdentifier("fst.settings.publication-status")
                }
            } header: {
                Text("Service").foregroundStyle(BrandTokens.textSecondary)
            }
            Section {
                Button("Reset App Settings", role: .destructive) {
                    resetPending = true
                }
                .accessibilityIdentifier("fst.settings.reset")
            } header: {
                Text("Reset").foregroundStyle(BrandTokens.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .festivalBackground(.carousel, session: session, visible: isVisible)
        .navigationTitle("Settings")
        .confirmationDialog(
            "Reset app settings only?",
            isPresented: $resetPending,
            titleVisibility: .visible
        ) {
            Button("Reset App Settings", role: .destructive) { resetAppSettings() }
        } message: {
            Text("Your profile, song filters and navigation history will remain.")
        }
    }

    // MARK: - Instrument and metadata policies

    /// Preserve at least one visible instrument, not a metadata minimum.
    ///
    /// - Parameters:
    ///   - activeCount: Number of enabled chart visibility switches.
    ///   - currentlyShown: Whether this switch would turn off a visible chart.
    /// - Returns: True when an instrument toggle is allowed.
    nonisolated static func canToggleInstrument(activeCount: Int, currentlyShown: Bool) -> Bool {
        !currentlyShown || activeCount > 1
    }

    private var visibleInstrumentCount: Int {
        [
            showLead, showBass, showDrums, showVocals, showProLead, showProBass,
            showKaraoke, showProCymbals, showProDrums,
        ].filter { $0 }.count
    }

    /// Map a chart ID to its single persisted native switch.
    ///
    /// - Parameter instrument: Solo chart identifier.
    /// - Returns: SwiftUI binding to the corresponding visibility setting.
    private func instrumentBinding(for instrument: Instrument) -> Binding<Bool> {
        switch instrument {
        case .lead: $showLead
        case .bass: $showBass
        case .drums: $showDrums
        case .vocals: $showVocals
        case .proLead: $showProLead
        case .proBass: $showProBass
        case .karaoke: $showKaraoke
        case .proCymbals: $showProCymbals
        case .proDrums: $showProDrums
        }
    }

    /// Map a metadata key to its independent persisted switch.
    ///
    /// - Parameter field: Content property shown on a song row.
    /// - Returns: Binding to its stored preference.
    private func metadataBinding(for field: MetadataField) -> Binding<Bool> {
        switch field {
        case .score: $metadataScore
        case .percentage: $metadataPercentage
        case .percentile: $metadataPercentile
        case .season: $metadataSeason
        case .intensity: $metadataIntensity
        case .difficulty: $metadataDifficulty
        case .stars: $metadataStars
        case .lastPlayed: $metadataLastPlayed
        }
    }

    /// Keep the anonymous difficulty meter adjustable when score fields require a player.
    ///
    /// - Parameter field: Metadata setting that supplies a Song-row label or meter.
    /// - Returns: Explanation of the actual currently supported row effect.
    private func metadataHint(for field: MetadataField) -> String {
        if field == .intensity {
            return "Controls song Intensity on selected score cards or filtered anonymous rows"
        }
        if field == .lastPlayed {
            return session.selectedPlayer == nil
                ? "Select a player to show the saved date"
                : "Shows the saved date on native Songs cards; Last Played sort is not yet available"
        }
        return session.selectedPlayer == nil
            ? "Select a player to use score metadata"
            : "Updates Songs score fields when icons are off or one chart is filtered"
    }

    // MARK: - Service and reset

    /// Show publication state, or an explicit failure, without a privileged key.
    func refreshService() async {
        do {
            let publication = try await session.refreshPublication()
            do {
                let catalog = try await session.catalog()
                try Task.checkCancellation()
                serviceStatus = SettingsServiceSummary.message(for: catalog)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                serviceStatus = "Publication \(publication.publicationId); songs update failed: "
                    + error.localizedDescription
                return
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            serviceStatus = "Publication unavailable: \(error.localizedDescription)"
        }
    }

    /// Restore app settings only, never a selected profile or Songs navigation.
    func resetAppSettings() {
        showInstrumentIcons = true
        filterInvalidScores = false
        leeway = 1
        pathDefaultView = .image
        pathWarningDismissed = false
        experimentalRanks = false
        hideShop = false
        disableShopHighlighting = false
        showLead = true
        showBass = true
        showDrums = true
        showVocals = true
        showProLead = true
        showProBass = true
        showKaraoke = true
        showProCymbals = true
        showProDrums = true
        metadataScore = true
        metadataPercentage = true
        metadataPercentile = true
        metadataSeason = true
        metadataIntensity = true
        metadataDifficulty = true
        metadataStars = true
        metadataLastPlayed = true
        reduceMotion = false
        disableAnimatedArtwork = false
        moreContrast = false
        lessTransparency = false
    }
}

/// The eight independent song-metadata visibility controls.
enum MetadataField: String, CaseIterable, Identifiable {
    case score
    case percentage
    case percentile
    case season
    case intensity
    case difficulty
    case stars
    case lastPlayed

    var id: Self { self }
    var label: String {
        switch self {
        case .score: "Score"
        case .percentage: "Percentage"
        case .percentile: "Percentile"
        case .season: "Season Achieved"
        case .intensity: "Intensity"
        case .difficulty: "Game Difficulty"
        case .stars: "Stars"
        case .lastPlayed: "Last Played"
        }
    }
}
