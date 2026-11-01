#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Identifiers

/// A section of the Songs list.
enum UKSongsSectionID: Hashable {
    case notices
    case group(String)
}

/// An item of the Songs list.
enum UKSongsItem: Hashable {
    case notice(Int, String)
    case song(String)
}

// MARK: - Songs

/// The Songs catalogue page (``SongsScreen``) in UIKit: a diffable compositional collection view
/// of material row cards under a floating section bar, with the A–Z rail, Quick Links, the
/// Sort and Filter tools, the Filter Songs field and the loading, failed, empty and paused
/// states. All filtering, sorting, grouping and provenance rules come from ``SongsPipeline``.
final class UKSongsViewController: UIViewController, UICollectionViewDelegate, UKPageToolsProviding {
    // MARK: State

    let context: UKContext
    var session: FestivalSession { context.session }

    /// The catalogue read, as ``SongsScreen/LoadState``.
    enum LoadState {
        case loading
        case loaded(CatalogPayload)
        case failed(ServiceIssue)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    /// What the content region shows.
    enum Presented {
        case loading
        case failed(ServiceIssue)
        case savedFiltersInvalid(String)
        case sortFailed(String)
        case empty(search: String, filtersApplied: Bool, restricting: Bool, disclosures: [SongsDisclosure])
        case list
    }

    var state: LoadState = .loading
    var refreshFailure: String?
    var shopRefreshFailure: String?
    var shopRetryRevision = 0 { didSet { restartTasks() } }
    var searchText = ""
    var settledSearch = ""
    var instrument: Instrument?
    var navigationNotice: String?
    var settings = SongsSettings.load()
    var visibleInstruments: Set<Instrument>
    var shownRevision: Int
    var refreshing = false
    /// A publication refresh has run, so the page anchor (focus target) exists.
    var hasRefreshed = false
    let refreshAnchor = UIView()
    let refreshMarker = UIView()
    var isVisible = false
    var presented = Presented.loading
    var visibleSongs: [Song] = []
    var groups: [SongsListGroup]?
    var showsIndex = false
    var indexSections: [SongSection] = []
    var disclosures: [SongsDisclosure] = []
    var songsById: [String: Song] = [:]
    var songsByIdPayload: Int?
    var observedCatalogue = 0
    var effectiveMode = SongSortMode.title
    var lastReorderKey: [String] = []
    var lastSnapshotKey: [String] = []
    var lastLayoutKey: [String] = []
    var tools: [UKPageTool] = []
    var sheetObserver: UKSongsSheetDismissObserver?
    var toolsToken: [String] = []

    // MARK: Views

    let listContainer = UIView()
    let bottomContainer = UIView()
    var lastPlacement: SongsFilterFieldPlacement?
    var quickLinksKey: [String] = []
    var teleporting = false
    var debugPushed = false
    lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    var dataSource: UICollectionViewDiffableDataSource<UKSongsSectionID, UKSongsItem>!
    let sectionBar = UKSongsSectionBar()
    let barBlocker = UIView()
    let indexView = UKSongSectionIndexView()
    var gate: UKReloadGate!
    var statusView: UIView?
    var edgeFade: UKPinnedHeaderEdgeFade?
    var bottomFade: UKBottomChromeFade?
    var bottomField: UKBottomSearchField?
    let searchController = UISearchController(searchResultsController: nil)
    lazy var background = UKBackgroundRegistration(session: context.session, mode: .carousel)
    let observations = UKObservationBag()
    var quickLinks: UKQuickLinks?
    let quickLinksController = QuickLinksController()
    var tasks: [Task<Void, Never>] = []
    var searchTask: Task<Void, Never>?
    var lastTaskKey: [Int] = []
    var jumpGeneration = 0
    nonisolated(unsafe) var defaultsObserver: NSObjectProtocol?
    nonisolated(unsafe) var presetObserver: NSObjectProtocol?

    // MARK: Init

