#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Player profile

/// `/player/:accountId` and the Statistics hub: a player's profile, ported from
/// ``PlayerProfileContent`` and ``StatisticsScreen`` (the web renders both from `PlayerPage`).
///
/// Reads only pure, keyless GETs through ``PlayerProfileLoader``: the compact scores, then in
/// parallel each played visible instrument's rankings-board row and 30-day rank history. Never
/// the player-stats GET. Nothing but a spinner shows until those reads settle; then the page
/// fades in and its cards stagger, so ranks and charts never pop into a half-drawn page.
///
/// The Statistics hub is this same page pointed at the selected player (``statistics``): it
/// restarts when the selection changes, shows "No Profile Selected" without one, and carries
/// the shell's root chrome (bell and avatar) wherever it is shown.
///
/// The dual-source graphs carousel (iPhone Duo inner display, portrait) is shelved
/// (``DualSourcePolicy/isEnabled`` is false), so the graphs stay inline.
@MainActor
class UKPlayerProfileViewController: UKProfileScrollViewController {
    // MARK: Types

    private struct LoadKey: Hashable {
        let accountId: String
        let retry: Int
        let publicationRevision: Int
    }

    private struct InstrumentViews {
        var container: UIView
        var stats: UKInstrumentStatsCardView?
        var percentiles: UKPlayerPercentileTableCardView?
        var history: UKPlayerRankHistoryCardView?
    }

    /// What the page's content depends on besides the profile read.
    private struct Signature: Equatable {
        var instruments: [Instrument]
        var filterInvalid: Bool
        var leeway: Double
    }

    // MARK: Inputs

    private let fixedAccountId: String?
    private let routeDisplayName: String?
    /// The Statistics hub: always the selected player, with the shell's root chrome.
    private let statistics: Bool

    // MARK: State

    private var phase = PlayerProfilePhase.loading
    private var retryRevision = 0
    private var loadedKey: LoadKey?
    private var loadTask: Task<Void, Never>?
    private var rankPreloads: [Instrument: InstrumentStatsCard.Phase] = [:]
    private var historyPreloads: [Instrument: PlayerRankHistoryCard.Phase] = [:]
    private var songsById: [String: Song] = [:]
    private var actionError: String?
    private var pendingLink: PlayerStatLink?
    private var identityBarItem: UIBarButtonItem?
    private var overviewGrid: UKStatGridView?
    private var instrumentViews: [Instrument: InstrumentViews] = [:]
    private var bandsSection: UIView?
    private var renderedSignature: Signature?
    private var renderedNoticePresence = false
    private var renderedAccountId: String?
    private var settingsTask: Task<Void, Never>?
    private var installedAccountChrome = false

    // MARK: Init

    /// Creates the pushed profile page.
    ///
    /// - Parameters:
    ///   - context: The screen's context.
    ///   - accountId: Public Epic account ID of the viewed player.
    ///   - displayName: Display name known from the originating link, if any.
    convenience init(context: UKContext, accountId: String, displayName: String?) {
        self.init(context: context, accountId: accountId, displayName: displayName, statistics: false)
    }

    init(context: UKContext, accountId: String?, displayName: String?, statistics: Bool) {
        fixedAccountId = accountId
        routeDisplayName = displayName
        self.statistics = statistics
        super.init(context: context)
    }

    deinit {
        loadTask?.cancel()
        settingsTask?.cancel()
    }

    // MARK: Derived state

    /// The account shown: the route's, or the selected player's on Statistics.
    private var accountId: String? {
        statistics ? session.selectedPlayer?.accountId : fixedAccountId
    }

    private var isSelected: Bool { accountId != nil && session.selectedPlayer?.accountId == accountId }

    private var shownPhase: PlayerProfilePhase {
        guard let accountId else { return .loading }
        return phase.shown(for: accountId)
    }

    private var displayName: String {
        if case let .available(payload) = shownPhase, let name = payload.profile.displayName { return name }
        if statistics { return session.selectedPlayer?.displayName ?? accountId ?? "Statistics" }
        return routeDisplayName ?? accountId ?? "Player"
    }

    private var loadKey: LoadKey? {
        accountId.map { LoadKey(accountId: $0, retry: retryRevision, publicationRevision: session.publicationRevision) }
    }

