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
    /// Privacy Policy sheet (issue #98).
    @State private var showingPrivacyPolicy = false
    /// Open Report an Issue / Request a Feature form, if any (issue #78).
    @State private var feedbackForm: FeedbackKind?
    /// The service accepts in-app feedback (`GET /api/features` → `feedback`). The rows stay
    /// hidden until it says so; a failed read is retried on the next Settings visit.
    @State private var feedbackEnabled = false
    @State private var quickLinks = QuickLinksController()
    /// A reorder row is lifted, so the page must not scroll under the drag.
    @State private var reorderDragging = false
    /// The page's measured size: its own column decides (the Licenses split, the Mac
    /// Settings window), not the window.
    @State private var pageSize: CGSize = .zero
    /// Accessibility text sizes keep one readable column (pattern `wide-columns` R7).
    @Environment(\.dynamicTypeSize) private var typeSize

    let session: FestivalSession
    let isVisible: Bool
    /// One Mac Settings pane's subset, or nil for the whole page (iPhone, iPad, web).
    let pane: SettingsPane?
    /// One list/detail topic's page on the right (issue #371), or nil.
    let topic: SettingsTopic?
    /// Set while the window allows Settings' list/detail split (iPad, unfolded iPhone Duo
    /// in landscape): the root page is then the list, its groups opening on the right.
    @Environment(\.listDetailSelect) private var listDetailSelect
    @Environment(\.deviceLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnvironment

    /// Keep settings on the same process-scoped API session as the Songs tab.
    ///
    /// - Parameters:
    ///   - session: Shared service and artwork connection.
    ///   - isVisible: True only while the Settings destination is selected.
    ///   - pane: A Mac Settings pane to show alone, or nil for the whole page.
    ///   - topic: A list/detail topic to show alone on the right, or nil.
    init(
        session: FestivalSession, isVisible: Bool = true, pane: SettingsPane? = nil,
        topic: SettingsTopic? = nil
    ) {
        self.session = session
        self.isVisible = isVisible
        self.pane = pane
        self.topic = topic
    }

    /// Whether sections show their titles: not on a topic page, whose pane title names it.
    private var showsSectionTitles: Bool { topic == nil }

    /// The root page as the list/detail list (issue #371): the window allows the split.
    private var isList: Bool {
        pane == nil && topic == nil && listDetailSelect?.accepts(.settingsTopic(.accessibility)) == true
    }

    /// The whole page or the list, with its Quick Links and root toolbar items.
    private var isRootPage: Bool { pane == nil && topic == nil }

    var body: some View {
        let columns = columns
        ScrollView {
            // Eager (not Lazy): the page is short, and a lazily recycled card would replay
            // its load-in fade when scrolled back into view. The Mac Settings window splits
            // its panes' sections into two balanced columns (pattern `wide-columns` R7).
            WideColumnStack(columns: columns, spacing: 28) {
                if let pane {
                    paneContent(pane)
                } else if let topic {
                    topicContent(topic)
                } else if isList {
                    listPage
                } else {
                    fullPage
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, pane == nil ? 8 : 20)
            .padding(.bottom, 32)
            .modifier(ReadableWidthContainer(isRegularWidth: layout.widthClass == .regular, columns: columns))
            // A scroll while the cards stagger in fades the rest in together (#323).
            .festivalFadeInScope()
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { pageSize = $0 }
        .debugPageScrollStress()
        .scrollDisabled(reorderDragging)
        .onPreferenceChange(SettingsReorderDragActiveKey.self) { reorderDragging = $0 }
        .modifier(SettingsQuickLinks(controller: quickLinks, isEnabled: isRootPage))
        .scrollDismissesKeyboard(.interactively)
        .festivalBackground(.carousel, session: session, visible: isVisible)
        .modifier(SettingsPageTitle(title: pane?.title ?? topic?.pageTitle ?? "Settings", isRoute: topic != nil))
        .toolbar {
            if isRootPage {
                QuickLinksToolbarItem(quickLinks)
                FestivalRootTrailingItems(session: session)
            }
        }
        .modifier(SettingsProvidesRootTrailingItems(isEnabled: topic == nil))
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
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicySheet()
        }
        .sheet(item: $feedbackForm, onDismiss: FeedbackFormModel.purgeStagedMedia) { kind in
            // Applies its own `.festivalSheet`, widening while its photo library is open.
            FeedbackFormSheet(kind: kind, session: session)
        }
        .whatsNewPresentation(isPresented: $showingWhatsNew) {
            WhatsNewChannelSheet(version: WhatsNewGate.appVersion()) {
                ChangelogSeenStore().markSeen(version: WhatsNewGate.appVersion())
                showingWhatsNew = false
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            // A topic page reads only what it shows: the service version on Version.
            async let features: Void = loadFeedbackAvailability()
            if serviceVersion == nil, topic == nil || topic == .version { await loadServiceVersion() }
            await features
        }
    }

    // MARK: - Page and panes

    /// Section columns: two in a Mac Settings pane when two columns fit, otherwise one;
    /// accessibility text sizes always stack (pattern `wide-columns` R1, R7). iPad and the
    /// unfolded iPhone Duo show the list/detail Settings in wide landscape instead of two
    /// columns (issue #371, which replaced #355's two-column page there).
    private var columns: Int {
        #if os(macOS)
        isList || topic != nil ? 1 : WideColumns.readable(WideColumns.count(size: pageSize), typeSize: typeSize)
        #else
        1
        #endif
    }

    /// The whole page in the web's order (iPhone, iPad).
    @ViewBuilder private var fullPage: some View {
                appSettings.festivalFadeIn(isLoaded: true, index: 0)
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
                // Past the first screenful: these fade in with the last staggered card,
                // or together with the rest when the page is scrolled (#323).
                FirstRunSettingsSection(session: session)
                    .quickLinkSection(id: "first-run", title: "First Run Guides", symbol: "sparkles")
                    .festivalFadeIn(isLoaded: true, index: 8)
                licensesRow.quickLinkSection(id: "licenses", title: "Licenses", symbol: "doc.text")
                    .festivalFadeIn(isLoaded: true, index: 9)
                privacyPolicyRow
                    .quickLinkSection(
                        id: "privacy-policy", title: "Privacy Policy", symbol: "hand.raised"
                    )
                    .festivalFadeIn(isLoaded: true, index: 10)
                reset.quickLinkSection(id: "reset", title: "Reset Settings", symbol: "trash")
                    .festivalFadeIn(isLoaded: true, index: 11)
    }

    /// The list/detail list (iPad, unfolded iPhone Duo in landscape; issue #371, owner-
    /// approved `split-panes` variant): the full page's order, with plain toggles acting
    /// in place and every group with more options a chevron row opening on the right.
    @ViewBuilder private var listPage: some View {
        appSettings.festivalFadeIn(isLoaded: true, index: 0)
        topicRow(.accessibility)
            .quickLinkSection(id: "accessibility", title: "Accessibility", symbol: "accessibility")
            .festivalFadeIn(isLoaded: true, index: 2)
        topicRow(.itemShop).quickLinkSection(id: "item-shop", title: "Item Shop", symbol: "bag.fill")
            .festivalFadeIn(isLoaded: true, index: 3)
        topicRow(.instruments)
            .quickLinkSection(id: "show-instruments", title: "Show Instruments", symbol: "music.note")
            .festivalFadeIn(isLoaded: true, index: 4)
        topicRow(.metadata)
            .quickLinkSection(id: "show-metadata", title: "Show Instrument Metadata", symbol: "list.bullet")
            .festivalFadeIn(isLoaded: true, index: 5)
        topicRow(.version)
            .quickLinkSection(id: "version", title: "Festival Score Tracker Version", symbol: "info.circle")
            .festivalFadeIn(isLoaded: true, index: 6)
        topicRow(.serviceInfo)
            .quickLinkSection(id: "service-info", title: ServiceInfoText.title, symbol: "server.rack")
            .festivalFadeIn(isLoaded: true, index: 7)
        if SettingsFixtureTools.isEnabled() {
            SettingsFixtureToolsSection(session: session)
        }
        topicRow(.firstRun)
            .quickLinkSection(id: "first-run", title: "First Run Guides", symbol: "sparkles")
            .festivalFadeIn(isLoaded: true, index: 8)
        licensesRow.quickLinkSection(id: "licenses", title: "Licenses", symbol: "doc.text")
            .festivalFadeIn(isLoaded: true, index: 9)
        topicRow(.privacyPolicy)
            .quickLinkSection(id: "privacy-policy", title: "Privacy Policy", symbol: "hand.raised")
            .festivalFadeIn(isLoaded: true, index: 10)
        reset.quickLinkSection(id: "reset", title: "Reset Settings", symbol: "trash")
            .festivalFadeIn(isLoaded: true, index: 11)
    }

    /// One topic's page on the right of the list/detail Settings: the same rows, storage
    /// keys and identifiers as the full page, untitled under the pane's own title.
    ///
    /// - Parameter topic: The open topic.
    @ViewBuilder private func topicContent(_ topic: SettingsTopic) -> some View {
        switch topic {
        case .songRowOrder:
            SettingsSectionCard(topic.rowTitle, subtitle: topic.subtitle, titled: false) {
                if enableVisualOrder {
                    songRowOrderList
                } else {
                    Text("Turn on Enable Independent Song Row Visual Order to choose this order.")
                        .font(.subheadline)
                        .foregroundStyle(FestivalText.primary)
                        .accessibilityIdentifier("fst.settings.song-row-order.off")
                }
            }
        case .paths:
            SettingsSectionCard(topic.rowTitle, subtitle: topic.subtitle, titled: false) {
                pathRows
            }
        case .accessibility: accessibility
        case .itemShop: itemShop
        case .instruments: instruments
        case .metadata: metadata
        case .version: version
        case .serviceInfo:
            SettingsServiceInfoSection(session: session, isVisible: isVisible, titled: false)
        case .firstRun:
            FirstRunSettingsSection(session: session, titled: false)
        case .privacyPolicy:
            PrivacyPolicyContent(policy: .current)
                .padding(.horizontal, 4)
        }
    }

    /// One Mac Settings pane: the same sections and rows (same storage keys and
    /// identifiers), grouped by topic.
    ///
    /// - Parameter pane: The selected pane.
    @ViewBuilder private func paneContent(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            accessibility
            itemShop
            FestivalGlassSection(
                "Leaderboards", subtitle: "Ranking options for the Leaderboards pages."
            ) {
                experimentalRanksRow
            }
            if feedbackEnabled {
                FestivalGlassSection(
                    "Feedback", subtitle: "Report an issue or request a feature on GitHub."
                ) {
                    feedbackRows
                }
            }
            reset
        case .songs:
            FestivalGlassSection(
                "Song Rows", subtitle: "How each song appears in the Songs list."
            ) {
                instrumentIconsRow
                visualOrderRows
            }
            instruments
            metadata
        case .paths:
            FestivalGlassSection(
                "CHOpt Paths", subtitle: "How optimal Overdrive paths open on a song's Paths page."
            ) {
                pathRows
            }
            FestivalGlassSection(
                "Invalid Scores",
                subtitle: "Uses the maximum score derived from each CHOpt path."
            ) {
                invalidScoreRows
            }
        case .guides:
            FirstRunSettingsSection(session: session)
        case .service:
            SettingsServiceInfoSection(session: session, isVisible: isVisible)
            if SettingsFixtureTools.isEnabled() {
                SettingsFixtureToolsSection(session: session)
            }
        case .about:
            version
            licensesRow
            privacyPolicyRow
        }
    }

    // MARK: - Sections

    private var appSettings: some View {
        FestivalGlassSection(
            "App Settings", subtitle: "General Festival Score Tracker app settings."
        ) {
            instrumentIconsRow
            visualOrderRows
            if isList {
                cardTopicRow(.paths)
            } else {
                pathRows
            }
            invalidScoreRows
            experimentalRanksRow
            if feedbackEnabled {
                feedbackRows
            }
        }
        .quickLinkSection(id: "app-settings", title: "App Settings", symbol: "gearshape.fill")
    }

    private var instrumentIconsRow: some View {
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
    }

    @ViewBuilder private var visualOrderRows: some View {
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
            if isList {
                // The draggable list opens on the right (issue #371).
                cardTopicRow(.songRowOrder)
            } else {
                // Shown directly under its switch, like the web's collapse (no disclosure).
                reorderBlock(SettingsTopic.songRowOrder.rowTitle, detail: SettingsTopic.songRowOrder.subtitle) {
                    songRowOrderList
                }
            }
        }
    }

    /// The Song Row Visual Order list, or a note while no metadata field is visible.
    @ViewBuilder private var songRowOrderList: some View {
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

    @ViewBuilder private var pathRows: some View {
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
    }

    @ViewBuilder private var invalidScoreRows: some View {
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
    }

    private var experimentalRanksRow: some View {
        Toggle(isOn: $experimentalRanks) {
            SettingLabel(
                "Experimental Ranks",
                detail: "More ranking mechanisms for Leaderboards. Not yet available."
            )
        }
        .disabled(true)
        .accessibilityHint("Experimental ranks are not yet available")
    }

    /// The Report an Issue and Request a Feature rows (issue #78).
    @ViewBuilder private var feedbackRows: some View {
        feedbackRow(
            .bug, detail: "Tell us about something that isn't working.",
            action: "Report", identifier: "fst.settings.feedback.bug"
        )
        feedbackRow(
            .feature, detail: "Suggest something new for Festival Score Tracker.",
            action: "Request", identifier: "fst.settings.feedback.feature"
        )
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

    /// Where system accessibility options live on this platform.
    private static var systemSettingsName: String {
        #if os(macOS)
        "System Settings"
        #else
        "device Settings"
        #endif
    }

    private var accessibility: some View {
        SettingsSectionCard(
            "Accessibility",
            subtitle: "Off follows your device; On adds an app override. "
                + "VoiceOver and text size are managed in \(Self.systemSettingsName).",
            titled: showsSectionTitles
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
        SettingsSectionCard(
            "Item Shop", subtitle: "Control how Item Shop availability is displayed.",
            titled: showsSectionTitles
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
        SettingsSectionCard(
            "Show Instruments",
            subtitle: "Choose which instruments to display throughout the app.",
            titled: showsSectionTitles
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
        SettingsSectionCard(
            "Show Instrument Metadata",
            subtitle: session.selectedPlayer == nil
                ? "Select a player to customize score metadata."
                : showInstrumentIcons
                    ? "With icons and All instruments, status chips replace score "
                        + "metadata. Turn icons off or filter one chart to show these fields."
                    : "Visible score fields update Songs cards. Enable Independent Song Row "
                        + "Visual Order above to choose which field leads; Last Played sort is "
                        + "still being ported.",
            titled: showsSectionTitles
        ) {
            ForEach(MetadataField.allCases) { field in
                Toggle(isOn: metadataBinding(for: field)) { SettingLabel(field.label) }
                    .disabled(session.selectedPlayer == nil && field != .intensity)
                    .accessibilityHint(metadataHint(for: field))
                    .accessibilityIdentifier("fst.settings.metadata.\(field.rawValue)")
            }
        }
    }

    private var version: some View {
        SettingsSectionCard(
            "Festival Score Tracker Version",
            subtitle: "Festival Score Tracker information to help with debugging.",
            titled: showsSectionTitles
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
        // Licenses opens in the trailing pane where Settings can split (iPad, Duo).
        chevronRow(
            "Licenses", subtitle: "Open source package license details.", route: .licenses,
            label: "View Licenses", identifier: "fst.settings.licenses"
        )
    }

    /// A list/detail topic's standalone chevron row, styled like the Licenses link
    /// (issue #371).
    ///
    /// - Parameter topic: The topic it opens on the right.
    private func topicRow(_ topic: SettingsTopic) -> some View {
        chevronRow(
            topic.rowTitle, subtitle: topic.subtitle, route: .settingsTopic(topic),
            label: topic.rowTitle, identifier: topic.accessibilityIdentifier
        )
    }

    /// A standalone link row: the section title and description with a trailing chevron,
    /// the whole row tappable, no card. It opens on the right where Settings splits and is
    /// pushed everywhere else (``ListDetailLink``), highlighted while open.
    ///
    /// - Parameters:
    ///   - title: Title Case section title.
    ///   - subtitle: Sentence-case description, also the accessibility hint.
    ///   - route: The page it opens.
    ///   - label: Accessibility label.
    ///   - identifier: Accessibility identifier.
    private func chevronRow(
        _ title: String, subtitle: String, route: AppRoute, label: String, identifier: String
    ) -> some View {
        ListDetailLink(value: route) {
            HStack(alignment: .center, spacing: 16) {
                FestivalSectionHeader(title, subtitle: subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SettingsChevron()
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // No `.accessibilityElement(children: .combine)` around the link (the button
        // already reads as one element): while the Licenses split was open it merged the
        // button with the selection fill and accent bar into a selected *static text*
        // and left the inner button exposed as well (landscape Settings split audit:
        // "Potentially inaccessible element/text", Lane A11Y3/A11Y4). Rivals' split
        // rows label the link the same way.
        .accessibilityLabel(label)
        .accessibilityHint(subtitle)
        .accessibilityIdentifier(identifier)
    }

    /// A list/detail topic's row inside the App Settings card, beside the toggles it
    /// belongs to (issue #371): the setting's label and description with a chevron.
    ///
    /// - Parameter topic: The topic it opens on the right.
    private func cardTopicRow(_ topic: SettingsTopic) -> some View {
        ListDetailLink(value: .settingsTopic(topic)) {
            HStack(spacing: 8) {
                SettingLabel(topic.rowTitle, detail: topic.subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SettingsChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(topic.rowTitle)
        .accessibilityHint(topic.subtitle)
        .accessibilityIdentifier(topic.accessibilityIdentifier)
    }

    /// Settings › Privacy Policy (issue #98): styled like the Licenses link, but it opens
    /// the policy as a modal sheet instead of pushing a page (App Review 5.1.1(i) asks for
    /// an easily accessible in-app policy; HIG Sheets: a scoped, self-contained view).
    private var privacyPolicyRow: some View {
        Button {
            showingPrivacyPolicy = true
        } label: {
            HStack(alignment: .center, spacing: 16) {
                FestivalSectionHeader(
                    "Privacy Policy",
                    subtitle: "How Festival Score Tracker handles your information."
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsChevron()
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy Policy")
        .accessibilityHint("How Festival Score Tracker handles your information")
        .accessibilityIdentifier("fst.settings.privacy-policy")
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
            // The brand red (≈ 5.6:1 behind white); the dark system red measured ≈ 3.4:1.
            .tint(BrandTokens.statusRed)
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
        guard topic == nil, !feedbackEnabled else { return }
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

// MARK: - Title and root items

/// The page's navigation title: a topic page is a pushed route, so it publishes its title
/// like every route (``SwiftUI/View/festivalNavigationTitle(_:)``); the root and the Mac
/// panes keep the plain title.
private struct SettingsPageTitle: ViewModifier {
    let title: String
    let isRoute: Bool

    func body(content: Content) -> some View {
        if isRoute {
            content.festivalNavigationTitle(title)
        } else {
            content.navigationTitle(title)
        }
    }
}

/// Tags the root page (and the Mac panes) as ending its toolbar with the root trailing
/// items; a topic page is a pushed route, which gets the stack's own items.
private struct SettingsProvidesRootTrailingItems: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.festivalProvidesRootTrailingItems()
        } else {
            content
        }
    }
}

// MARK: - Quick links

/// The page's Quick Links container, only for the whole page: a Mac Settings pane is
/// short and titled by its toolbar button, so it has no Quick Links menu.
private struct SettingsQuickLinks: ViewModifier {
    let controller: QuickLinksController
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.quickLinks(controller, title: "Quick Links")
        } else {
            content
        }
    }
}

// MARK: - Readable width

/// Caps a page's content to readable columns and centers it on a regular-width window
/// (Duo unfolded, iPad, Mac), instead of stretching every toggle row edge to edge:
/// one 680 pt column, or two side by side when Settings splits its sections in wide
/// landscape (pattern `wide-columns` R7, #355). A compact window (iPhone, Duo folded)
/// is unaffected: this only activates once a caller passes `isRegularWidth: true`.
struct ReadableWidthContainer: ViewModifier {
    let isRegularWidth: Bool
    /// Readable columns side by side (Settings in wide landscape), else 1.
    var columns: Int = 1
    /// Roughly a Dynamic Type–friendly settings form width, well under an iPad or
    /// unfolded Duo's full window.
    static let columnWidth: CGFloat = 680

    /// The cap for `columns` readable columns and the gutters between them.
    ///
    /// - Parameter columns: Columns side by side (at least 1).
    /// - Returns: The maximum content width in points.
    static func maxWidth(columns: Int) -> CGFloat {
        let count = CGFloat(max(1, columns))
        return columnWidth * count + WideColumns.spacing * (count - 1)
    }

    func body(content: Content) -> some View {
        if isRegularWidth || columns > 1 {
            content
                .frame(maxWidth: Self.maxWidth(columns: columns), alignment: .leading)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

// MARK: - Chevron

/// The trailing chevron of Settings' link rows (Licenses, Privacy Policy, list/detail
/// topics). HIG Lists and tables: "for drill-down, use a disclosure indicator".
private struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.body.weight(.semibold))
            .foregroundStyle(FestivalText.primary)
            .accessibilityHidden(true)
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
