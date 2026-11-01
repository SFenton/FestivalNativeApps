#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Settings page

/// The Settings page and its list/detail topic pages (``SettingsScreen``): the whole page in the
/// web's order on iPhone and in a narrow window, the list whose groups open on the right where
/// the window splits (iPad, unfolded iPhone Duo), or one topic's page (`topic`).
///
/// Every row writes the same `fst.*` key in the same representation as SwiftUI's `@AppStorage`
/// (``UKSettingsStore``), so the SwiftUI app's pages and the port's pages read the change alike.
/// The page builds once and follows `UserDefaults` and the selected player; only the cards that
/// depend on the layout (list vs. page) or on the player are rebuilt.
@MainActor
final class UKSettingsViewController: UKSettingsScrollPage, UKPageToolsProviding, UIScrollViewDelegate {
    private let topic: SettingsTopic?
    private lazy var background = UKBackgroundRegistration(session: context.session, mode: .carousel)
    private var isList = false
    private var didBuild = false
    private var didFade = false
    private var cardsByID: [String: UIView] = [:]
    private var linkRows: [AppRoute: UKSettingsLinkRow] = [:]
    private var quickLinks: UKQuickLinks?
    private let quickLinksController = QuickLinksController()
    private var toggles: [() -> Void] = []
    private var refreshers: [() -> Void] = []
    private var serviceInfo: UKSettingsServiceInfoSection?
    private var serviceVersion: String?
    private var serviceVersionFailed = false
    private var versionRow: UKSettingsValueRow?
    private var versionTask: Task<Void, Never>?
    private let observations = UKObservationBag()
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?
    private var lastVisualOrder: Bool?
    private var lastIcons: Bool?
    private var lastHasPlayer: Bool?

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - context: The page's context.
    ///   - topic: A list/detail topic to show alone, or nil for the whole page.
    init(context: UKContext, topic: SettingsTopic? = nil) {
        self.topic = topic
        super.init(context: context)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    /// Whether this is the root page (the whole page or the list), with Quick Links.
    private var isRootPage: Bool { topic == nil }
    private var hasPlayer: Bool { context.session.selectedPlayer != nil }
    private var showsTitles: Bool { topic == nil }

    // MARK: Page tools

    var ukPageTools: [UKPageTool] { quickLinks?.tool.map { [$0] } ?? [] }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        ukSetPageTitle(topic?.pageTitle ?? "Settings")
        scrollView.delegate = self
        if isRootPage {
            let quick = UKQuickLinks(controller: quickLinksController, title: "Quick Links", sections: quickLinkSections())
            quick.attach(
                to: scrollView, rect: { [weak self] id in self?.frame(ofCard: id) },
                element: { [weak self] id in self?.element(ofCard: id) }
            )
            quick.onToolChange = { [weak self] in self?.ukPageToolsDidChange() }
            quickLinks = quick
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UKSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.settingsChanged() } }
        observations.observe { [weak self] in
            guard let self else { return }
            let player = context.session.selectedPlayer?.accountId
            _ = player
            playerChanged()
        }
        observations.observe { [weak self] in
            _ = self?.context.shell?.splitOpen
            self?.updateOpenDetail()
        }
        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        background.registers = ukSplitPane != .trailing
        background.viewWillAppear()
        if topic != nil { ukInstallAccountItems() }
        serviceInfo?.startPolling()
        loadServiceVersionIfNeeded()
        if !didFade {
            didFade = true
            for (index, card) in column.arrangedSubviews.enumerated() {
                UKFadeIn.fadeIn(card, staggerIndex: index)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        quickLinks?.didAppear()
        updateOpenDetail()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        quickLinks?.willDisappear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        background.viewDidDisappear()
        serviceInfo?.stopPolling()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let list = isRootPage && ukSectionStack?.geometry != nil
        if didBuild, list != isList { rebuild() }
        quickLinks?.scrollViewDidScroll()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { quickLinks?.scrollViewDidScroll() }

    // MARK: Building

    private func rebuild() {
        isList = isRootPage && ukSectionStack?.geometry != nil
        didBuild = true
        toggles = []
        refreshers = []
        cardsByID = [:]
        linkRows = [:]
        serviceInfo?.stopPolling()
        serviceInfo = nil
        versionRow = nil
        var cards: [UIView] = []
        func add(_ id: String, _ view: UIView) {
            cardsByID[id] = view
            cards.append(view)
        }
        if let topic {
            add(topic.rawValue, topicContent(topic))
        } else if isList {
            add("app-settings", appSettings())
            add("accessibility", topicRow(.accessibility))
            add("item-shop", topicRow(.itemShop))
            add("show-instruments", topicRow(.instruments))
            add("show-metadata", topicRow(.metadata))
            add("version", topicRow(.version))
            add("service-info", topicRow(.serviceInfo))
            if SettingsFixtureTools.isEnabled() { add("fixture", UKSettingsFixtureTools(session: context.session)) }
            add("first-run", topicRow(.firstRun))
            add("licenses", licensesRow())
            add("privacy-policy", topicRow(.privacyPolicy))
            add("reset", resetBlock())
        } else {
            add("app-settings", appSettings())
            add("accessibility", accessibilityCard(titled: true))
            add("item-shop", itemShopCard(titled: true))
            add("show-instruments", instrumentsCard(titled: true))
            add("show-metadata", metadataCard(titled: true))
            add("version", versionCard(titled: true))
            add("service-info", serviceInfoCard(titled: true))
            if SettingsFixtureTools.isEnabled() { add("fixture", UKSettingsFixtureTools(session: context.session)) }
            add("first-run", UKFirstRunSettingsSection(session: context.session, titled: true))
            add("licenses", licensesRow())
            add("privacy-policy", privacyRow())
            add("reset", resetBlock())
        }
        setCards(cards)
        if didFade {
            // A relayout rebuild shows its cards at once.
            cards.forEach { $0.alpha = 1 }
        }
        lastVisualOrder = UKSettings.bool("fst.settings.enableVisualOrder", default: false)
        lastIcons = UKSettings.bool("fst.settings.showInstrumentIcons", default: true)
        lastHasPlayer = hasPlayer
        syncAll()
        if isViewLoaded, view.window != nil {
            serviceInfo?.startPolling()
            loadServiceVersionIfNeeded()
        }
        updateOpenDetail()
    }

    private func quickLinkSections() -> [QuickLinkSection] {
        let items: [(String, String, String)] = [
            ("app-settings", "App Settings", "gearshape.fill"),
            ("accessibility", "Accessibility", "accessibility"),
            ("item-shop", "Item Shop", "bag.fill"),
            ("show-instruments", "Show Instruments", "music.note"),
            ("show-metadata", "Show Instrument Metadata", "list.bullet"),
            ("version", "Festival Score Tracker Version", "info.circle"),
            ("service-info", ServiceInfoText.title, "server.rack"),
            ("first-run", "First Run Guides", "sparkles"),
            ("licenses", "Licenses", "doc.text"),
            ("privacy-policy", "Privacy Policy", "hand.raised"),
            ("reset", "Reset Settings", "trash"),
        ]
        return items.map { QuickLinkSection(id: $0.0, title: $0.1, icon: .system($0.2)) }
    }

    private func frame(ofCard id: String) -> CGRect? {
        guard let card = cardsByID[id], card.superview != nil, card.window != nil else { return nil }
        return card.convert(card.bounds, to: scrollView)
    }

    private func element(ofCard id: String) -> NSObject? {
        guard let card = cardsByID[id] else { return nil }
        var queue: [UIView] = [card]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.isAccessibilityElement { return view }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    // MARK: Following settings

    private func settingsChanged() {
        guard didBuild else { return }
        let order = UKSettings.bool("fst.settings.enableVisualOrder", default: false)
        let icons = UKSettings.bool("fst.settings.showInstrumentIcons", default: true)
        syncAll()
        if icons != lastIcons {
            lastIcons = icons
            replaceMetadataCard()
        }
        if order != lastVisualOrder {
            lastVisualOrder = order
            closeUnlistedTopic(independentVisualOrder: order)
        }
    }

    private func playerChanged() {
        guard didBuild else { return }
        let has = hasPlayer
        guard has != lastHasPlayer else { return }
        lastHasPlayer = has
        replaceMetadataCard()
    }

    private func syncAll() {
        toggles.forEach { $0() }
        refreshers.forEach { $0() }
    }

    /// Rebuilds the Show Instrument Metadata card in place: its description and each
    /// switch's state follow the selected player and Show Instrument Icons.
    private func replaceMetadataCard() {
        let id = topic == .metadata ? SettingsTopic.metadata.rawValue : "show-metadata"
        guard let old = cardsByID[id], let index = column.arrangedSubviews.firstIndex(of: old) else { return }
        let new = metadataCard(titled: showsTitles)
        column.removeArrangedSubview(old)
        old.removeFromSuperview()
        column.insertArrangedSubview(new, at: index)
        cardsByID[id] = new
        syncAll()
    }

    /// Return the right-hand pane to its placeholder when the open topic's row just left the
    /// list (pattern `split-panes` R6).
    private func closeUnlistedTopic(independentVisualOrder: Bool) {
        guard isList, case .settingsTopic(let open)? = ukOpenDetail,
              !open.isListed(independentVisualOrder: independentVisualOrder) else { return }
        context.navigator?.closeDetail()
    }

    private func updateOpenDetail() {
        guard isList else {
            linkRows.values.forEach { $0.isOpen = false }
            return
        }
        let open = ukOpenDetail
        for (route, row) in linkRows { row.isOpen = route == open }
    }

    // MARK: Cards

    private func toggle(
        _ title: String, detail: String? = nil, key: String, default fallback: Bool, inverted: Bool = false,
        label: String? = nil, hint: String? = nil, identifier: String, leading: UIView? = nil,
        onChange: ((Bool) -> Void)? = nil
    ) -> UKSettingsToggleRow {
        let row = UKSettingsToggleRow(
            title: title, detail: detail, key: key, default: fallback, inverted: inverted,
            accessibilityLabel: label, hint: hint, identifier: identifier, leading: leading
        )
        row.onChange = onChange
        toggles.append { [weak row] in row?.sync() }
        return row
    }

    private func appSettings() -> UIView {
        let section = UKSettingsSection("App Settings", subtitle: "General Festival Score Tracker app settings.")
        var rows: [UIView] = []
        rows.append(toggle(
            "Show Instrument Icons",
            detail: "Display instrument icons on each song row showing which parts have leaderboard scores or FCs.",
            key: "fst.settings.showInstrumentIcons", default: true,
            hint: "Shows score and full combo status for each enabled chart on unfiltered Songs cards when a player is selected",
            identifier: "fst.settings.show-instrument-icons"
        ))
        rows.append(toggle(
            "Enable Independent Song Row Visual Order",
            detail: "When enabled, the metadata display order on song rows is controlled separately from sort priority. "
                + "When disabled, metadata follows sort priority order.",
            key: "fst.settings.enableVisualOrder", default: false, identifier: "fst.settings.enable-visual-order"
        ))
        let order = UKSettingsAccordionRow(isOpen: UKSettings.bool("fst.settings.enableVisualOrder", default: false)) { [unowned self] in
            if isList {
                return cardTopicRow(.songRowOrder)
            }
            return reorderBlock(SettingsTopic.songRowOrder.rowTitle, detail: SettingsTopic.songRowOrder.subtitle) { songRowOrderList() }
        }
        refreshers.append { [weak order] in order?.follow(UKSettings.bool("fst.settings.enableVisualOrder", default: false)) }
        rows.append(order)
        if isList {
            rows.append(cardTopicRow(.paths))
        } else {
            rows.append(contentsOf: pathRows())
        }
        rows.append(contentsOf: invalidScoreRows())
        rows.append(toggle(
            "Enable Experimental Leaderboard Ranks",
            detail: "Enable this to see more ranking mechanisms in the Leaderboards page.",
            key: ExperimentalRanks.storageKey, default: ExperimentalRanks.defaultValue,
            hint: "Adds Adjusted, Weighted, FC Rate and Max Score to Rank By on Leaderboards, Rivals and Bands",
            identifier: "fst.settings.experimental-ranks"
        ))
        section.setRows(rows)
        return section
    }

    private func invalidScoreRows() -> [UIView] {
        let filter = toggle(
            "Filter Invalid Scores",
            detail: "When enabled, the app will attempt to filter out invalid leaderboard values based on the maximum "
                + "score derived from the CHOpt path.",
            key: "fst.settings.filterInvalidScores", default: false, identifier: "fst.settings.filter-invalid-scores"
        )
        var leeway: UKSettingsLeewayBlock?
        let accordion = UKSettingsAccordionRow(isOpen: UKSettings.bool("fst.settings.filterInvalidScores", default: false)) {
            let block = UKSettingsLeewayBlock()
            leeway = block
            return block
        }
        refreshers.append { [weak accordion] in
            accordion?.follow(UKSettings.bool("fst.settings.filterInvalidScores", default: false))
            leeway?.sync()
        }
        return [filter, accordion]
    }

    private func pathRows() -> [UIView] {
        let choice = UKSettingsChoiceRow<PathDisplayMode>(
            title: "CHOpt Path Default View",
            detail: "Choose whether CHOpt paths open as an image or text table by default.",
            key: "fst.settings.pathDefaultView", default: .image, label: \.label,
            identifier: "fst.settings.path-default-view"
        )
        refreshers.append { [weak choice] in choice?.sync() }
        let columns = reorderBlock(
            "CHOpt Text Path Column Order", detail: "Choose the order columns appear in the CHOpt text path view."
        ) { pathColumnList() }
        return [choice, columns]
    }

    /// An inline reorder list with its bold title and description.
    private func reorderBlock(_ title: String, detail: String, list: () -> UIView) -> UIView {
        let heading = UKLabel(title, style: .body, weight: .semibold).asHeader()
        let text = UKLabel(detail, style: .subheadline)
        let body = list()
        let stack = UIStackView(arrangedSubviews: [heading, text, body])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(12, after: text)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    // MARK: Reorder lists

    private func songRowOrderList() -> UIView {
        let host = UIView()
        host.translatesAutoresizingMaskIntoConstraints = false
        var signature: String?
        let refresh = { [weak self, weak host] in
            guard let self, let host else { return }
            let visible = visibleVisualOrder()
            let current = visible.map(\.rawValue).joined(separator: ",")
            guard current != signature else { return }
            signature = current
            host.subviews.forEach { $0.removeFromSuperview() }
            let content: UIView
            if visible.isEmpty {
                content = UKLabel("No metadata fields are currently visible.", style: .subheadline)
            } else {
                content = UKSettingsReorderList(
                    items: visible, identifier: "fst.settings.song-row-order", label: { $0.reorderLabel }, key: { $0.rawValue }
                ) { reordered in
                    let full = MetadataField.savedSongRowOrder(UKSettingsStore.string(
                        "fst.settings.songRowVisualOrder", default: SettingsOrder.encode(MetadataField.defaultSongRowOrder)
                    ))
                    UKSettingsStore.set(
                        SettingsOrder.encode(SettingsReorder.merging(visible: reordered, into: full)),
                        forKey: "fst.settings.songRowVisualOrder"
                    )
                }
            }
            ukPin(content, in: host)
        }
        refreshers.append(refresh)
        refresh()
        return host
    }

    private func pathColumnList() -> UIView {
        let host = UIView()
        host.translatesAutoresizingMaskIntoConstraints = false
        var signature: String?
        let refresh = { [weak host] in
            guard let host else { return }
            let raw = UKSettingsStore.string("fst.settings.pathColumnOrder", default: SettingsOrder.encode(PathColumnKey.allCases))
            let order: [PathColumnKey] = SettingsOrder.decode(raw)
            let current = order.map(\.rawValue).joined(separator: ",")
            guard current != signature else { return }
            signature = current
            host.subviews.forEach { $0.removeFromSuperview() }
            let list = UKSettingsReorderList(
                items: order, identifier: "fst.settings.path-column-order", label: { $0.label }, key: { $0.rawValue }
            ) { UKSettingsStore.set(SettingsOrder.encode($0), forKey: "fst.settings.pathColumnOrder") }
            ukPin(list, in: host)
        }
        refreshers.append(refresh)
        refresh()
        return host
    }

    /// The saved Song row order limited to currently visible metadata fields.
    private func visibleVisualOrder() -> [MetadataField] {
        MetadataField.savedSongRowOrder(UKSettingsStore.string(
            "fst.settings.songRowVisualOrder", default: SettingsOrder.encode(MetadataField.defaultSongRowOrder)
        )).filter { UKSettings.bool(Self.metadataKey($0), default: true) }
    }

    // MARK: Accessibility, shop, instruments, metadata

    private func accessibilityCard(titled: Bool) -> UIView {
        let section = UKSettingsSection(
            "Accessibility", subtitle: SettingsCopy.accessibilitySubtitle(systemSettingsName: SettingsCopy.deviceSettingsName),
            titled: titled
        )
        section.setRows([
            toggle("Reduce Motion", key: "fst.accessibility.reduceMotion", default: false, identifier: "fst.settings.reduce-motion"),
            toggle("Disable Animated Artwork", key: "fst.accessibility.disableAnimatedArtwork", default: false, identifier: "fst.settings.disable-artwork-animation"),
            toggle("Increase Contrast", key: "fst.accessibility.moreContrast", default: false, identifier: "fst.settings.more-contrast"),
            toggle(
                "Reduce Transparency", detail: "Replaces glass with solid surfaces.", key: "fst.accessibility.lessTransparency",
                default: false, identifier: "fst.settings.less-transparency"
            ),
        ])
        return section
    }

    private func itemShopCard(titled: Bool) -> UIView {
        let section = UKSettingsSection(
            "Item Shop", subtitle: "Control how Item Shop availability is displayed.", titled: titled
        )
        let highlights = toggle(
            "Highlight Shop Items", key: "fst.settings.disableShopHighlighting", default: false, inverted: true,
            identifier: "fst.settings.shop-highlights"
        )
        let hide = toggle(
            "Hide Item Shop", detail: "Also hides its menu entry. Your highlight preference is retained.",
            key: "fst.settings.hideShop", default: false, identifier: "fst.settings.hide-shop"
        )
        refreshers.append { [weak highlights] in
            highlights?.isRowEnabled = !UKSettings.bool("fst.settings.hideShop", default: false)
        }
        section.setRows([hide, highlights])
        return section
    }

    private static let instrumentKeys: [Instrument: String] = [
        .lead: "fst.settings.showLead", .bass: "fst.settings.showBass", .drums: "fst.settings.showDrums",
        .vocals: "fst.settings.showVocals", .proLead: "fst.settings.showProLead", .proBass: "fst.settings.showProBass",
        .karaoke: "fst.settings.showKaraoke", .proCymbals: "fst.settings.showProCymbals", .proDrums: "fst.settings.showProDrums",
    ]

    private func instrumentsCard(titled: Bool) -> UIView {
        let section = UKSettingsSection(
            "Show Instruments", subtitle: "Choose which instruments to display throughout the app.", titled: titled
        )
        var rows: [UKSettingsToggleRow] = []
        for instrument in Instrument.allCases {
            let key = Self.instrumentKeys[instrument] ?? "fst.settings.show\(instrument.rawValue)"
            let icon = UKInstrumentIconView(instrument, size: 28, hidesFromAccessibility: true)
            let row = toggle(
                instrument.label, key: key, default: true, label: instrument.label,
                identifier: "fst.settings.instrument.\(instrument.rawValue)", leading: icon
            )
            rows.append(row)
        }
        refreshers.append { [rows] in
            let count = Instrument.allCases.filter { UKSettings.bool(Self.instrumentKeys[$0] ?? "", default: true) }.count
            for (instrument, row) in zip(Instrument.allCases, rows) {
                let shown = UKSettings.bool(Self.instrumentKeys[instrument] ?? "", default: true)
                row.isRowEnabled = !SettingsCopy.instrumentSwitchDisabled(isShown: shown, visibleCount: count)
            }
        }
        section.setRows(rows)
        return section
    }

    private static func metadataKey(_ field: MetadataField) -> String {
        "fst.settings.metadata" + field.rawValue.prefix(1).uppercased() + field.rawValue.dropFirst()
    }

    private func metadataCard(titled: Bool) -> UIView {
        let player = hasPlayer
        let section = UKSettingsSection(
            "Show Instrument Metadata",
            subtitle: SettingsCopy.metadataSubtitle(
                hasPlayer: player, showInstrumentIcons: UKSettings.bool("fst.settings.showInstrumentIcons", default: true)
            ),
            titled: titled
        )
        var rows: [UIView] = []
        for field in MetadataField.allCases {
            let row = toggle(
                field.label, key: Self.metadataKey(field), default: true,
                hint: SettingsCopy.metadataHint(for: field, hasPlayer: player),
                identifier: "fst.settings.metadata.\(field.rawValue)"
            )
            row.isRowEnabled = !SettingsCopy.metadataSwitchDisabled(field, hasPlayer: player)
            rows.append(row)
        }
        section.setRows(rows)
        return section
    }

    // MARK: Version

    private func versionCard(titled: Bool) -> UIView {
        let section = UKSettingsSection(
            "Festival Score Tracker Version",
            subtitle: "Festival Score Tracker information to help with debugging.", titled: titled
        )
        let info = Bundle.main.infoDictionary
        let app = UKSettingsValueRow(
            "App Version", value: AppBuildInfo.versionText(info), spokenValue: AppBuildInfo.spokenVersionText(info),
            identifier: "fst.settings.app-version"
        )
        let build = UKSettingsValueRow(
            "Build Configuration", value: SettingsCopy.buildConfigurationText, identifier: "fst.settings.build"
        )
        let service = UKSettingsValueRow(
            "Service Version", value: SettingsCopy.serviceVersionText(version: serviceVersion, failed: serviceVersionFailed),
            identifier: "fst.settings.service-version"
        )
        versionRow = service
        let whatsNew = UKSettingsShowRow(
            title: "What's New", detail: "Recent changes to Festival Score Tracker.", action: "Show",
            hint: "Shows the latest changelog", identifier: "fst.settings.whats-new"
        ) { [weak self] in
            guard let self else { return }
            UKWhatsNew.present(session: context.session, from: self)
        }
        section.setRows([app, build, service, whatsNew])
        return section
    }

    private func loadServiceVersionIfNeeded() {
        guard versionRow != nil, serviceVersion == nil, versionTask == nil else { return }
        let session = context.session
        versionTask = Task { [weak self] in
            do {
                let value = try await session.client().serviceVersion()
                self?.serviceVersion = value
                self?.serviceVersionFailed = false
            } catch {
                if error is CancellationError { self?.versionTask = nil; return }
                if let urlError = error as? URLError, urlError.code == .cancelled { self?.versionTask = nil; return }
                self?.serviceVersionFailed = true
            }
            self?.versionRow?.setValue(
                SettingsCopy.serviceVersionText(version: self?.serviceVersion, failed: self?.serviceVersionFailed ?? false)
            )
            self?.versionTask = nil
        }
    }

    private func serviceInfoCard(titled: Bool) -> UIView {
        let section = UKSettingsServiceInfoSection(session: context.session, titled: titled)
        serviceInfo = section
        return section
    }

    // MARK: Link rows

    private func licensesRow() -> UIView {
        let row = UKSettingsLinkRow(
            title: "Licenses", subtitle: "Open source package license details.", label: "View Licenses",
            identifier: "fst.settings.licenses"
        ) { [weak self] in self?.open(.licenses) }
        linkRows[.licenses] = row
        return row
    }

    private func privacyRow() -> UIView {
        UKSettingsLinkRow(
            title: "Privacy Policy", subtitle: "How Festival Score Tracker handles your information.",
            label: "Privacy Policy", identifier: "fst.settings.privacy-policy"
        ) { [weak self] in
            guard let self else { return }
            UKPrivacyPolicyViewController.present(from: self)
        }
    }

    private func topicRow(_ topic: SettingsTopic) -> UIView {
        let route = AppRoute.settingsTopic(topic)
        let row = UKSettingsLinkRow(
            title: topic.rowTitle, subtitle: topic.subtitle, label: topic.rowTitle, identifier: topic.accessibilityIdentifier
        ) { [weak self] in self?.open(route) }
        linkRows[route] = row
        return row
    }

    private func cardTopicRow(_ topic: SettingsTopic) -> UIView {
        let route = AppRoute.settingsTopic(topic)
        let row = UKSettingsLinkRow(
            title: topic.rowTitle, subtitle: topic.subtitle, label: topic.rowTitle, identifier: topic.accessibilityIdentifier,
            inCard: true
        ) { [weak self] in self?.open(route) }
        linkRows[route] = row
        return row
    }

    private func open(_ route: AppRoute) {
        context.navigator?.selectDetail(route)
        DispatchQueue.main.async { [weak self] in self?.updateOpenDetail() }
    }

    // MARK: Topics

    private func topicContent(_ topic: SettingsTopic) -> UIView {
        switch topic {
        case .songRowOrder:
            let section = UKSettingsSection(topic.rowTitle, subtitle: topic.subtitle, titled: false)
            let host = UIView()
            host.translatesAutoresizingMaskIntoConstraints = false
            var built: Bool?
            let refresh = { [weak self, weak host] in
                guard let self, let host else { return }
                let enabled = UKSettings.bool("fst.settings.enableVisualOrder", default: false)
                guard enabled != built else { return }
                built = enabled
                host.subviews.forEach { $0.removeFromSuperview() }
                if enabled {
                    ukPin(songRowOrderList(), in: host)
                } else {
                    let note = UKLabel(
                        "Turn on Enable Independent Song Row Visual Order to choose this order.", style: .subheadline
                    )
                    note.accessibilityIdentifier = "fst.settings.song-row-order.off"
                    ukPin(note, in: host)
                }
            }
            refreshers.append(refresh)
            refresh()
            section.setRows([host])
            return section
        case .paths:
            let section = UKSettingsSection(topic.rowTitle, subtitle: topic.subtitle, titled: false)
            section.setRows(pathRows())
            return section
        case .accessibility: return accessibilityCard(titled: false)
        case .itemShop: return itemShopCard(titled: false)
        case .instruments: return instrumentsCard(titled: false)
        case .metadata: return metadataCard(titled: false)
        case .version: return versionCard(titled: false)
        case .serviceInfo: return serviceInfoCard(titled: false)
        case .firstRun: return UKFirstRunSettingsSection(session: context.session, titled: false)
        case .privacyPolicy:
            let content = UKPrivacyPolicyContent.make()
            let holder = UIView()
            content.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 4),
                content.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -4),
                content.topAnchor.constraint(equalTo: holder.topAnchor), content.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            ])
            return holder
        }
    }

