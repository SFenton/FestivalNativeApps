#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Native first-run demos

/// Native demo families that mirror the catalog's actual SwiftUI demo families.
enum UKFirstRunDemoFamily: String {
    case songs
    case songsSort
    case songsNavigation
    case songsFilter
    case songInfoChart
    case songInfoScores
    case songInfoPaths
    case songInfoShop
    case playerHistory
    case statistics
    case suggestions
    case leaderboards
    case compete
    case rivals
    case shop
    case generic
}

/// A decorative UIKit rendering of one first-run catalog demo.
///
/// The carousel owns the accessible title and description. This view is deliberately inert,
/// but it uses the same bounded demo pools and catalogue selection policy as the SwiftUI
/// carousel, plus the UIKit row, card, instrument and chart primitives used by app pages.
@MainActor
final class UKFirstRunNativeDemoView: UIView {
    private let slideID: String
    private weak var session: FestivalSession?
    private let content = UIStackView()
    private var animatedViews: [UIView] = []
    private var pulseView: UIView?
    private var active = false
    private var catalogTask: Task<Void, Never>?
    private var motionObserver: UKMotionVisibilityObserver?
    private var cachedSongs: [Song] = []
    private var catalogueToken = UUID()
    nonisolated(unsafe) private var rotationTimer: Timer?
    private var rotationIndex = 0
    private var rowRotation: FirstRunRowRotation<Song>?
    private var responsiveSongRows: [(UKSongRowView, UKSongRowInput)] = []
    private var lastSongRowWidth: CGFloat = 0
    private var lastSongRowCategory: UIContentSizeCategory?
    private var embeddedControllers: [UIViewController] = []
    private(set) var embeddedControllerNames: [String] = []
    private(set) var renderedFamily: UKFirstRunDemoFamily = .generic
    private(set) var hasRenderedContent = false

    /// Whether the UIKit port has a native demo for a catalog slide.
    static func hasNativeDemo(id: String) -> Bool {
        family(for: id) != .generic && FirstRunDemoContent.hasLiveDemo(id: id)
    }

    /// Resolves a catalog id to the native family that renders its actual state.
    static func family(for id: String) -> UKFirstRunDemoFamily {
        switch id {
        case "songs-sort": .songsSort
        case "songs-navigation": .songsNavigation
        case "songs-filter": .songsFilter
        case "songinfo-chart", "songinfo-bar-select": .songInfoChart
        case "songinfo-view-all", "songinfo-top-scores": .songInfoScores
        case "songinfo-paths": .songInfoPaths
        case "songinfo-shop-button", "songinfo-new-in-shop", "songinfo-leaving-tomorrow": .songInfoShop
        case "playerhistory-score-list", "playerhistory-sort": .playerHistory
        case "statistics-select-profile", "statistics-drill-down", "statistics-overview",
             "statistics-instrument-breakdown", "statistics-percentiles", "statistics-top-songs": .statistics
        case "suggestions-category-card", "suggestions-global-filter", "suggestions-instrument-filter",
             "suggestions-infinite-scroll": .suggestions
        case "leaderboards-overview", "leaderboards-experimental-metrics", "leaderboards-your-rank": .leaderboards
        case "compete-hub", "compete-leaderboards", "compete-rivals": .compete
        case "rivals-overview", "rivals-instruments", "rivals-detail": .rivals
        case "shop-overview", "shop-highlighting", "shop-new-items", "shop-leaving-tomorrow": .shop
        case "songs-song-list", "songs-icons", "songs-metadata", "songs-shop-highlight",
             "songs-new-in-shop", "songs-leaving-tomorrow": .songs
        default: .generic
        }
    }

    private var isRotating: Bool {
        [
            "songs-song-list", "songs-icons", "songs-metadata", "songinfo-bar-select",
            "statistics-top-songs", "suggestions-category-card", "leaderboards-experimental-metrics",
            "compete-hub", "compete-rivals", "rivals-overview", "rivals-instruments", "rivals-detail",
        ].contains(slideID)
    }