    /// Creates the page.
    ///
    /// - Parameter context: The section's context.
    init(context: UKContext) {
        self.context = context
        visibleInstruments = context.visibleInstruments
        shownRevision = context.session.publicationRevision
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        if let presetObserver { NotificationCenter.default.removeObserver(presetObserver) }
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "fst.songs.page"
        ukSetPageTitle("Songs", floatsPageTools: ukShell?.floatsPageTools ?? false)
        navigationItem.largeTitleDisplayMode = .automatic
        buildViews()
        configureDataSource()
        configureSearch()
        gate = UKReloadGate(key: reloadKey, isLoading: true, spinnerLabel: "Loading songs")
        gate.onReveal = { [weak self] in self?.revealList() }
        gate.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(gate, at: 0)
        NSLayoutConstraint.activate([
            gate.leadingAnchor.constraint(equalTo: view.leadingAnchor), gate.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gate.topAnchor.constraint(equalTo: view.topAnchor), gate.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        gate.contentView.addSubview(listContainer)
        listContainer.frame = gate.contentView.bounds
        listContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        listContainer.addSubview(bottomContainer)
        bottomContainer.frame = listContainer.bounds
        bottomContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        bottomContainer.addSubview(collectionView)
        collectionView.frame = bottomContainer.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        edgeFade = UKPinnedHeaderEdgeFade(maskedView: listContainer)
        for proxy in [refreshAnchor, refreshMarker] {
            proxy.isUserInteractionEnabled = false
            proxy.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
            view.addSubview(proxy)
        }
        view.addSubview(barBlocker)
        view.addSubview(sectionBar)
        view.addSubview(indexView)
        indexView.onSelect = { [weak self] id in self?.jumpToSection(id: AnyHashable(id)) }
        observeEverything()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        UKRefreshCommands.shared.register(self) { [weak self] in await self?.reloadCatalogue() }
        background.viewWillAppear()
        quickLinks?.didAppear()
        restartTasks()
        installFilterPlacement()
        #if DEBUG
        startDebugPush()
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        UKRefreshCommands.shared.unregister(self)
        quickLinks?.willDisappear()
        cancelTasks()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        background.viewDidDisappear()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        edgeFade?.layout()
        bottomFade?.layout()
        layoutChrome()
        let width = collectionView.bounds.width
        if width != lastLayoutWidth {
            lastLayoutWidth = width
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    var lastLayoutWidth: CGFloat = 0

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            collectionView.collectionViewLayout.invalidateLayout()
            reconfigureRows()
        }
    }

    // MARK: Views

    private func buildViews() {
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.accessibilityIdentifier = "fst.songs.list"
        collectionView.keyboardDismissMode = .onDrag
        collectionView.refreshControl = nil
        setContentScrollView(collectionView)
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            Task { @MainActor in
                await self?.reloadCatalogue()
                refresh?.endRefreshing()
            }
        }, for: .valueChanged)
        collectionView.refreshControl = refresh
        barBlocker.isHidden = true
        barBlocker.isAccessibilityElement = false
    }

    // MARK: Observation

    private func observeEverything() {
        // Rebuilds the list whenever anything it read changes: the session's catalogue,
        // Shop, selected profile and score index.
        observations.observe { [weak self] in self?.recompute() }
        observations.observe { [weak self] in
            guard let self else { return }
            let key = [self.session.publicationRevision, self.session.selectionRevision]
            if key != self.lastTaskKey {
                self.lastTaskKey = key
                self.restartTasks()
            }
            self.publicationMayHaveChanged()
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UKSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.settingsMayHaveChanged() } }
        // A Profile stat tile saved a Songs preset: apply its instrument and clear the search,
        // as the SwiftUI root's `showSongs` does.
        presetObserver = NotificationCenter.default.addObserver(
            forName: UKProfileLinks.songsPresetApplied, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?["instrument"] as? String
            MainActor.assumeIsolated { self?.applyPreset(instrument: raw.flatMap(Instrument.init(rawValue:))) }
        }
    }

    private func applyPreset(instrument preset: Instrument?) {
        instrument = preset
        searchController.searchBar.text = ""
        bottomField?.text = ""
        searchTask?.cancel()
        searchText = ""
        settledSearch = ""
        settings = SongsSettings.load()
        recompute()
    }

    private func settingsMayHaveChanged() {
        let loaded = SongsSettings.load()
        let visible = UKSettings.visibleInstruments()
        var changed = false
        if loaded != settings {
            let shopHidden = loaded.hideShop != settings.hideShop
            settings = loaded
            changed = true
            if shopHidden { restartTasks() }
        }
        if visible != visibleInstruments {
            visibleInstruments = visible
            if let current = instrument, !visible.contains(current) {
                navigationNotice = "\(current.label) was hidden. Showing all instruments."
                instrument = nil
            }
            changed = true
        }
        if changed { recompute() }
    }

    /// Reads the pipeline's inputs from the current state.
    func makePipeline() -> SongsPipeline {
        var payload: CatalogPayload?
        if case let .loaded(loaded) = state { payload = loaded }
        return SongsPipeline(
            session: session, payload: payload, settings: settings, instrument: instrument,
            visibleInstruments: visibleInstruments
        )
    }

    // MARK: Reload gate

    /// The list settings whose change replays the load sequence (web `settingsKey`).
    struct ReloadKey: Hashable {
        let sortMode: SongSortMode
        let sortAscending: Bool
        let generalFilter: Data
        let legacyShopFilter: [Bool]
        let playerScoreFilter: Data
        let instrument: Instrument?
        let search: String
        let revision: Int
    }

