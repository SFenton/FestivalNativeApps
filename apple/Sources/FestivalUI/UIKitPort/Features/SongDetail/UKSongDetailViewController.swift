#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Song Detail

/// The song page (``SongDetailScreen``): a spinner until every visible chart's top ten, the
/// selected player's history, the band previews and the Item Shop feed have loaded, then a
/// scrolling page that fades in with the web's stagger: the hero (cover, title, artist,
/// year), Intensity, Score History, one leaderboard card per visible chart, and the Duos,
/// Trios and Quads previews.
///
/// Page tools are Item Shop, Paths and Quick Links (all after the first load); the song's
/// cover is the shared backdrop while the page is on screen (``UKBackgroundRegistration``).
final class UKSongDetailViewController: UIViewController, UKPageToolsProviding, UIScrollViewDelegate {
    private let song: Song
    private let context: UKContext
    private var session: FestivalSession { context.session }

    // State (the SwiftUI screen's @State)
    private var ready = false
    private var previewPreloads: [Instrument: SongScorePreview.LoadState] = [:]
    private var historyEntries: [ScoreHistoryEntry] = []
    private var historyInstrument: Instrument?
    private var loadedGate: GateKey?
    private var bandPreviews: SongBandPreviewState = .loading
    private var bandKey: BandKey?
    private var shopRefreshFailure: String?
    private var heroTitleBottom: CGFloat = 0
    private var heroTitleHidden = false
    private var gateTask: Task<Void, Never>?
    private var shopTask: Task<Void, Never>?
    private var shopTaskKey: ShopTaskKey?
    private var visibleInstruments: Set<Instrument>

    /// What the page's first-appearance reads depend on.
    private struct GateKey: Hashable {
        let publicationRevision: Int
        let accountId: String?
        let leeway: Double?
    }

    /// What the band previews depend on (not leeway: band scores are unfiltered).
    private struct BandKey: Hashable {
        let publicationRevision: Int
        let accountId: String?
    }

    private struct ShopTaskKey: Equatable {
        let publicationRevision: Int
        let hidden: Bool
        let contentShown: Bool
    }

    // Views
    private let scrollView = UKControlScrollView()
    private let contentStack = UIStackView()
    private var hero: UIView?
    private var heroTitle: UKMarqueeLabel?
    private let shopErrorHolder = UIView()
    private var intensity: UIView?
    private var intensityHeader: UIView?
    private var historyHolder = UIView()
    private var historyView: UKSongScoreHistoryView?
    private var cardViews: [Instrument: UKSongScorePreviewView] = [:]
    private var bandViews: [BandType: UKSongBandPreviewView] = [:]
    private var cardGrid: UKSongDetailCardGridView?
    private var bandGrid: UKSongDetailCardGridView?
    private var barTitleView: UKSongBarTitleView?