    private static let instrumentToggles: [(Instrument, String)] = [
        (.lead, "fst.settings.showLead"), (.bass, "fst.settings.showBass"), (.drums, "fst.settings.showDrums"),
        (.vocals, "fst.settings.showVocals"), (.proLead, "fst.settings.showProLead"), (.proBass, "fst.settings.showProBass"),
        (.karaoke, "fst.settings.showKaraoke"), (.proCymbals, "fst.settings.showProCymbals"), (.proDrums, "fst.settings.showProDrums"),
    ]

    /// Settings-visible solo charts, in the Songs tab's order.
    private var visibleInstruments: [Instrument] {
        Self.instrumentToggles.compactMap { UKProfileSettings.bool($0.1, default: true) ? $0.0 : nil }
    }

    private var signature: Signature {
        let leeway = UserDefaults.standard.object(forKey: "fst.settings.leeway") as? Double ?? 1.0
        return Signature(
            instruments: visibleInstruments,
            filterInvalid: UKProfileSettings.bool("fst.settings.filterInvalidScores", default: false), leeway: leeway
        )
    }

    /// The Settings leeway rounded to 0.1 while Filter Invalid Scores is on, else nil.
    private var invalidScoreLeeway: Double? {
        let value = signature
        return value.filterInvalid ? (value.leeway * 10).rounded() / 10 : nil
    }

    private func effective(_ payload: PlayerProfilePayload) -> PlayerProfilePayload {
        payload.filteringInvalidScores(songsById: songsById, leeway: invalidScoreLeeway)
    }

    private var identity: ProfileIdentityAction? {
        guard case let .available(payload) = shownPhase else { return nil }
        return PlayerProfileTiles.identity(
            isSelected: isSelected, payloadPublicationId: payload.publicationId,
            sessionPublicationId: session.publicationId, hasSelectedPlayer: session.selectedPlayer != nil
        )
    }

    private var plannedIdentity: ProfileIdentityAction {
        PlayerProfileTiles.plannedIdentity(isSelected: isSelected, hasSelectedPlayer: session.selectedPlayer != nil)
    }

