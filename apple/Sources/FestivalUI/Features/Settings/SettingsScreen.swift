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

    @AppStorage("fst.settings.enableVisualOrder") private var enableVisualOrder = false
    @AppStorage("fst.settings.songRowVisualOrder")
    private var songRowVisualOrderRaw = SettingsOrder.encode(MetadataField.allCases)
    @AppStorage("fst.settings.pathColumnOrder")
    private var pathColumnOrderRaw = SettingsOrder.encode(PathColumnKey.allCases)

    @AppStorage("fst.settings.tapDiagnostics") private var tapDiagnostics = false
    @AppStorage("fst.settings.tapTelemetry") private var tapTelemetry = false

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
    @State private var showingVisualOrderSheet = false
    @State private var showingPathColumnSheet = false

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                appSettings
                diagnostics
                accessibility
                itemShop
                instruments
                metadata
                version
                service
                about
                reset
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
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
        .sheet(isPresented: $showingVisualOrderSheet) {
            SettingsReorderSheet(
                title: "Song Row Order",
                subtitle: "Sets the order visible metadata fields appear on Songs cards. "
                    + "Fields turned off in Show Instrument Metadata are skipped.",
                items: songRowVisualOrder,
                label: \.label
            )
        }
        .sheet(isPresented: $showingPathColumnSheet) {
            SettingsReorderSheet(
                title: "Path Column Order",
                subtitle: "Sets the column order for the CHOpt Paths text table.",
                items: pathColumnOrder,
                label: \.label
            )
        }
    }

    // MARK: - Sections

    private var appSettings: some View {
        FestivalGlassSection(
            "App Settings", subtitle: "General Festival Score Tracker app settings."
        ) {
            Toggle(isOn: $showInstrumentIcons) {
                SettingLabel(
                    "Show Instrument Icons",
                    detail: "Star: full combo · Check: scored · Minus: no score · "
                        + "Slash: not charted · Exclamation: inconsistent score"
                )
            }
            .accessibilityHint(
                "Shows score and full combo status for each enabled chart on "
                    + "unfiltered Songs cards when a player is selected"
            )
            .accessibilityIdentifier("fst.settings.show-instrument-icons")
            Toggle(isOn: $enableVisualOrder) {
                SettingLabel(
                    "Enable Song Row Visual Order",
                    detail: "Reorder which visible metadata field appears first on Songs cards."
                )
            }
            .accessibilityIdentifier("fst.settings.enable-visual-order")
            if enableVisualOrder {
                reorderRow(
                    "Song Row Order",
                    detail: visibleVisualOrderSummary,
                    identifier: "fst.settings.song-row-order"
                ) { showingVisualOrderSheet = true }
            }
            Toggle(isOn: $filterInvalidScores) {
                SettingLabel(
                    "Filter Invalid Scores",
                    detail: "Hide scores that exceed the CHOpt maximum by more than the leeway."
                )
            }
            if filterInvalidScores {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Score Leeway: \(ScoreFormatting.leeway(leeway))")
                        .foregroundStyle(BrandTokens.textPrimary)
                    Text("Scores up to \(maxEffectiveScore) count as valid before filtering.")
                        .font(.footnote)
                        .foregroundStyle(BrandTokens.textSecondary)
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
            LabeledContent {
                Picker("CHOpt Path Default View", selection: $pathDefaultView) {
                    Text("Image").tag(PathDisplayMode.image)
                    Text("Text").tag(PathDisplayMode.text)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityValue(pathDefaultView.label)
                .accessibilityIdentifier("fst.settings.path-default-view")
            } label: {
                SettingLabel("CHOpt Path Default View")
            }
            reorderRow(
                "CHOpt Path Column Order",
                detail: pathColumnOrder.wrappedValue.map(\.label).joined(separator: " · "),
                identifier: "fst.settings.path-column-order"
            ) { showingPathColumnSheet = true }
            Toggle(isOn: $experimentalRanks) {
                SettingLabel(
                    "Experimental Ranks",
                    detail: "More ranking mechanisms for Leaderboards. Not yet available."
                )
            }
            .disabled(true)
            .accessibilityHint("Experimental ranks are not yet available")
        }
    }

    private var accessibility: some View {
        FestivalGlassSection(
            "Accessibility",
            subtitle: "Off follows your device; On adds an app override. "
                + "VoiceOver and text size are managed in device Settings."
        ) {
            Toggle(isOn: $reduceMotion) { SettingLabel("Reduce Motion") }
                .accessibilityIdentifier("fst.settings.reduce-motion")
            Toggle(isOn: $disableAnimatedArtwork) { SettingLabel("Disable Animated Artwork") }
                .accessibilityIdentifier("fst.settings.disable-artwork-animation")
            Toggle(isOn: $moreContrast) { SettingLabel("Increase Contrast") }
                .accessibilityIdentifier("fst.settings.more-contrast")
            Toggle(isOn: $lessTransparency) {
                SettingLabel("Reduce Transparency", detail: "Replaces glass with solid surfaces.")
            }
            .accessibilityIdentifier("fst.settings.less-transparency")
        }
    }

    private var itemShop: some View {
        FestivalGlassSection(
            "Item Shop", subtitle: "Control how Item Shop availability is displayed."
        ) {
            Toggle(isOn: $hideShop) {
                SettingLabel(
                    "Hide Item Shop",
                    detail: "Also hides its menu entry. Your highlight preference is retained."
                )
            }
            .accessibilityIdentifier("fst.settings.hide-shop")
            Toggle(
                isOn: Binding(
                    get: { !disableShopHighlighting },
                    set: { disableShopHighlighting = !$0 }
                )
            ) {
                SettingLabel("Highlight Shop Items")
            }
            .disabled(hideShop)
            .accessibilityIdentifier("fst.settings.shop-highlights")
        }
    }

    private var instruments: some View {
        FestivalGlassSection(
            "Show Instruments",
            subtitle: "Choose which instruments to display throughout the app."
        ) {
            ForEach(Instrument.allCases) { instrument in
                let shown = instrumentBinding(for: instrument)
                Toggle(isOn: shown) {
                    HStack(spacing: 12) {
                        InstrumentIcon(instrument, size: 28)
                            .accessibilityHidden(true)
                        SettingLabel(instrument.label)
                    }
                }
                .disabled(shown.wrappedValue && visibleInstrumentCount <= 1)
                .accessibilityLabel(instrument.label)
                .accessibilityIdentifier("fst.settings.instrument.\(instrument.rawValue)")
            }
        }
    }

    private var metadata: some View {
        FestivalGlassSection(
            "Show Instrument Metadata",
            subtitle: session.selectedPlayer == nil
                ? "Select a player to customize score metadata."
                : showInstrumentIcons
                    ? "With icons and All instruments, status chips replace score "
                        + "metadata. Turn icons off or filter one chart to show these fields."
                    : "Visible score fields update Songs cards. Enable Song Row Visual "
                        + "Order above to choose which field leads; Last Played sort is "
                        + "still being ported."
        ) {
            ForEach(MetadataField.allCases) { field in
                Toggle(isOn: metadataBinding(for: field)) { SettingLabel(field.label) }
                    .disabled(session.selectedPlayer == nil && field != .intensity)
                    .accessibilityHint(metadataHint(for: field))
                    .accessibilityIdentifier("fst.settings.metadata.\(field.rawValue)")
            }
        }
    }

    /// Debug-only tap diagnostics, the native form of `SettingsPage.tsx:631-654`.
    ///
    /// Hidden in Release; no diagnostics collector reads these yet, but the toggles
    /// persist so the wiring is ready when one lands.
    @ViewBuilder private var diagnostics: some View {
        #if DEBUG
        FestivalGlassSection(
            "Diagnostics",
            subtitle: "Debug-only tools for investigating touch handling issues."
        ) {
            Toggle(isOn: $tapDiagnostics) {
                SettingLabel(
                    "Tap Diagnostics",
                    detail: "Record on-device touch handling details for troubleshooting."
                )
            }
            .onChange(of: tapDiagnostics) { _, enabled in
                if !enabled { tapTelemetry = false }
            }
            .accessibilityIdentifier("fst.settings.tap-diagnostics")
            Toggle(isOn: $tapTelemetry) {
                SettingLabel(
                    "Tap Telemetry",
                    detail: tapDiagnostics
                        ? "Include tap diagnostics in crash and issue reports."
                        : "Turn on Tap Diagnostics first."
                )
            }
            .disabled(!tapDiagnostics)
            .accessibilityIdentifier("fst.settings.tap-telemetry")
        }
        #endif
    }

    private var version: some View {
        FestivalGlassSection("Version", subtitle: "Build information for support requests.") {
            versionRow("App Version", value: appVersionText)
            versionRow("Build Configuration", value: buildConfigurationText)
            versionRow("Service Version", value: serviceVersionText)
        }
    }

    private func versionRow(_ label: String, value: String) -> some View {
        HStack {
            SettingLabel(label)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(BrandTokens.textSecondary)
        }
    }

    private var service: some View {
        FestivalGlassSection("Service", subtitle: "Check the live score publication.") {
            Button("Check Publication") { Task { await refreshService() } }
                .frame(maxWidth: .infinity, alignment: .leading)
            if let serviceStatus {
                Text(serviceStatus)
                    .font(.subheadline)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .accessibilityIdentifier("fst.settings.publication-status")
            }
        }
    }

    private var about: some View {
        FestivalGlassSection("Licenses", subtitle: "Open source package license details.") {
            navigationRow("View Licenses", route: .licenses, identifier: "fst.settings.licenses")
        }
    }

    private func navigationRow(_ title: String, route: AppRoute, identifier: String) -> some View {
        NavigationLink(value: route) {
            HStack {
                SettingLabel(title)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandTokens.textMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// A settings row that opens a `SettingsReorderSheet` instead of toggling in place.
    ///
    /// - Parameters:
    ///   - title: Title Case row label.
    ///   - detail: Current order, summarized for the collapsed row.
    ///   - identifier: Accessibility identifier for the row.
    ///   - open: Action that presents the reorder sheet.
    private func reorderRow(
        _ title: String, detail: String, identifier: String, open: @escaping () -> Void
    ) -> some View {
        Button(action: open) {
            HStack {
                SettingLabel(title, detail: detail)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandTokens.textMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var reset: some View {
        FestivalGlassSection(
            "Reset Settings", subtitle: "Restore all settings to their default values."
        ) {
            Button("Reset App Settings", role: .destructive) {
                resetPending = true
            }
            .tint(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("fst.settings.reset")
        }
    }

    // MARK: - Ordering, leeway and version

    /// Decode the persisted Song row field order, resilient to app updates.
    private var songRowVisualOrder: Binding<[MetadataField]> {
        Binding(
            get: { SettingsOrder.decode(songRowVisualOrderRaw) },
            set: { songRowVisualOrderRaw = SettingsOrder.encode($0) }
        )
    }

    /// Decode the persisted CHOpt Paths text-table column order.
    private var pathColumnOrder: Binding<[PathColumnKey]> {
        Binding(
            get: { SettingsOrder.decode(pathColumnOrderRaw) },
            set: { pathColumnOrderRaw = SettingsOrder.encode($0) }
        )
    }

    /// Summarize the fields Song rows would actually show, in the saved order.
    ///
    /// - Returns: Order preview limited to metadata fields that are currently visible.
    private var visibleVisualOrderSummary: String {
        let visible = songRowVisualOrder.wrappedValue.filter { metadataBinding(for: $0).wrappedValue }
        return visible.isEmpty
            ? "No metadata fields are currently visible."
            : visible.map(\.label).joined(separator: " · ")
    }

    /// CHOpt's engine-enforced highest raw score for any solo chart.
    private static let choptMaxScore = 100_000

    /// The highest score Filter Invalid Scores currently accepts as valid.
    private var maxEffectiveScore: String {
        let value = Int((Double(Self.choptMaxScore) * (1 + leeway / 100)).rounded())
        return value.formatted()
    }

    /// The app's marketing/build version, e.g. "1.0 (12)".
    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    /// Debug vs Release, useful context when a user reports a bug.
    private var buildConfigurationText: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    /// The live service's `/api/version` is not yet on the verified-read allowlist
    /// (`.agents/platforms/service-safety.md`), so this stays a disclosed placeholder
    /// rather than an unvetted network call.
    private var serviceVersionText: String { "Not yet available" }

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
        enableVisualOrder = false
        songRowVisualOrderRaw = SettingsOrder.encode(MetadataField.allCases)
        pathColumnOrderRaw = SettingsOrder.encode(PathColumnKey.allCases)
        filterInvalidScores = false
        leeway = 1
        pathDefaultView = .image
        pathWarningDismissed = false
        experimentalRanks = false
        hideShop = false
        disableShopHighlighting = false
        tapDiagnostics = false
        tapTelemetry = false
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

// MARK: - Row label

/// Title plus optional muted description, the web's setting-row layout.
struct SettingLabel: View {
    let title: String
    let detail: String?

    /// Create a label.
    ///
    /// - Parameters:
    ///   - title: Title Case setting name.
    ///   - detail: Optional sentence-case explanation.
    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(BrandTokens.textPrimary)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The eight independent song-metadata visibility controls.
enum MetadataField: String, CaseIterable, Identifiable, Hashable {
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