    // MARK: Reset

    private func resetBlock() -> UIView {
        let header = UKSectionHeaderView("Reset Settings", subtitle: "Restore all settings to their default values.")
        let holder = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(header)
        var button: UIButton!
        button = UKSettingsButtons.prominent(
            "Reset App Settings", font: UKFont.font(.headline), fill: BrandUIColors.statusRed, identifier: "fst.settings.reset"
        ) { [weak self] in self?.confirmReset(from: button) }
        button.accessibilityLabel = "Reset App Settings"
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 4),
            header.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -4),
            header.topAnchor.constraint(equalTo: holder.topAnchor),
        ])
        let stack = UIStackView(arrangedSubviews: [holder, button])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.bottomAnchor.constraint(equalTo: holder.bottomAnchor).isActive = true
        return stack
    }

    private func confirmReset(from source: UIView) {
        let alert = UIAlertController(
            title: "Reset Settings",
            message: "Are you sure you want to restore all settings to their default values? "
                + "Your profile, song filters and navigation history will remain.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Reset App Settings", style: .destructive) { [weak self] _ in self?.resetAppSettings() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = source
        alert.popoverPresentationController?.sourceRect = source.bounds
        present(alert, animated: true)
    }

    /// Restore app settings only, never a selected profile or Songs navigation.
    func resetAppSettings() {
        SettingsRegistry.resetAll()
        syncAll()
    }
}

/// Pins `content` to all four edges of `host`.
@MainActor
private func ukPin(_ content: UIView, in host: UIView) {
    content.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: host.leadingAnchor), content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        content.topAnchor.constraint(equalTo: host.topAnchor), content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
    ])
}
#endif