    private var hasNavigator: Bool { context.navigator != nil }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        installQuickLinks()
        render()
        observations.observe { [weak self] in self?.sessionChanged() }
        settingsTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UKSettings.didChange) {
                self?.settingsChanged()
            }
        }
        loadIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if statistics, ukRoute != nil, !installedAccountChrome {
            installedAccountChrome = true
            ukInstallAccountItems()
        }
        // Back from a pushed page keeps the shown ranks: the key is unchanged, so nothing reloads.
        loadIfNeeded()
    }

    override var isSectionRoot: Bool { statistics }

    override var pageBarItems: [UIBarButtonItem] { identityBarItem.map { [$0] } ?? [] }

    // MARK: Observation

    /// Follows the session: a new selected player (Statistics), a new publication, or a change
    /// to which links and actions the page offers.
    private func sessionChanged() {
        let id = accountId
        let revision = session.publicationRevision
        _ = session.selectedPlayer
        _ = session.publicationId
        guard isViewLoaded else { return }
        if statistics, id != renderedAccountId {
            // This tab root survives a profile switch: key its per-account state by the account.
            resetForAccountChange()
            return
        }
        if let key = loadKey, key.publicationRevision != revision || loadedKey != key, loadedKey != nil || loadTask == nil {
            loadIfNeeded()
            return
        }
        refreshLinks()
    }

    private func settingsChanged() {
        guard isViewLoaded, case .available = shownPhase, let rendered = renderedSignature, rendered != signature else { return }
        renderAvailable(fadeIn: false)
    }

    private func resetForAccountChange() {
        loadTask?.cancel()
        loadedKey = nil
        phase = .loading
        actionError = nil
        rankPreloads = [:]
        historyPreloads = [:]
        render()
        loadIfNeeded()
    }

    // MARK: Load

    private func loadIfNeeded() {
        guard let key = loadKey, loadedKey != key else {
            if loadKey == nil { render() }
            return
        }
        if loadTask != nil, loadTaskKey == key { return }
        startLoad(key)
    }

    private var loadTaskKey: LoadKey?

    private func startLoad(_ key: LoadKey) {
        loadTask?.cancel()
        loadTaskKey = key
        renderedAccountId = key.accountId
        phase = .loading
        render()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.load(key)
            if !Task.isCancelled, self.loadFinished { self.loadedKey = key }
            if self.loadTaskKey == key { self.loadTaskKey = nil }
        }
    }

    private var loadFinished: Bool {
        switch phase {
        case .available, .syncing: true
        case .loading, .failed: false
        }
    }

    /// Read the public profile without selecting or persisting it, with the catalogue
    /// alongside, then every played visible instrument's ranking and rank history.
    private func load(_ key: LoadKey) async {
        do {
            let loaded = try await PlayerProfileLoader.load(
                session: session, accountId: key.accountId, instruments: visibleInstruments
            )
            guard !Task.isCancelled else { return }
            songsById = loaded.songsById
            guard let payload = loaded.payload else {
                phase = .syncing
                render()
                return
            }
            rankPreloads = loaded.extras.ranks
            historyPreloads = loaded.extras.histories
            phase = .available(payload)
            render(fadeIn: true)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(ServiceIssue(error))
            render()
        }
    }

    private func retry() {
        retryRevision += 1
        loadIfNeeded()
    }

    // MARK: Render

    private func render(fadeIn: Bool = false) {
        guard isViewLoaded else { return }
        updateTitle()
        scrollView.accessibilityIdentifier = nil
        guard accountId != nil else {
            showNoProfile()
            updateBar()
            return
        }
        switch shownPhase {
        case .loading:
            let loading = UKLoadingView(accessibilityLabel: "Loading Profile", placement: .fill)
            loading.hingeProvider = hingeProvider
            loading.accessibilityIdentifier = "fst.player.loading"
            showState(loading)
        case .syncing:
            let status = UKServiceStatusView(
                .other(message: "\(displayName)'s public scores are still syncing. Try again shortly."),
                title: "Scores Are Syncing"
            ) { [weak self] in self?.retry() }
            status.ukContain(identifier: "fst.player.syncing")
            showState(status)
        case let .failed(issue):
            let status = UKServiceStatusView(issue, title: "Profile Unavailable") { [weak self] in self?.retry() }
            status.ukContain(identifier: "fst.player.error")
            showState(status)
        case .available:
            renderAvailable(fadeIn: fadeIn)
        }
        updateBar()
    }

    private func updateTitle() {
        if statistics, accountId == nil {
            ukSetPageTitle("Statistics")
        } else {
            ukSetPageTitle(displayName, mode: .large)
        }
    }

    /// Statistics with nobody selected: the brief moment between a deselect and the tab bar
    /// hiding Statistics.
    private func showNoProfile() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Choose Profile"
        let colors = UKAccentText.prominentColors(increasedContrast: UKAccessibility.systemIncreasedContrast(traitCollection))
        configuration.baseBackgroundColor = colors.fill
        configuration.baseForegroundColor = colors.label
        configuration.cornerStyle = .capsule
        let choose = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.context.navigator?.presentProfile()
        })
        choose.accessibilityIdentifier = "fst.statistics.choose-profile"
        choose.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let empty = UKEmptyStateView(
            "No Profile Selected", systemImage: "chart.bar", subtitle: "Select a player to see their statistics.",
            identifier: "fst.statistics.empty", actions: [choose]
        )
        empty.hingeProvider = hingeProvider
        showState(empty)
    }

    // MARK: Available page

    private func renderAvailable(fadeIn: Bool) {
        guard let accountId, case let .available(raw) = shownPhase else { return }
        let offset = scrollView.contentOffset
        let payload = effective(raw)
        let notice = identityNotice(payload)
        renderedSignature = signature
        renderedNoticePresence = notice != nil || actionError != nil
        instrumentViews = [:]
        var sections: [UIView] = []
        var anchors: [(QuickLinkSection, UIView)] = []
        if renderedNoticePresence { sections.append(noticesCard(notice)) }
        let overview = overallSection(payload)
        sections.append(overview)
        anchors.append((QuickLinkSection(id: "global", title: "Global Statistics", icon: .system("chart.bar.fill")), overview))
        let header = UKSectionHeaderView(
            "Instrument Statistics",
            subtitle: "A quick look at \(displayName)'s overall Festival statistics per instrument."
        )
        sections.append(UKProfileInset(header, horizontal: UKProfileMetrics.headerInset))
        let instruments = visibleInstruments
        let tiles = instruments.map { instrumentSection(payload, instrument: $0, accountId: accountId) }
        if layout.widthClass == .regular {
            let grid = UKProfileColumnGrid(columns: .fixed(2), spacing: 20)
            grid.layoutProvider = { [weak self] in self?.layout ?? .standardPhone }
            grid.setCells(tiles)
            sections.append(grid)
        } else {
            sections.append(contentsOf: tiles)
        }
        for instrument in instruments {
            guard let views = instrumentViews[instrument] else { continue }
            anchors.append((
                QuickLinkSection(id: "instrument:\(instrument.rawValue)", title: instrument.label, icon: .instrument(instrument)),
                views.container
            ))
            if let history = views.history, history.showsChart {
                anchors.append((
                    QuickLinkSection(
                        id: "rank-history:\(instrument.rawValue)", title: "Rank History",
                        icon: .system("chart.line.uptrend.xyaxis"), depth: 1, spokenTitle: "\(instrument.label) Rank History"
                    ), history
                ))
            }
            if let percentiles = views.percentiles, !percentiles.isHidden {
                anchors.append((
                    QuickLinkSection(
                        id: "percentiles:\(instrument.rawValue)", title: "Percentiles", icon: .system("chart.bar.xaxis"),
                        depth: 1, spokenTitle: "\(instrument.label) Percentiles"
                    ), percentiles
                ))
            }
        }
        // Web `PlayerContent` appends the bands after the instrument sections: inline, not behind a link.
        let bands = UKPlayerBandsPreviewSectionView(
            session: session, accountId: accountId, displayName: displayName, routeDisplayName: routeDisplayName,
            layoutProvider: { [weak self] in self?.layout ?? .standardPhone },
            navigate: { [weak self] route in self?.context.navigator?.push(route) }
        )
        bandsSection = bands
        sections.append(bands)
        anchors.append((QuickLinkSection(id: "bands", title: "Bands", icon: .system("person.3.fill")), bands))
        setSections(sections, fadeIn: fadeIn)
        scrollView.accessibilityIdentifier = "fst.player.available"
        setQuickLinks(anchors)
        for views in instrumentViews.values {
            views.history?.onChange = { [weak self] in self?.recollectQuickLinks() }
        }
        if !fadeIn { scrollView.contentOffset = offset }
    }

    /// The history cards show or hide as their reads settle: re-collect the Quick Links.
    private func recollectQuickLinks() {
        var anchors = quickLinkViews.filter { !$0.section.id.hasPrefix("rank-history:") }.map { ($0.section, $0.view) }
        for instrument in visibleInstruments {
            guard let history = instrumentViews[instrument]?.history, history.showsChart,
                  let index = anchors.firstIndex(where: { $0.0.id == "instrument:\(instrument.rawValue)" }) else { continue }
            anchors.insert((
                QuickLinkSection(
                    id: "rank-history:\(instrument.rawValue)", title: "Rank History",
                    icon: .system("chart.line.uptrend.xyaxis"), depth: 1, spokenTitle: "\(instrument.label) Rank History"
                ), history
            ), at: index + 1)
        }
        setQuickLinks(anchors)
    }

    // MARK: Sections

    /// Selection-pause notice and Select/Switch error, in one card shown only while either
    /// applies. The page title already names the player, so there is no avatar or name here.
    private func noticesCard(_ notice: PlayerProfileIdentityNotice?) -> UIView {
        let section = UKGroupSectionView()
        var rows: [UIView] = []
        if let notice {
            let label = UKLabel(notice.message, style: .footnote, color: BrandUIColors.gold)
            label.accessibilityIdentifier = notice.accessibilityIdentifier
            rows.append(label)
        }
        if let actionError {
            let label = UKLabel(actionError, style: .footnote, color: BrandUIColors.gold)
            label.accessibilityIdentifier = "fst.player.action-error"
            rows.append(label)
        }
        section.setRows(rows)
        return section
    }

    private func identityNotice(_ payload: PlayerProfilePayload) -> PlayerProfileIdentityNotice? {
        PlayerProfileIdentityNotice.notice(
            isSelected: isSelected, payloadPublicationId: payload.publicationId, sessionPublicationId: session.publicationId
        )
    }

    private func tileLink(_ link: PlayerStatLink?) -> PlayerStatLink? {
        PlayerProfileTiles.tileLink(link, hasNavigator: hasNavigator, isSelected: isSelected, hasIdentity: identity != nil)
    }

    private func overallTiles(_ payload: PlayerProfilePayload) -> [StatTile] {
        let visible = Set(visibleInstruments)
        let stats = payload.profile.overallStats(visibleInstruments: visible)
        return PlayerProfileTiles.overall(stats, visible: visible, link: tileLink)
    }

    private func overallSection(_ payload: PlayerProfilePayload) -> UIView {
        let grid = UKStatGridView(
            tiles: overallTiles(payload), scope: "overview", layoutProvider: { [weak self] in self?.layout ?? .standardPhone }
        )
        grid.onSelect = { [weak self] link in self?.open(link) }
        overviewGrid = grid
        let header = UKProfileInset(UKSectionHeaderView("Global Statistics"), horizontal: UKProfileMetrics.headerInset)
        let section = UKProfileSection([header, grid], spacing: 8)
        section.ukContain(identifier: "fst.player.overview")
        return section
    }

    /// One instrument's block: header, Rank History, stat cards and Percentiles (each its own
    /// card). The header sits above its card, never inside it.
    private func instrumentSection(_ payload: PlayerProfilePayload, instrument: Instrument, accountId: String) -> UIView {
        let stats = payload.profile.instrumentStats(instrument)
        var views: [UIView] = [UKProfileInstrumentHeader(instrument)]
        var entry = InstrumentViews(container: UIView())
        if stats.songsPlayed == 0 {
            let section = UKGroupSectionView()
            let note = UKFootnoteLabel("No \(instrument.label) scores recorded yet.")
            note.accessibilityIdentifier = "fst.player.instrument-empty.\(instrument.rawValue)"
            section.setRows([note])
            views.append(section)
        } else {
            let history = UKPlayerRankHistoryCardView(
                session: session, accountId: accountId, instrument: instrument, preloaded: historyPreloads[instrument]
            )
            let card = UKInstrumentStatsCardView(
                session: session, accountId: accountId, instrument: instrument,
                tiles: PlayerProfileTiles.instrument(payload.profile, stats: stats, link: tileLink),
                preloaded: rankPreloads[instrument], linkFilter: { [weak self] in self?.tileLink($0) },
                layoutProvider: { [weak self] in self?.layout ?? .standardPhone },
                onSelect: { [weak self] link in self?.open(link) }
            )
            let percentiles = UKPlayerPercentileTableCardView(
                buckets: payload.profile.percentileBuckets(instrument), instrument: instrument,
                linkFilter: { [weak self] in self?.tileLink($0) }, onSelect: { [weak self] link in self?.open(link) }
            )
            views += [history, card, percentiles]
            entry.history = history
            entry.stats = card
            entry.percentiles = percentiles
        }
        let section = UKProfileSection(views, spacing: 12)
        section.ukContain(identifier: "fst.player.instrument.\(instrument.rawValue)")
        entry.container = section
        instrumentViews[instrument] = entry
        return section
    }

    /// Re-evaluates which tiles link and the identity action (selection or publication changed).
    private func refreshLinks() {
        guard case let .available(raw) = shownPhase else {
            updateBar()
            return
        }
        let payload = effective(raw)
        let noticePresence = identityNotice(payload) != nil || actionError != nil
        if noticePresence != renderedNoticePresence {
            renderAvailable(fadeIn: false)
            updateBar()
            return
        }
        overviewGrid?.setTiles(overallTiles(payload))
        for (instrument, views) in instrumentViews {
            let stats = payload.profile.instrumentStats(instrument)
            views.stats?.update(tiles: PlayerProfileTiles.instrument(payload.profile, stats: stats, link: tileLink))
            views.percentiles?.refreshLinks()
        }
        updateBar()
    }

    // MARK: Actions

    private func open(_ link: PlayerStatLink) {
        switch PlayerProfileTiles.decision(for: link, isSelected: isSelected, identity: identity) {
        case .navigate:
            navigate(link)
        case .selectThenNavigate:
            if select() { navigate(link) }
        case .confirmSwitch:
            pendingLink = link
            confirmSwitch()
        case .ignore:
            break
        }
    }

    private func navigate(_ link: PlayerStatLink) {
        UKProfileLinks.follow(link, context: context)
    }

    private func perform(_ action: ProfileIdentityAction) {
        switch action {
        case .select: select()
        case .switchTo: confirmSwitch()
        case .deselect: confirmDeselect()
        }
    }

    /// Promote the current viewed, response-proven read to the selected profile.
    ///
    /// - Returns: Whether the player is now selected.
    @discardableResult
    private func select() -> Bool {
        guard case let .available(payload) = shownPhase else { return false }
        let result = PlayerSearchResult(accountId: payload.profile.accountId, displayName: displayName)
        do {
            try session.selectPlayer(result, from: payload)
            actionError = nil
            return true
        } catch {
            actionError = error.localizedDescription
            refreshLinks()
            return false
        }
    }

    private func confirmSwitch() {
        present(
            title: "Switch selected profile?", message: "Scores and profile-dependent pages will update to \(displayName).",
            confirm: "Switch Profile",
            onConfirm: { [weak self] in
                guard let self else { return }
                let link = self.pendingLink
                self.pendingLink = nil
                if self.select(), let link { self.navigate(link) }
            },
            onCancel: { [weak self] in self?.pendingLink = nil }
        )
    }

    private func confirmDeselect() {
        present(
            title: "Deselect profile?", message: "Scores and profile-only content will be hidden; app Settings stay saved.",
            confirm: "Deselect Profile", onConfirm: { [weak self] in self?.session.deselectPlayer() }, onCancel: nil
        )
    }

    /// A destructive confirmation dialog (`.confirmationDialog` with a visible title).
    private func present(title: String, message: String, confirm: String, onConfirm: @escaping () -> Void, onCancel: (() -> Void)?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: confirm, style: .destructive) { _ in onConfirm() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in onCancel?() })
        if let popover = alert.popoverPresentationController {
            if let item = identityBarItem {
                popover.barButtonItem = item
            } else {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        present(alert, animated: true)
    }

    // MARK: Bar

    /// Select / Switch as a prominent header button (Deselect lives in the drawer), disabled
    /// while the read is in flight or paused so the bar never re-lays out; in the iPhone Duo
    /// vertical bar it is a rail item with its symbol.
    private func updateBar() {
        identityBarItem = makeIdentityItem()
        pageToolsChanged()
    }

    private func makeIdentityItem() -> UIBarButtonItem? {
        guard !statistics else { return nil }
        let action: ProfileIdentityAction
        let enabled: Bool
        if let identity, identity != .deselect {
            action = identity
            enabled = true
        } else if PlayerProfileTiles.showsIdentityPlaceholder(shownPhase), plannedIdentity != .deselect {
            action = plannedIdentity
            enabled = false
        } else {
            return nil
        }
        if layout.sectionChrome.isVerticalBar {
            guard enabled else { return nil }
            let item = UIBarButtonItem(image: UIImage(systemName: action.systemImage), primaryAction: UIAction(title: action.title) { [weak self] _ in
                self?.perform(action)
            })
            item.accessibilityLabel = action.title
            item.accessibilityIdentifier = action.railAccessibilityIdentifier
            item.tintColor = action.isDestructive ? BrandUIColors.statusRed : UKAccentText.prominentFill
            return item
        }
        let item = UIBarButtonItem(title: action.shortTitle, image: nil, primaryAction: UIAction(title: action.shortTitle) { [weak self] _ in
            self?.perform(action)
        })
        if #available(iOS 26.0, *) {
            item.style = .prominent
            item.tintColor = action.isDestructive ? BrandUIColors.statusRed : UKAccentText.prominentFill
        } else {
            item.style = .done
            item.tintColor = action.isDestructive ? BrandUIColors.statusRed : UKAccentText.prominentFill
        }
        item.setTitleTextAttributes([.font: UKFont.font(.body, weight: .semibold), .foregroundColor: enabled ? UIColor.white : BrandUIColors.textDisabled], for: .normal)
        item.setTitleTextAttributes([.font: UKFont.font(.body, weight: .semibold), .foregroundColor: BrandUIColors.textDisabled], for: .disabled)
        item.accessibilityLabel = action.title
        // A distinct identifier while disabled, so journeys waiting for the action never tap the placeholder.
        item.accessibilityIdentifier = enabled ? action.accessibilityIdentifier : action.accessibilityIdentifier + ".pending"
        item.isEnabled = enabled
        return item
    }
}

// MARK: - Statistics

/// `/statistics`: the selected player's own profile statistics hub (``StatisticsScreen``).
/// The web renders this route by pointing `PlayerPage` at the tracked account; this page is
/// ``UKPlayerProfileViewController`` always in its selected state, carrying the shell's bell
/// and avatar.
@MainActor
final class UKStatisticsViewController: UKPlayerProfileViewController {
    /// Creates the page.
    ///
    /// - Parameter context: The screen's context.
    init(context: UKContext) {
        super.init(context: context, accountId: nil, displayName: nil, statistics: true)
    }
}
#endif