    var reloadKey: ReloadKey {
        ReloadKey(
            sortMode: settings.sortMode, sortAscending: settings.sortAscending, generalFilter: settings.generalFilterData,
            legacyShopFilter: [settings.legacyFilterInShop, settings.legacyFilterLeavingTomorrow],
            playerScoreFilter: settings.playerScoreFilterData, instrument: instrument, search: settledSearch,
            revision: shownRevision
        )
    }

    private func revealList() {
        sectionBarNeedsUpdate()
    }

    // MARK: Loading

    func cancelTasks() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// Restarts the catalogue, Shop and selected-profile reads the SwiftUI page keys on
    /// publication, selection and visibility.
    func restartTasks() {
        cancelTasks()
        guard isVisible else { return }
        tasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            switch self.state {
            case .loading, .failed:
                await self.reloadCatalogue()
            case let .loaded(payload):
                if self.shownRevision == self.session.publicationRevision,
                   let current = self.session.publicationId, payload.observedPublicationId != current {
                    await self.reloadCatalogue()
                }
            }
        })
        if !settings.hideShop {
            tasks.append(Task { @MainActor [weak self] in await self?.reloadShop() })
        }
        tasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            let session = self.session
            if session.selectedBand != nil {
                switch session.bandLoadState {
                case .loading, .failed: await session.refreshSelectedBand()
                case .none, .available, .syncing: break
                }
                return
            }
            guard session.selectedPlayer != nil else { return }
            switch session.playerLoadState {
            case .loading, .failed: await session.refreshSelectedPlayer()
            case .none, .available, .syncing: break
            }
        })
    }

    /// A new publication refreshes the list in place: it fades out, the spinner holds while the
    /// new catalogue is read and the rebuilt list fades in (issue #304).
    private func publicationMayHaveChanged() {
        let revision = session.publicationRevision
        guard revision != shownRevision, !refreshing else { return }
        refreshing = true
        hasRefreshed = true
        recompute()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let started = ContinuousClock.now
            await self.reloadCatalogue(publicationRefresh: true)
            // The spinner holds at least as long as the SwiftUI boundary's fade, hold and fade.
            let remaining = Duration.milliseconds(1200) - (ContinuousClock.now - started)
            if remaining > .zero { try? await Task.sleep(for: remaining) }
            self.shownRevision = self.session.publicationRevision
            self.refreshing = false
            self.recompute()
        }
    }

    /// The invisible heading VoiceOver focus rests on during and after a refresh
    /// (`fst.publication.page-anchor`, "Loading new scores" while it runs) and the spinner's marker.
    func updateRefreshAnchor() {
        let forced = ProcessInfo.processInfo.environment["FST_UI_TEST_PAGE_ANCHOR"] == "inside"
        let shows = hasRefreshed && (forced || UIAccessibility.isVoiceOverRunning)
        refreshAnchor.isAccessibilityElement = shows
        refreshAnchor.accessibilityIdentifier = "fst.publication.page-anchor"
        refreshAnchor.accessibilityLabel = "Songs"
        refreshAnchor.accessibilityTraits = .header
        refreshAnchor.accessibilityValue = refreshing ? "Loading new scores" : nil
        refreshMarker.isAccessibilityElement = refreshing
        refreshMarker.accessibilityIdentifier = "fst.publication.refreshing"
        refreshMarker.accessibilityLabel = "Loading new scores"
    }

    /// Refreshes the public catalogue, preserving the last-viewed process cache.
    func reloadCatalogue(publicationRefresh: Bool = false) async {
        let prior: CatalogPayload?
        if case let .loaded(payload) = state {
            prior = payload
        } else {
            prior = nil
            state = .loading
            recompute()
        }
        do {
            let updated = try await session.catalog()
            try Task.checkCancellation()
            if prior == nil || publicationRefresh {
                await SongsPipeline.primeFirstArtwork(for: updated, session: session, instrument: instrument, settings: settings)
                try Task.checkCancellation()
            }
            state = .loaded(updated)
            refreshFailure = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if let prior {
                state = .loaded(prior)
                refreshFailure = error.localizedDescription
            } else {
                state = .failed(ServiceIssue(error))
            }
        }
        recompute()
    }

    private func reloadShop() async {
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
        recompute()
    }

    // MARK: Search

    /// Sets the Filter Songs text and settles it after 250 ms.
    func setSearch(_ text: String) {
        guard text != searchText else { return }
        searchText = text
        searchTask?.cancel()
        recompute()
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.settledSearch = self.searchText
            self.recompute()
        }
    }

    // MARK: UKPageToolsProviding

    var ukPageTools: [UKPageTool] { pageTools() }
}
#endif