    private func updateRotation(allowed: Bool) {
        guard allowed, isRotating else {
            rotationTimer?.invalidate()
            rotationTimer = nil
            return
        }
        guard rotationTimer == nil else { return }
        let components = FirstRunDemoTiming.swapInterval.components
        let interval = max(
            0.1,
            Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        )
        rotationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, self.active, self.catalogueVisible,
                  UKMotionVisibility.permitsAnimation(in: self) else { return }
            self.rotationIndex += 1
            if self.rotatingSongDemo, var rotation = self.rowRotation {
                let indices = rotation.nextSwap()
                rotation.replace(indices)
                self.rowRotation = rotation
                self.replaceSongRows(rotation.rows)
            } else {
                self.render()
            }
            self.applyMotion(animated: true)
        }
    }

    /// Creates a native demo.
    init(slide: FirstRunSlide, session: FestivalSession?) {
        slideID = slide.id
        self.session = session
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])
        motionObserver = UKMotionVisibilityObserver { [weak self] in
            guard let self else { return }
            self.applyMotion(animated: false)
        }
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        catalogTask?.cancel()
        rotationTimer?.invalidate()
    }

    /// Makes this demo the visible slide and starts or stops its decorative motion.
    func setActive(_ active: Bool, animated: Bool) {
        self.active = active
        applyMotion(animated: animated)
    }

    private func applyMotion(animated: Bool) {
        let mayAnimate = active && UKMotionVisibility.permitsAnimation(in: self)
        if active {
            for (index, view) in animatedViews.enumerated() {
                if mayAnimate && animated {
                    UKFadeIn.fadeIn(view, rises: false, delay: Double(index) * FirstRunMotion.rowStaggerSeconds)
                } else {
                    UKFadeIn.finishAnimations(in: view)
                    view.alpha = 1
                }
            }
        } else {
            animatedViews.forEach { UKFadeIn.finishAnimations(in: $0); $0.alpha = 1 }
        }
        updatePulse(allowed: mayAnimate)
        updateRotation(allowed: mayAnimate)
        refreshCatalogueLoad()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            catalogTask?.cancel()
            catalogTask = nil
            catalogueToken = UUID()
            removeEmbeddedControllers()
        }
        let needsEmbeddedController = [
            "songs-sort", "songs-filter", "suggestions-global-filter",
            "suggestions-instrument-filter", "playerhistory-sort",
        ].contains(slideID)
        if window != nil, embeddedControllers.isEmpty, needsEmbeddedController {
            render()
        }
        applyMotion(animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(1, bounds.width - 24)
        let category = traitCollection.preferredContentSizeCategory
        guard abs(width - lastSongRowWidth) > 0.5 || category != lastSongRowCategory else { return }
        lastSongRowWidth = width
        lastSongRowCategory = category
        for (row, input) in responsiveSongRows {
            row.configure(input, width: width, traits: traitCollection)
        }
    }

    // MARK: Rendering

    private func render() {
        removeEmbeddedControllers()
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        animatedViews = []
        pulseView = nil
        responsiveSongRows = []
        renderedFamily = Self.family(for: slideID)
        switch renderedFamily {
        case .songs:
            renderSongs()
        case .songsSort:
            renderSongsSort()
        case .songsNavigation:
            renderNavigationPreview()
        case .songsFilter:
            renderSongsFilter()
        case .songInfoChart:
            renderChart()
        case .songInfoScores:
            renderScoreRows()
        case .playerHistory:
            if slideID == "playerhistory-sort" {
                renderPlayerHistorySort()
            } else {
                renderScoreRows()
            }
        case .songInfoPaths:
            renderPaths()
        case .songInfoShop:
            renderShopAction()
        case .statistics:
            if slideID == "statistics-select-profile" {
                renderProfile()
            } else if slideID == "statistics-top-songs" {
                renderSongs()
            } else {
                renderStats()
            }
        case .suggestions:
            if slideID == "suggestions-category-card" {
                renderSuggestionCategory(FirstRunDemoSongs.placeholders(count: 2))
            } else if slideID == "suggestions-global-filter" || slideID == "suggestions-instrument-filter" {
                renderSuggestionsFilter()
            } else {
                renderSuggestions()
            }
        case .leaderboards:
            if slideID == "leaderboards-experimental-metrics" {
                renderControlPreview(title: "Rank By", options: ["Score", "Adjusted", "FC Rate"])
            } else {
                renderRankings()
            }
        case .compete:
            if slideID == "compete-rivals" || (slideID == "compete-hub" && rotationIndex % 2 == 1) {
                renderRivals()
            } else {
                renderRankings()
            }
        case .rivals:
            renderRivals()
        case .shop:
            if slideID == "shop-overview" {
                renderShopGrid()
            } else {
                renderSongs()
            }
        case .generic:
            renderGeneric()
        }
        hasRenderedContent = !content.arrangedSubviews.isEmpty
        catalogTask?.cancel()
        catalogTask = nil
        catalogueToken = UUID()
        guard usesCatalogueSongs else {
            setActive(active, animated: false)
            return
        }

        if !cachedSongs.isEmpty {
            replaceSongRows(rowRotation?.rows ?? Array(cachedSongs.prefix(songCount)))
        } else {
            refreshCatalogueLoad()
        }
    }

    private func removeEmbeddedControllers() {
        for controller in embeddedControllers {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        embeddedControllers.removeAll()
        embeddedControllerNames.removeAll()
    }

    private func embed(_ controller: UIViewController, height: CGFloat = 260) -> Bool {
        guard let parent = nearestViewController() else { return false }
        parent.addChild(controller)
        controller.loadViewIfNeeded()
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.clipsToBounds = true
        holder.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.isUserInteractionEnabled = false
        controller.view.isAccessibilityElement = false
        controller.view.accessibilityElementsHidden = true
        func hideAccessibility(_ view: UIView) {
            view.accessibilityElementsHidden = true
            view.subviews.forEach(hideAccessibility)
        }
        hideAccessibility(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: holder.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            holder.heightAnchor.constraint(equalToConstant: height),
        ])
        content.addArrangedSubview(holder)
        controller.didMove(toParent: parent)
        embeddedControllers.append(controller)
        embeddedControllerNames.append(String(describing: type(of: controller)))
        animatedViews.append(holder)
        return true
    }

    private func renderSongsSort() {
        let controller = UKSongsSortSheetController(
            mode: .title, ascending: true, modes: SongSortMode.catalogueModes,
            identifier: "fst.first-run.songs.sort"
        ) { _, _ in }
        guard embed(controller) else {
            renderControlPreview(title: "Sort Songs", options: SongSortMode.catalogueModes.map(\.label))
            return
        }
    }

    private func renderSongsFilter() {
        let inputs = UKSongsFilterSheetController.Inputs(
            appliedGeneral: SongGeneralFilter(),
            showShop: false,
            shopAvailable: false,
            availableDecades: [2010, 2020],
            availableDurations: [120, 180, 240],
            appliedPlayerFilter: SongPlayerScoreFilter(),
            appliedInstrument: nil,
            visibleInstruments: Set(Instrument.allCases),
            selectedPlayer: false,
            scoreAvailable: false,
            invalidScoreFilteringEnabled: false,
            availableSeasons: []
        )
        let controller = UKSongsFilterSheetController(inputs) { _, _, _ in }
        guard embed(controller) else {
            renderControlPreview(title: "Filter Songs", options: ["Year", "Duration", "Item Shop"])
            return
        }
    }

    private func renderSuggestionsFilter() {
        let controller = UKSuggestionsFilterViewController(
            applied: .defaults(), visibleInstruments: Array(Instrument.allCases)
        ) { _ in }
        guard embed(controller) else {
            renderControlPreview(title: "Filter Suggestions", options: ["All", "Instrument", "Category"])
            return
        }
    }

    private func renderPlayerHistorySort() {
        let controller = UKPlayerHistorySortViewController(
            mode: .date, ascending: false
        ) { _, _ in }
        guard embed(controller) else {
            renderControlPreview(title: "Sort Score History", options: ["Date", "Score", "Accuracy", "Season"])
            return
        }
    }

    private var catalogueVisible: Bool {
        guard active, let window, let scene = window.windowScene else { return false }
        return scene.activationState == .foregroundActive
    }

    private func refreshCatalogueLoad() {
        guard usesCatalogueSongs else { return }
        guard catalogueVisible else {
            catalogTask?.cancel()
            catalogTask = nil
            return
        }
        guard cachedSongs.isEmpty, catalogTask == nil, let session else { return }
        let token = UUID()
        catalogueToken = token
        catalogTask = Task { [weak self, weak session] in
            guard let session, let payload = try? await session.catalog() else {
                if self?.catalogueToken == token { self?.catalogTask = nil }
                return
            }
            let preferred: [String]
            if self?.slideID.contains("shop") == true,
               let shop = session.currentShop,
               shop.observedPublicationId == payload.observedPublicationId {
                preferred = shop.sortedSongs.map(\.songId)
            } else {
                preferred = []
            }
            let songs = FirstRunDemoSongs.pick(
                from: payload.catalog.songs,
                count: self?.songPoolCount ?? 3,
                preferring: preferred
            )
            guard !songs.isEmpty, !Task.isCancelled, let self, self.catalogueToken == token,
                  self.catalogueVisible else {
                if self?.catalogueToken == token { self?.catalogTask = nil }
                return
            }
            self.cachedSongs = songs
            if self.rotatingSongDemo {
                self.rowRotation = FirstRunRowRotation(pool: songs, visible: self.songCount)
            }
            self.catalogTask = nil
            self.replaceSongRows(self.rowRotation?.rows ?? songs)
        }
    }

    private var songCount: Int {
        switch slideID {
        case "shop-overview": 6
        case "statistics-top-songs": 4
        case "suggestions-category-card": 2
        default: 3
        }
    }

    private var rotatingSongDemo: Bool {
        [
            "songs-song-list", "songs-icons", "songs-metadata", "statistics-top-songs",
            "suggestions-category-card",
        ].contains(slideID)
    }

    private var songPoolCount: Int {
        rotatingSongDemo ? max(songCount, 24) : songCount
    }

    private var usesCatalogueSongs: Bool {
        switch slideID {
        case "songs-song-list", "songs-icons", "songs-metadata", "songs-shop-highlight",
             "songs-new-in-shop", "songs-leaving-tomorrow", "statistics-top-songs",
             "suggestions-category-card", "shop-overview", "shop-highlighting", "shop-new-items",
             "shop-leaving-tomorrow":
            true
        default: false
        }
    }

    private func renderSongs() {
        let rows = FirstRunDemoSongs.placeholders(count: songCount)
        for (index, song) in rows.enumerated() {
            let row = songRow(song, index: index)
            content.addArrangedSubview(row)
            animatedViews.append(row)
        }
        addPulse(to: content.arrangedSubviews.first)
    }

    private func replaceSongRows(_ songs: [Song]) {
        guard window != nil else { return }
        if renderedFamily == .suggestions, slideID == "suggestions-category-card" {
            renderSuggestionCategory(songs)
            return
        }
        if renderedFamily == .shop, slideID == "shop-overview" {
            renderShopGrid(songs)
            return
        }
        let old = content.arrangedSubviews
        old.forEach { $0.removeFromSuperview() }
        animatedViews = []
        responsiveSongRows = []
        for (index, song) in songs.enumerated() {
            let row = songRow(song, index: index)
            content.addArrangedSubview(row)
            animatedViews.append(row)
        }
        setActive(active, animated: true)
    }

    private func songRow(_ song: Song, index: Int) -> UIView {
        if let session {
            let row = UKSongRowView()
            let highlight: ShopHighlight? = slideID.contains("leaving")
                ? .leavingTomorrow : (slideID.contains("new") ? .new : nil)
            let input = UKSongRowInput(
                song: song, instrument: .lead, session: session,
                showInstrumentIcons: slideID.contains("icons"),
                shopOffer: slideID.contains("shop")
                    ? SongRowShopOffer(highlight: highlight, navigable: false, reservesBag: true)
                    : nil
            )
            row.configure(input, width: max(1, bounds.width - 24), traits: traitCollection)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
            responsiveSongRows.append((row, input))
            return row
        }
        let card = UKCardView(cornerRadius: 10)
        let art = UIView()
        art.translatesAutoresizingMaskIntoConstraints = false
        art.backgroundColor = song.isFirstRunPlaceholder
            ? BrandUIColors.surfaceMuted
            : BrandUIColors.accentBlue.withAlphaComponent(0.35)
        art.layer.cornerRadius = 7
        let title = UKLabel(song.isFirstRunPlaceholder ? "Song title" : song.title, style: .subheadline, weight: .semibold)
        let detail = UKLabel(
            song.isFirstRunPlaceholder ? "Artist · Year" : "\(song.artist) · \(song.year.map(String.init) ?? "Year")",
            style: .caption1, color: BrandUIColors.textMuted
        )
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 2
        let trailing: UIView
        if slideID.contains("icons") {
            trailing = UIStackView(arrangedSubviews: [
                UKInstrumentIconView(.lead, size: 18, hidesFromAccessibility: true),
                UKInstrumentIconView(.bass, size: 18, hidesFromAccessibility: true),
            ])
        } else if slideID.contains("shop") {
            trailing = badge(slideID.contains("leaving") ? "Leaving" : slideID.contains("new") ? "New" : "In Shop")
        } else {
            trailing = UKLabel("\(index + 1)", style: .caption1, weight: .semibold, color: BrandUIColors.accentBlue)
        }
        let row = UIStackView(arrangedSubviews: [art, text, trailing])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        art.widthAnchor.constraint(equalToConstant: 38).isActive = true
        art.heightAnchor.constraint(equalToConstant: 38).isActive = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        card.embed(row, insets: UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8))
        return card
    }

    private func renderControlPreview(title: String, options: [String]) {
        content.addArrangedSubview(UKLabel(title, style: .headline, weight: .semibold))
        for option in options {
            var configuration = UIButton.Configuration.plain()
            configuration.title = option
            configuration.baseForegroundColor = BrandUIColors.textPrimary
            configuration.image = UIImage(systemName: option == options.first ? "checkmark" : "circle")
            configuration.imagePadding = 8
            let button = UIButton(configuration: configuration)
            button.isUserInteractionEnabled = false
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            content.addArrangedSubview(button)
            animatedViews.append(button)
        }
    }

    private func renderNavigationPreview() {
        // The shell's UITabBar is the reusable native navigation primitive; embedding a
        // second UKRootViewController would own live stacks and violate the inert-demo rule.
        let bar = UITabBar()
        bar.items = ["Songs", "Suggestions", "Leaderboards", "Settings"].enumerated().map { index, title in
            let item = UITabBarItem(title: title, image: UIImage(systemName: ["music.note.list", "sparkles", "trophy", "gearshape"][index]), tag: index)
            return item
        }
        bar.selectedItem = bar.items?.first
        bar.heightAnchor.constraint(equalToConstant: 52).isActive = true
        content.addArrangedSubview(bar)
        animatedViews = [bar]
    }

    private func renderChart() {
        let chart = UKScoreHistoryChartView(
            rows: FirstRunDemoPool.ownHistory, instrument: .lead, chartWidth: 320,
            reservesPager: false, currentSeason: nil
        )
        content.addArrangedSubview(chart)
        chart.heightAnchor.constraint(equalToConstant: 170).isActive = true
        animatedViews = [chart]
    }

    private func renderScoreRows() {
        if renderedFamily == .playerHistory {
            for (index, entry) in FirstRunDemoPool.ownHistory.enumerated() {
                let row = UKScoreHistoryRowView(
                    entry: entry, isBest: index == 0, seasonColumn: false, currentSeason: nil,
                    grouped: false, scoreTemplate: "486500"
                )
                content.addArrangedSubview(row)
                animatedViews.append(row)
            }
            return
        }
        let entries = slideID.contains("top-scores") ? FirstRunDemoPool.topScores.map { ($0.name, "\($0.score)") } :
            FirstRunDemoPool.ownScores.map { ($0.name, "\($0.score)") }
        for (index, entry) in entries.prefix(4).enumerated() {
            let row = metricRow(rank: index + 1, title: entry.0, value: entry.1)
            content.addArrangedSubview(row)
            animatedViews.append(row)
        }
        addPulse(to: content.arrangedSubviews.last)
    }

    private func renderPaths() {
        // UKSongPathsViewController is the reusable full viewer, but it owns path-artifact
        // reads. The first-run contract forbids live API loads, so this remains a native,
        // inert selector preview until a selector-only UIKit component exists.
        let selector = UIStackView(arrangedSubviews: [
            selectorRow("Instrument", "Lead", "music.note"),
            selectorRow("Difficulty", "Expert", "dial.medium"),
            selectorRow("View", "Image", "photo"),
        ])
        selector.axis = .horizontal
        selector.distribution = .fillEqually
        selector.spacing = 6
        content.addArrangedSubview(selector)
        let path = UIView()
        path.backgroundColor = BrandUIColors.surfaceMuted
        path.layer.cornerRadius = 10
        path.heightAnchor.constraint(equalToConstant: 120).isActive = true
        content.addArrangedSubview(path)
        animatedViews = [selector, path]
    }

    private func renderShopAction() {
        let row = UIStackView(arrangedSubviews: [
            UKLabel("Item Shop", style: .body, weight: .semibold),
            UIView(),
            badge(slideID.contains("leaving") ? "Leaving Tomorrow" : slideID.contains("new") ? "New" : "In Shop"),
        ])
        row.axis = .horizontal
        row.alignment = .center
        let card = UKCardView(cornerRadius: 12)
        card.embed(row, insets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        content.addArrangedSubview(card)
        addPulse(to: card)
        animatedViews = [card]
    }

    private func renderProfile() {
        let row = metricRow(rank: 0, title: "Select Player", value: "Choose a profile to compare scores")
        content.addArrangedSubview(row)
        addPulse(to: row)
        animatedViews = [row]
    }

    private func renderStats() {
        let values = FirstRunDemoPool.percentileBuckets.prefix(4).map { ("Top \($0.percent)%", "\($0.count)") }
        for (index, value) in values.enumerated() {
            let tile = metricRow(rank: index, title: value.0, value: value.1)
            content.addArrangedSubview(tile)
            animatedViews.append(tile)
        }
    }

    private func renderSuggestions() {
        let template = FirstRunSuggestionsCategoryCardDemo.templates[
            rotationIndex % FirstRunSuggestionsCategoryCardDemo.templates.count
        ]
        let title = UKLabel(
            slideID == "suggestions-category-card" ? template.title
                : (slideID.contains("instrument") ? "Filter by instrument" : "Suggested for you"),
            style: .headline, weight: .semibold
        )
        content.addArrangedSubview(title)
        if slideID == "suggestions-category-card" {
            content.addArrangedSubview(UKLabel(template.description, style: .caption1))
        }
        let categories = FirstRunSuggestionsCategoryCardDemo.scrollTemplates.map(\.title)
        for (index, category) in categories.prefix(3).enumerated() {
            let row = metricRow(rank: index, title: category, value: "\(index + 2) songs")
            content.addArrangedSubview(row)
            animatedViews.append(row)
        }
        addPulse(to: content.arrangedSubviews.first)
    }

    private func renderRankings() {
        let entries = slideID.contains("your-rank") ? FirstRunDemoPool.rankingNeighborhood : FirstRunDemoPool.rankings
        for (index, entry) in entries.prefix(5).enumerated() {
            let row = metricRow(rank: entry.rank, title: entry.name, value: entry.rating, selected: entry.isPlayer)
            content.addArrangedSubview(row)
            animatedViews.append(row)
            _ = index
        }
        addPulse(to: content.arrangedSubviews.last)
    }

    private func renderRivals() {
        let offset = rotationIndex % max(1, FirstRunDemoPool.rivalsAbove.count - 1)
        let above = Array(FirstRunDemoPool.rivalsAbove[offset...].prefix(2))
        let below = Array(FirstRunDemoPool.rivalsBelow[offset...].prefix(2))
        let rivals = above + below
        for (index, rival) in rivals.enumerated() {
            let row = metricRow(
                rank: index, title: rival.name, value: "\(rival.shared) shared", selected: false
            )
            content.addArrangedSubview(row)
            animatedViews.append(row)
        }
    }

    private func renderShopGrid() {
        renderShopGrid(FirstRunDemoSongs.placeholders(count: 6))
    }

    private func renderShopGrid(_ songs: [Song]) {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        animatedViews = []
        let rows = stride(from: 0, to: songs.count, by: 3).map {
            Array(songs[$0..<min($0 + 3, songs.count)])
        }
        for rowSongs in rows {
            let row = UIStackView(arrangedSubviews: rowSongs.map { songTile($0) })
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 6
            content.addArrangedSubview(row)
            animatedViews.append(row)
        }
    }

    private func renderSuggestionCategory(_ songs: [Song]) {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        animatedViews = []
        let template = FirstRunSuggestionsCategoryCardDemo.templates[
            rotationIndex % FirstRunSuggestionsCategoryCardDemo.templates.count
        ]
        if let session {
            let category = template.category(songs)
            let card = UKSuggestionCardView(
                category: category,
                context: UKContext(session: session),
                currentSeason: session.catalogCurrentSeason,
                visibleInstruments: Set(Instrument.allCases)
            )
            content.addArrangedSubview(card)
            animatedViews = [card]
        } else {
            content.addArrangedSubview(UKLabel(template.title, style: .headline, weight: .semibold))
            content.addArrangedSubview(UKLabel(template.description, style: .caption1))
            for (index, song) in songs.prefix(2).enumerated() {
                let row = songRow(song, index: index)
                content.addArrangedSubview(row)
                animatedViews.append(row)
            }
        }
    }

    private func songTile(_ song: Song) -> UIView {
        let tile = UKCardView(cornerRadius: 8)
        let art: UIView
        if let session, !song.isFirstRunPlaceholder {
            let artwork = UKArtworkTileView(size: 48)
            artwork.configure(raw: song.albumArt, session: session)
            art = artwork
        } else {
            let placeholder = UIView()
            placeholder.backgroundColor = song.isFirstRunPlaceholder
                ? BrandUIColors.surfaceMuted : BrandUIColors.accentPurple.withAlphaComponent(0.35)
            placeholder.layer.cornerRadius = 6
            art = placeholder
        }
        art.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let label = UKLabel(song.isFirstRunPlaceholder ? "Song" : song.title, style: .caption2, lines: 2)
        let stack = UIStackView(arrangedSubviews: [art, label])
        stack.axis = .vertical
        stack.spacing = 4
        tile.embed(stack, insets: UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6))
        return tile
    }

    private func renderGeneric() {
        let row = metricRow(rank: 0, title: "Festival Score Tracker", value: "Explore this feature")
        content.addArrangedSubview(row)
        animatedViews = [row]
    }

    private func metricRow(rank: Int, title: String, value: String, selected: Bool = false) -> UIView {
        let row = UIStackView(arrangedSubviews: [
            UKLabel(rank > 0 ? "\(rank)" : "", style: .caption1, weight: .bold, color: selected ? BrandUIColors.accentPurple : BrandUIColors.textMuted),
            UKLabel(title, style: .subheadline, weight: .semibold),
            UIView(),
            UKLabel(value, style: .caption1, weight: .semibold, color: BrandUIColors.textMuted),
        ])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        let card = UKCardView(cornerRadius: 10)
        card.backgroundColor = selected ? BrandUIColors.accentPurple.withAlphaComponent(0.22) : BrandUIColors.surfaceMuted
        card.embed(row, insets: UIEdgeInsets(top: 7, left: 9, bottom: 7, right: 9))
        return card
    }

    private func selectorRow(_ title: String, _ value: String, _ symbol: String) -> UIView {
        let button = UIButton(type: .system)
        button.isUserInteractionEnabled = false
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.setTitle(" \(value)", for: .normal)
        button.tintColor = BrandUIColors.accentBlue
        button.setTitleColor(BrandUIColors.textPrimary, for: .normal)
        button.titleLabel?.font = UKFont.font(.caption1, weight: .semibold)
        button.accessibilityLabel = "\(title), \(value)"
        return button
    }

    private func badge(_ title: String) -> UIView {
        let label = UKLabel(title, style: .caption2, weight: .semibold, color: BrandUIColors.textPrimary, lines: 1)
        let pill = UIView()
        pill.backgroundColor = BrandUIColors.statusGreen.withAlphaComponent(0.7)
        pill.layer.cornerRadius = 8
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -3),
        ])
        return pill
    }

    private func addPulse(to view: UIView?) {
        guard let view else { return }
        let pulse = UIView()
        pulse.isUserInteractionEnabled = false
        pulse.backgroundColor = .clear
        pulse.layer.borderColor = BrandUIColors.accentBlue.cgColor
        pulse.layer.borderWidth = 2
        pulse.layer.cornerRadius = 10
        pulse.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pulse)
        NSLayoutConstraint.activate([
            pulse.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pulse.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pulse.topAnchor.constraint(equalTo: view.topAnchor),
            pulse.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        pulseView = pulse
    }

    private func updatePulse(allowed: Bool) {
        guard let pulse = pulseView else { return }
        pulse.layer.removeAllAnimations()
        let shouldRun = allowed && active && window != nil
        if shouldRun {
            pulse.alpha = 0.7
            UIView.animate(
                withDuration: ShopRowPulseBorder.period / 2,
                delay: 0,
                options: [.autoreverse, .repeat, .allowUserInteraction, .curveEaseInOut]
            ) { pulse.alpha = 0 }
        } else {
            pulse.alpha = 0.7
        }
    }
}
#endif
