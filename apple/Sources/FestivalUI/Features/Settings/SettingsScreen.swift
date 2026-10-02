import SwiftUI
import FestivalCore
import FestivalDesign

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
    /// Suggestions' own persisted filter draft (Lane G). Not shown in this screen's
    /// UI — Suggestions reads/writes it directly — but "Reset App Settings" restores
    /// every registered app preference, so it is reset here too.
    @AppStorage(SuggestionFilterSettings.storageKey) private var suggestionFilterData = Data()

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
    @State private var serviceVersion: String?
    @State private var serviceVersionFailed = false
    @State private var showingWhatsNew = false
    /// Open Report an Issue / Request a Feature form, if any (issue #78).
    @State private var feedbackForm: FeedbackKind?
    /// The service accepts in-app feedback (`GET /api/features` → `feedback`). The rows stay
    /// hidden until it says so; a failed read is retried on the next Settings visit.
    @State private var feedbackEnabled = false
    @State private var quickLinks = QuickLinksController()
    /// A reorder row is lifted, so the page must not scroll under the drag.
    @State private var reorderDragging = false

    let session: FestivalSession
    let isVisible: Bool
    @Environment(\.deviceLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnvironment

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
            // A plain VStack (not Lazy): the page is short, and a lazily recycled card would
            // replay its load-in fade when scrolled back into view.
            VStack(alignment: .leading, spacing: 28) {
                appSettings.festivalFadeIn(isLoaded: true, index: 0)
                diagnostics.festivalFadeIn(isLoaded: true, index: 1)
                accessibility
                    .quickLinkSection(
                        id: "accessibility", title: "Accessibility", symbol: "accessibility"
                    )
                    .festivalFadeIn(isLoaded: true, index: 2)
                itemShop.quickLinkSection(id: "item-shop", title: "Item Shop", symbol: "bag.fill")
                    .festivalFadeIn(isLoaded: true, index: 3)
                instruments.quickLinkSection(
                    id: "show-instruments", title: "Show Instruments", symbol: "music.note"
                )
                .festivalFadeIn(isLoaded: true, index: 4)
                metadata.quickLinkSection(
                    id: "show-metadata", title: "Show Instrument Metadata", symbol: "list.bullet"
                )
                .festivalFadeIn(isLoaded: true, index: 5)
                version.quickLinkSection(
                    id: "version", title: "Festival Score Tracker Version", symbol: "info.circle"
                )
                    .festivalFadeIn(isLoaded: true, index: 6)
                SettingsServiceInfoSection(session: session, isVisible: isVisible)
                    .quickLinkSection(
                        id: "service-info", title: ServiceInfoText.title, symbol: "server.rack"
                    )
                    .festivalFadeIn(isLoaded: true, index: 7)
                if SettingsFixtureTools.isEnabled() {
                    SettingsFixtureToolsSection(session: session)
                }
                // Past the first screenful: `festivalFadeIn` shows these without a delay.
                FirstRunSettingsSection(session: session)
                    .quickLinkSection(id: "first-run", title: "First Run Guides", symbol: "sparkles")
                    .festivalFadeIn(isLoaded: true, index: 8)
                licensesRow.quickLinkSection(id: "licenses", title: "Licenses", symbol: "doc.text")
                    .festivalFadeIn(isLoaded: true, index: 9)
                reset.quickLinkSection(id: "reset", title: "Reset Settings", symbol: "trash")
                    .festivalFadeIn(isLoaded: true, index: 10)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .modifier(ReadableWidthContainer(isRegularWidth: layout.widthClass == .regular))
        }
        .scrollDisabled(reorderDragging)
        .onPreferenceChange(SettingsReorderDragActiveKey.self) { reorderDragging = $0 }
        .quickLinks(quickLinks, title: "Quick Links")
        .scrollDismissesKeyboard(.interactively)
        .festivalBackground(.carousel, session: session, visible: isVisible)
        .navigationTitle("Settings")
        .toolbar {
            QuickLinksToolbarItem(quickLinks)
            FestivalRootTrailingItems(session: session)
        }
        .festivalProvidesRootTrailingItems()
        .confirmationDialog(
            "Reset Settings",
            isPresented: $resetPending,
            titleVisibility: .visible
        ) {
            Button("Reset App Settings", role: .destructive) { resetAppSettings() }
        } message: {
            Text(
                "Are you sure you want to restore all settings to their default values? "
                    + "Your profile, song filters and navigation history will remain."
            )
        }
        .sheet(item: $feedbackForm, onDismiss: FeedbackFormModel.purgeStagedMedia) { kind in
            FeedbackFormSheet(kind: kind, session: session)
                .festivalSheet(.large)
        }
        .whatsNewPresentation(isPresented: $showingWhatsNew) {
            WhatsNewSheet(
                version: WhatsNewGate.appVersion(),
                entries: Changelog.displayEntries(distribution: AppDistribution.resolved ?? .appStore)
            ) {
                ChangelogSeenStore().markSeen(version: WhatsNewGate.appVersion())
                showingWhatsNew = false
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            async let features: Void = loadFeedbackAvailability()
            if serviceVersion == nil { await loadServiceVersion() }
            await features
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
            Toggle(isOn: $enableVisualOrder.animation(reduceMotionAnimation)) {
                SettingLabel(
                    "Enable Independent Song Row Visual Order",
                    detail: "When enabled, the metadata display order on song rows is controlled "
                        + "separately from sort priority. When disabled, metadata follows sort "
                        + "priority order."
                )
            }
            .accessibilityIdentifier("fst.settings.enable-visual-order")
            if enableVisualOrder {
                // Shown directly under its switch, like the web's collapse (no disclosure).
                reorderBlock(
                    "Song Row Visual Order",
                    detail: "When filtering to a single instrument in the song list, extra "
                        + "metadata is displayed. Choose the order it appears in on the bottom row."
                ) {
                    if visibleVisualOrder.isEmpty {
                        Text("No metadata fields are currently visible.")
                            .font(.subheadline)
                            .foregroundStyle(FestivalText.primary)
                    } else {
                        SettingsReorderList(
                            items: visibleVisualOrder,
                            identifier: "fst.settings.song-row-order",
                            label: \.reorderLabel, key: \.rawValue
                        ) { reordered in
                            songRowVisualOrder.wrappedValue = SettingsReorder.merging(
                                visible: reordered, into: songRowVisualOrder.wrappedValue
                            )
                        }
                    }
                }
            }
            SettingsChoiceRow(
                title: "CHOpt Path Default View",
                detail: "Choose whether CHOpt paths open as an image or text table by default.",
                options: PathDisplayMode.allCases,
                label: \.label,
                selection: $pathDefaultView,
                identifier: "fst.settings.path-default-view",
                animation: reduceMotionAnimation
            )
            reorderBlock(
                "CHOpt Text Path Column Order",
                detail: "Choose the order columns appear in the CHOpt text path view."
            ) {
                SettingsReorderList(
                    items: pathColumnOrder.wrappedValue,
                    identifier: "fst.settings.path-column-order",
                    label: \.label, key: \.rawValue
                ) { pathColumnOrder.wrappedValue = $0 }
            }
            Toggle(isOn: $filterInvalidScores.animation(reduceMotionAnimation)) {
                SettingLabel(
                    "Filter Invalid Scores",
                    detail: "When enabled, the app will attempt to filter out invalid leaderboard "
                        + "values based on the maximum score derived from the CHOpt path."
                )
            }
            .accessibilityIdentifier("fst.settings.filter-invalid-scores")
            if filterInvalidScores {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Maximum Score Leeway: \(ScoreFormatting.leeway(leeway))")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FestivalText.primary)
                    Text(
                        "A CHOpt path with a max score of 100k and "
                            + "\(ScoreFormatting.leeway(leeway)) leeway accepts scores up to "
                            + "\(maxEffectiveScore) as valid."
                    )
                    .font(.footnote)
                    .foregroundStyle(FestivalText.primary)
                    Slider(
                        value: Binding(
                            get: { leeway },
                            set: { leeway = InvalidScoreFilter.normalized($0) }
                        ),
                        in: InvalidScoreFilter.range, step: InvalidScoreFilter.step
                    )
                    .accessibilityLabel("Max Score Leeway")
                    .accessibilityValue(ScoreFormatting.leeway(leeway))
                    .accessibilityIdentifier("fst.settings.leeway")
                }
            }
            Toggle(isOn: $experimentalRanks) {
                SettingLabel(
                    "Experimental Ranks",
                    detail: "More ranking mechanisms for Leaderboards. Not yet available."
                )
            }
            .disabled(true)
            .accessibilityHint("Experimental ranks are not yet available")
            if feedbackEnabled {
                feedbackRow(
                    .bug, detail: "Tell us about something that isn't working.",
                    action: "Report", identifier: "fst.settings.report-issue"
                )
                feedbackRow(
                    .feature, detail: "Suggest something new for Festival Score Tracker.",
                    action: "Request", identifier: "fst.settings.request-feature"
                )
            }
        }
        .quickLinkSection(id: "app-settings", title: "App Settings", symbol: "gearshape.fill")
    }

    /// A row that opens the bug or feature form, styled like What's New's "Show" row.
    private func feedbackRow(
        _ kind: FeedbackKind, detail: String, action: String, identifier: String
    ) -> some View {
        Button { feedbackForm = kind } label: {
            HStack {
                SettingLabel(kind.formTitle, detail: detail)
                Spacer(minLength: 8)
                Text(action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTokens.accentBlue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityHint("Opens a form that files it on GitHub")
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
                    : "Visible score fields update Songs cards. Enable Independent Song Row "
                        + "Visual Order above to choose which field leads; Last Played sort is "
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
        .quickLinkSection(id: "diagnostics", title: "Diagnostics", symbol: "info.circle")
        #endif
    }

    private var version: some View {
        FestivalGlassSection(
            "Festival Score Tracker Version",
            subtitle: "Festival Score Tracker information to help with debugging."
        ) {
            versionRow("App Version", value: appVersionText)
            versionRow("Build Configuration", value: buildConfigurationText)
            versionRow("Service Version", value: serviceVersionText)
            Button { showingWhatsNew = true } label: {
                HStack {
                    SettingLabel("What's New", detail: "Recent changes to Festival Score Tracker.")
                    Spacer(minLength: 8)
                    Text("Show")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrandTokens.accentBlue)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("fst.settings.whats-new")
            .accessibilityHint("Shows the latest changelog")
        }
    }

    private func versionRow(_ label: String, value: String) -> some View {
        HStack {
            SettingLabel(label)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(FestivalText.primary)
        }
    }

    /// The web's standalone Licenses link: its section title and description with a
    /// trailing chevron, the whole row tappable, no card (`SettingsPage.tsx` "Licenses").
    private var licensesRow: some View {
        NavigationLink(value: AppRoute.licenses) {
            HStack(alignment: .center, spacing: 16) {
                FestivalSectionHeader("Licenses", subtitle: "Open source package license details.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("View Licenses")
        .accessibilityHint("Open source package license details")
        .accessibilityIdentifier("fst.settings.licenses")
    }

    /// An inline reorder list with its bold title and description, the web's
    /// `innerSectionTitle` + `sectionHint` + `ReorderList` block.
    ///
    /// - Parameters:
    ///   - title: Title Case block title.
    ///   - detail: Sentence-case description.
    ///   - list: The reorder list (or its empty state).
    private func reorderBlock<List: View>(
        _ title: String, detail: String, @ViewBuilder list: () -> List
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(FestivalText.primary)
                .fixedSize(horizontal: false, vertical: true)
            list()
                .padding(.top, 8)
        }
    }

    private var reset: some View {
        // The web's reset block: header, then a full-width red (`btnDanger`) button.
        VStack(alignment: .leading, spacing: 12) {
            FestivalSectionHeader(
                "Reset Settings", subtitle: "Restore all settings to their default values."
            )
            .padding(.horizontal, 4)
            Button(role: .destructive) {
                resetPending = true
            } label: {
                Text("Reset App Settings")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .foregroundStyle(.white)
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

    /// The saved Song row order limited to currently visible metadata fields (the web's
    /// `visualOrderItems`); hidden fields keep their place after a reorder.
    private var visibleVisualOrder: [MetadataField] {
        songRowVisualOrder.wrappedValue.filter { metadataBinding(for: $0).wrappedValue }
    }

    /// Enable/disable animation for inline blocks, none under Reduce Motion.
    private var reduceMotionAnimation: Animation? {
        reduceMotionEnvironment || reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    /// The highest score Filter Invalid Scores accepts for the web's 100k example path.
    private var maxEffectiveScore: String {
        InvalidScoreFilter.ceiling(maxScore: InvalidScoreFilter.exampleMaxScore, leeway: leeway)
            .formatted()
    }

    /// The app's marketing/build version plus the release commit, e.g. "1.0 (12) · 42edc57"
    /// (no commit for `dev` builds; see `AppBuildInfo`).
    private var appVersionText: String {
        AppBuildInfo.versionText(Bundle.main.infoDictionary)
    }

    /// Debug vs Release, useful context when a user reports a bug.
    private var buildConfigurationText: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    /// The live service build from keyless `GET /api/version` (pure read; see
    /// `.agents/platforms/service-safety.md`), "Loading" until it answers.
    private var serviceVersionText: String {
        serviceVersion ?? (serviceVersionFailed ? "Unavailable" : "Loading")
    }

    /// Show the feedback rows once the service reports in-app feedback is on (pure
    /// `GET /api/features`). Off or unreadable keeps them hidden; an open form stays open.
    func loadFeedbackAvailability() async {
        guard !feedbackEnabled else { return }
        do {
            feedbackEnabled = try await session.client().feedbackEnabled()
        } catch {
            feedbackEnabled = false
        }
    }

    /// Read the service version once per visible Settings session.
    func loadServiceVersion() async {
        do {
            let value = try await session.client().serviceVersion()
            serviceVersion = value
            serviceVersionFailed = false
        } catch {
            if error is CancellationError { return }
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            serviceVersionFailed = true
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
        suggestionFilterData = Data()
    }
}

// MARK: - Readable width

/// Caps Settings' content to a readable column and centers it on a regular-width
/// window (Duo unfolded, iPad), instead of stretching every toggle row edge to edge
/// or splitting into a 2-column grid: Settings rows are label/control pairs, not
/// dashboard cards, so a wide row just reads worse
/// (`.agents/design/apple/duo.md` "Settings, Shop, Bands — … readable-width Settings").
/// A compact window (iPhone, Duo folded) is unaffected — this only activates once a
/// caller passes `isRegularWidth: true`.
struct ReadableWidthContainer: ViewModifier {
    let isRegularWidth: Bool
    /// Roughly a Dynamic Type–friendly settings form width, well under an iPad or
    /// unfolded Duo's full window.
    private static let maxWidth: CGFloat = 680

    func body(content: Content) -> some View {
        if isRegularWidth {
            content
                .frame(maxWidth: Self.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

// MARK: - Row label

/// Title plus optional description, the web's setting-row layout (`toggleLabel` is
/// semibold; the description stays regular and white per the white-text rule).
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
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
        case .difficulty: "Difficulty"
        case .stars: "Stars"
        case .lastPlayed: "Last Played"
        }
    }

    /// Row title in the Song Row Visual Order list (web `METADATA_SORT_DISPLAY`).
    var reorderLabel: String {
        self == .intensity ? "Song Intensity" : label
    }
}