    // Seams
    private lazy var background = UKBackgroundRegistration(session: session, mode: .song(song.albumArt))
    private lazy var quickLinks = UKQuickLinks(controller: QuickLinksController(), title: "Quick Links", sections: [])
    private let observations = UKObservationBag()
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    private var cachedShop: (key: String, item: UIBarButtonItem)?
    private var cachedPaths: UIBarButtonItem?

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - song: Catalogue record opened from the Songs route.
    ///   - context: The pushing screen's context.
    init(song: Song, context: UKContext) {
        self.song = song
        self.context = context
        visibleInstruments = context.visibleInstruments
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        gateTask?.cancel()
        shopTask?.cancel()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    // MARK: State derived

    private var previewInstruments: [Instrument] { SongDetailPlan.previewInstruments(song, visible: visibleInstruments) }
    private var pathInstruments: [Instrument] { SongDetailPlan.pathInstruments(visible: visibleInstruments) }
    private var hideShop: Bool { UKSettings.bool("fst.settings.hideShop", default: false) }
    private var showsScoreHistory: Bool { session.selectedPlayer != nil && !historyEntries.isEmpty }

    private var shopOffer: ShopSong? { hideShop ? nil : session.shopOffersById[song.songId] }

    private var shopTone: ShopStatusTone? {
        ShopStatusTone.tone(
            for: shopOffer, hidden: hideShop, highlightingDisabled: UKSettings.bool("fst.settings.disableShopHighlighting", default: false)
        )
    }

    private var tools: SongDetailPageTools {
        .resolve(contentShown: ready, hasShopOffer: shopOffer != nil, hasPathCharts: !pathInstruments.isEmpty)
    }

    private var gateKey: GateKey {
        let filter = UKSettings.bool("fst.settings.filterInvalidScores", default: false)
        let leeway = UserDefaults.standard.object(forKey: "fst.settings.leeway") as? Double ?? 1.0
        return GateKey(
            publicationRevision: session.publicationRevision, accountId: session.selectedPlayer?.accountId,
            leeway: filter ? (leeway * 10).rounded() / 10 : nil
        )
    }

    private var fadesEnabled: Bool { !DebugAnimationOverride.stillBackground || DebugAnimationOverride.keepFades }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureScroll()
        configureLoading()
        observations.observe { [weak self] in self?.sessionChanged() }
        settingsObserver = NotificationCenter.default.addObserver(forName: UKSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        quickLinks.onToolChange = { [weak self] in self?.ukPageToolsDidChange() }
        quickLinks.attach(to: scrollView, rect: { [weak self] id in self?.rect(forSection: id) }, element: { [weak self] id in self?.element(forSection: id) })
        gateChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        background.viewWillAppear()
        ukSetPageTitle(song.title, mode: .inline, floatsPageTools: ukShell?.floatsPageTools ?? false)
        navigationItem.largeTitleDisplayMode = .never
        applyBarTitle(animated: false)
        ukInstallAccountItems()
        quickLinks.didAppear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        background.viewDidDisappear()
        quickLinks.willDisappear()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        measureHeroTitle()
        quickLinks.scrollViewDidScroll()
    }

    private func configureScroll() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .automatic
        view.addSubview(scrollView)
        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.alignment = .fill
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor), scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
        scrollView.isHidden = true
    }

    private func configureLoading() {
        let loading = UKLoadingView(accessibilityLabel: "Loading \(song.title)", placement: .fill)
        loading.hingeProvider = { [weak self] in self?.ukLayout.splitHinge }
        loading.translatesAutoresizingMaskIntoConstraints = false
        loading.accessibilityIdentifier = "fst.song-detail.loading"
        view.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.leadingAnchor.constraint(equalTo: view.leadingAnchor), loading.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loading.topAnchor.constraint(equalTo: view.topAnchor), loading.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        loadingFill = loading
    }

    private var loadingFill: UKLoadingView?

    // MARK: Observation

    /// Everything the page reads from the session: a new publication or profile restarts the
    /// gate, a Shop change updates the tools and the error line.
    private func sessionChanged() {
        _ = session.publicationRevision
        _ = session.selectedPlayer?.accountId
        _ = session.shopOffersById[song.songId]
        _ = session.shopError
        _ = session.currentShop?.publicationId
        guard isViewLoaded else { return }
        gateChanged()
        shopTaskMaybeChanged()
        refreshShopError()
        ukPageToolsDidChange()
        refreshQuickLinks()
    }

    private func settingsChanged() {
        let visible = context.visibleInstruments
        if visible != visibleInstruments {
            visibleInstruments = visible
            if ready { rebuildContent() }
        }
        gateChanged()
        shopTaskMaybeChanged()
        cachedShop = nil
        ukPageToolsDidChange()
    }

    // MARK: Tools

    var ukPageTools: [UKPageTool] {
        var result: [UKPageTool] = []
        let floating = ukShell?.floatsPageTools ?? false
        let chrome = ukWindowLayout.sectionChrome
        if tools.shop, let offer = shopOffer {
            let key = "\(offer.shopUrl.absoluteString)|\(shopTone.map { "\($0)" } ?? "")|\(floating)|\(chrome.isVerticalBar)"
            if cachedShop?.key != key {
                cachedShop = (key, UKSongDetailShopAction.item(offer: offer, tone: shopTone, chrome: chrome, floating: floating))
            }
            if let item = cachedShop?.item { result.append(UKPageTool(order: PageToolOrder.primary, item: item)) }
        }
        if tools.paths {
            if cachedPaths == nil {
                let item = UIBarButtonItem(title: "Paths", image: UIImage(systemName: "map"), primaryAction: UIAction { [weak self] _ in self?.presentPaths() })
                item.accessibilityIdentifier = "fst.song-detail.paths"
                item.accessibilityLabel = "Paths"
                item.tintColor = BrandUIColors.textPrimary
                cachedPaths = item
            }
            if let item = cachedPaths { result.append(UKPageTool(order: PageToolOrder.secondary, item: item)) }
        }
        if tools.quickLinks, let tool = quickLinks.tool { result.append(tool) }
        return result
    }

    private func presentPaths() {
        guard let first = pathInstruments.first else { return }
        let layout = ukWindowLayout
        let coverage = SongPathsPolicy.coverage(layout)
        let pathDefault = PathDisplayMode(rawValue: UserDefaults.standard.string(forKey: "fst.settings.pathDefaultView") ?? "") ?? .image
        let page = UKSongPathsViewController(
            song: song, context: context.with { $0.surface = .sheet }, instruments: pathInstruments, firstInstrument: first,
            defaultDisplay: pathDefault, warnAboutKaraoke: visibleInstruments.contains(.karaoke), coverage: coverage
        )
        UKSheet.present(page, from: self, title: nil, closeIdentifier: "fst.paths.close", size: .large, sizing: .page, coverage: coverage)
    }

    // MARK: Loading

    private func gateChanged() {
        guard isViewLoaded else { return }
        let key = gateKey
        guard loadedGate != key else { return }
        gateTask?.cancel()
        gateTask = Task { [weak self] in await self?.loadGate(key) }
    }

    /// First appearance: read every visible chart's top ten, the selected player's history
    /// for this song, the band previews and the Item Shop feed in parallel, then show the
    /// page. Later key changes refresh the history quietly; the cards reload themselves.
    private func loadGate(_ key: GateKey) async {
        guard loadedGate != key else { return }
        if ready {
            async let bands: Void = loadBandsIfNeeded()
            await loadHistory()
            await bands
            if !Task.isCancelled { loadedGate = key }
            applyHistory()
            return
        }
        async let history: Void = loadHistory()
        async let bands: Void = loadBandsIfNeeded()
        async let shop: Void = loadShopIfNeeded()
        let previews = await SongDetailPreloader.previews(
            session: session, song: song, instruments: previewInstruments, leeway: key.leeway
        )
        await history
        await bands
        await shop
        guard !Task.isCancelled else { return }
        previewPreloads = previews
        loadedGate = key
        ready = true
        showContent()
    }

    private func loadBandsIfNeeded() async {
        let key = BandKey(publicationRevision: session.publicationRevision, accountId: session.selectedPlayer?.accountId)
        guard bandKey != key else { return }
        guard let state = await SongBandPreviewLoader.load(session: session, songId: song.songId, accountId: key.accountId) else { return }
        bandPreviews = state
        bandKey = key
        for view in bandViews.values { view.state = state }
    }

    private func reloadBands() async {
        bandPreviews = .loading
        bandKey = nil
        for view in bandViews.values { view.state = .loading }
        await loadBandsIfNeeded()
    }

    private func loadHistory() async {
        guard let accountId = session.selectedPlayer?.accountId else {
            historyEntries = []
            return
        }
        do {
            let payload = try await session.songHistory(accountId: accountId, songId: song.songId)
            try Task.checkCancellation()
            historyEntries = payload.state == .available ? payload.response.history.filter { $0.songId == song.songId } : []
        } catch {
            guard !Task.isCancelled else { return }
            historyEntries = []
        }
    }

    private func shopTaskMaybeChanged() {
        let key = ShopTaskKey(publicationRevision: session.publicationRevision, hidden: hideShop, contentShown: ready)
        guard key != shopTaskKey else { return }
        shopTaskKey = key
        guard ready else { return }
        shopTask?.cancel()
        shopTask = Task { [weak self] in
            await self?.loadShopIfNeeded()
            self?.refreshShopError()
            self?.ukPageToolsDidChange()
        }
    }

    /// Read the Item Shop feed unless it is hidden, already known or already failed. A
    /// failure is the explicit completed-no-offer state (the page shows the Shop status
    /// error instead of the action).
    private func loadShopIfNeeded() async {
        guard !hideShop, session.currentShop == nil, session.shopError == nil else { return }
        do {
            _ = try await session.shop()
            try Task.checkCancellation()
            shopRefreshFailure = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            shopRefreshFailure = error.localizedDescription
        }
    }

    // MARK: Content

    private func showContent() {
        loadingFill?.removeFromSuperview()
        loadingFill = nil
        scrollView.isHidden = false
        rebuildContent()
        shopTaskKey = ShopTaskKey(publicationRevision: session.publicationRevision, hidden: hideShop, contentShown: true)
        ukPageToolsDidChange()
        refreshQuickLinks()
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cardViews = [:]
        bandViews = [:]
        let hero = makeHero()
        self.hero = hero
        contentStack.addArrangedSubview(hero)
        contentStack.addArrangedSubview(shopErrorHolder)
        refreshShopError()
        let intensity = makeIntensity()
        contentStack.addArrangedSubview(intensity)
        historyHolder.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(historyHolder)
        applyHistory()
        let layout: () -> DeviceLayout = { [weak self] in self?.ukLayout ?? .standardPhone }
        let cards = previewInstruments.map { instrument -> UIView in
            let card = UKSongScorePreviewView(song: song, instrument: instrument, context: context, preloaded: previewPreloads[instrument])
            cardViews[instrument] = card
            return card
        }
        let grid = UKSongDetailCardGridView(cards: cards, layoutProvider: layout)
        cardGrid = grid
        contentStack.addArrangedSubview(grid)
        let bands = BandType.allCases.map { bandType -> UIView in
            let view = UKSongBandPreviewView(song: song, bandType: bandType, state: bandPreviews, context: context) { [weak self] in
                guard let self else { return }
                Task { await self.reloadBands() }
            }
            bandViews[bandType] = view
            return view
        }
        let bandGrid = UKSongDetailCardGridView(cards: bands, layoutProvider: layout)
        self.bandGrid = bandGrid
        contentStack.addArrangedSubview(bandGrid)
        if fadesEnabled {
            UKFadeIn.fadeIn(hero, staggerIndex: 0)
            UKFadeIn.fadeIn(intensity, staggerIndex: 1)
            for (index, card) in cards.enumerated() { UKFadeIn.fadeIn(card, staggerIndex: index + 3) }
            for (index, view) in bands.enumerated() { UKFadeIn.fadeIn(view, staggerIndex: cards.count + index + 3) }
        }
        view.setNeedsLayout()
    }

    // MARK: Hero

    private func makeHero() -> UIView {
        let art = UKArtworkTileView(size: 96)
        art.configure(raw: song.albumArt, session: session)
        var details: [UIView] = []
        if let year = song.year {
            details.append(UKLabel(year.formatted(.number.grouping(.never))))
        }
        let text = UKSongHeaderTextView(
            title: song.title, artist: song.artist, titleFont: UKFont.font(.title1, weight: .bold), spacing: 8, details: details
        )
        heroTitle = text.titleView
        let row = UIStackView(arrangedSubviews: [art, text])
        row.spacing = 16
        row.alignment = .top
        let holder = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: holder.leadingAnchor), row.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            row.topAnchor.constraint(equalTo: holder.topAnchor), row.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        // The page's h1: the rotor's first heading.
        holder.isAccessibilityElement = true
        holder.accessibilityTraits = .header
        holder.accessibilityLabel = ([song.title, song.artist] + details.compactMap { ($0 as? UILabel)?.text }).joined(separator: ", ")
        holder.accessibilityIdentifier = "fst.song-detail.hero-title"
        return holder
    }

    private func measureHeroTitle() {
        guard let title = heroTitle, title.window != nil else { return }
        let bottom = title.convert(title.bounds, to: scrollView).maxY
        if abs(bottom - heroTitleBottom) > 0.5 {
            heroTitleBottom = bottom
            updateHeroHidden()
        }
    }

    private func updateHeroHidden() {
        let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let hidden = SongHeaderScrollAway.isHidden(offset: offset, headerBottom: heroTitleBottom)
        guard hidden != heroTitleHidden else { return }
        heroTitleHidden = hidden
        applyBarTitle(animated: !UKAccessibility.reduceMotion)
    }

    /// The pinned bar title: empty until the hero title scrolls away, then the song's
    /// identity (also in the iPhone Duo vertical bar, where the bar stays at the top).
    private func applyBarTitle(animated: Bool) {
        let next: UIView
        if heroTitleHidden {
            let title = UKSongBarTitleView(song: song, session: session, identifier: "fst.song-detail.pinned-title")
            barTitleView = title
            next = title
        } else {
            let clear = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            clear.isAccessibilityElement = false
            clear.accessibilityElementsHidden = true
            next = clear
        }
        if animated, let bar = navigationController?.navigationBar {
            UIView.transition(with: bar, duration: 0.2, options: [.transitionCrossDissolve, .curveEaseInOut]) { self.navigationItem.titleView = next }
        } else {
            navigationItem.titleView = next
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateHeroHidden()
        quickLinks.scrollViewDidScroll()
    }

    // MARK: Shop error

    private func refreshShopError() {
        shopErrorHolder.subviews.forEach { $0.removeFromSuperview() }
        guard ready, !hideShop, let error = session.shopError ?? (session.currentShop == nil ? shopRefreshFailure : nil) else {
            shopErrorHolder.isHidden = true
            return
        }
        shopErrorHolder.isHidden = false
        let disclosure = UKFreshnessDisclosureView(message: "Item Shop status unavailable: \(error)", symbol: "exclamationmark.triangle")
        disclosure.accessibilityIdentifier = "fst.song-detail.shop-error"
        disclosure.translatesAutoresizingMaskIntoConstraints = false
        shopErrorHolder.addSubview(disclosure)
        NSLayoutConstraint.activate([
            disclosure.leadingAnchor.constraint(equalTo: shopErrorHolder.leadingAnchor), disclosure.trailingAnchor.constraint(equalTo: shopErrorHolder.trailingAnchor),
            disclosure.topAnchor.constraint(equalTo: shopErrorHolder.topAnchor), disclosure.bottomAnchor.constraint(equalTo: shopErrorHolder.bottomAnchor),
        ])
    }

    // MARK: Intensity

    private func makeIntensity() -> UIView {
        let header = UKSectionHeaderView("Intensity")
        intensityHeader = header
        let cells: [UIView] = Instrument.allCases.compactMap { instrument in
            guard SongDetailPlan.charted(song).contains(instrument), let level = song.difficulty?.chartedValue(for: instrument) else { return nil }
            let icon = UKInstrumentIconView(
                instrument, keyboard: song.usesKeyboardIcon && (instrument == .lead || instrument == .proLead), size: 22
            )
            let row = UIStackView(arrangedSubviews: [icon, UKDifficultyMeterView(level: level, raw: true), UIView()])
            row.spacing = 8
            row.alignment = .center
            return row
        }
        let card = UKCardView(cornerRadius: 16)
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 10
        for start in stride(from: 0, to: cells.count, by: 2) {
            let pair = UKHingeColumnsView()
            pair.spacing = 10
            pair.layoutProvider = { [weak self] in self?.ukLayout ?? .standardPhone }
            pair.translatesAutoresizingMaskIntoConstraints = false
            for (offset, cell) in cells[start ..< min(start + 2, cells.count)].enumerated() {
                let host = offset == 0 ? pair.leadingContent : pair.trailingContent
                cell.translatesAutoresizingMaskIntoConstraints = false
                host.addSubview(cell)
                NSLayoutConstraint.activate([
                    cell.leadingAnchor.constraint(equalTo: host.leadingAnchor), cell.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                    cell.topAnchor.constraint(equalTo: host.topAnchor), cell.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                ])
            }
            pair.heightAnchor.constraint(equalToConstant: 24).isActive = true
            rows.addArrangedSubview(pair)
        }
        card.embed(rows, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        let column = UIStackView(arrangedSubviews: [header, card])
        column.axis = .vertical
        column.spacing = 12
        column.accessibilityContainerType = .semanticGroup
        column.accessibilityIdentifier = "fst.song-detail.intensity"
        intensity = column
        return column
    }

    // MARK: Score History

    private func applyHistory() {
        guard ready else { return }
        let shows = showsScoreHistory
        if shows {
            let preferred = historyView?.chosen ?? historyInstrument
            let section = UKSongScoreHistoryView(
                song: song, entries: historyEntries, pool: previewInstruments, preferred: preferred,
                currentSeason: session.catalogCurrentSeason, viewportWidth: view.bounds.width.rounded(), context: context
            )
            historyView?.removeFromSuperview()
            historyView = section
            historyHolder.addSubview(section)
            NSLayoutConstraint.activate([
                section.leadingAnchor.constraint(equalTo: historyHolder.leadingAnchor), section.trailingAnchor.constraint(equalTo: historyHolder.trailingAnchor),
                section.topAnchor.constraint(equalTo: historyHolder.topAnchor), section.bottomAnchor.constraint(equalTo: historyHolder.bottomAnchor),
            ])
            historyHolder.isHidden = false
            if fadesEnabled { UKFadeIn.fadeIn(section, staggerIndex: 2) }
        } else {
            historyInstrument = historyView?.chosen ?? historyInstrument
            historyView?.removeFromSuperview()
            historyView = nil
            historyHolder.isHidden = true
        }
        refreshQuickLinks()
    }

    // MARK: Quick Links

    private func refreshQuickLinks() {
        let sections = tools.quickLinks
            ? SongDetailPlan.quickLinkSections(previewInstruments: previewInstruments, showsScoreHistory: showsScoreHistory) : []
        quickLinks.controller.configure(title: "Quick Links", explicit: sections)
        quickLinks.scrollViewDidScroll()
    }

    private func sectionView(_ id: String) -> UIView? {
        if id == "intensity" { return intensity }
        if id == "score-history" { return historyView }
        if id.hasPrefix("instrument-"), let instrument = Instrument(rawValue: String(id.dropFirst("instrument-".count))) { return cardViews[instrument] }
        if id.hasPrefix("band-"), let band = BandType(rawValue: String(id.dropFirst("band-".count))) { return bandViews[band] }
        return nil
    }

    private func rect(forSection id: String) -> CGRect? {
        guard let view = sectionView(id), view.window != nil, !view.isHidden, view.superview != nil else { return nil }
        return view.convert(view.bounds, to: scrollView)
    }

    private func element(forSection id: String) -> NSObject? {
        switch id {
        case "intensity": intensityHeader
        case "score-history": historyView?.headerElement
        default:
            if id.hasPrefix("band-"), let band = BandType(rawValue: String(id.dropFirst("band-".count))) { bandViews[band]?.headerElement } else { sectionView(id) }
        }
    }
}
#endif
