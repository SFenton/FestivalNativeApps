#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Rival comparison base

/// What Rival Detail and Rivalry share (``RivalDetailScreen``, ``RivalryScreen``): the rival,
/// the scope (coerced while Experimental Ranks is off), the rival-detail read with the
/// catalogue lookup that lets a song row open its song, the song rows and the View Profile tool.
class UKRivalComparisonViewController: UKRivalsPageViewController {
    /// The rival's account id.
    let rivalId: String
    /// The rival's name from the route.
    let routeName: String?
    private let routeScope: RivalScope?
    /// The loaded detail, once read.
    private(set) var detail: RivalDetailResponse?
    private var songsById: [String: Song] = [:]
    private let profileIdentifier: String

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - context: The context it was created in.
    ///   - rivalId: Rival account id.
    ///   - name: Rival display name, if known.
    ///   - scope: Scope that produced the tapped row, or nil.
    ///   - profileIdentifier: Identifier of the View Profile tool.
    init(context: UKContext, rivalId: String, name: String?, scope: RivalScope?, profileIdentifier: String) {
        self.rivalId = rivalId
        self.routeName = name
        self.routeScope = scope
        self.profileIdentifier = profileIdentifier
        super.init(context: context)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var experimentalRanks: Bool { UKSettings.bool(ExperimentalRanks.storageKey, default: ExperimentalRanks.defaultValue) }
    override var settingsSignature: AnyHashable { experimentalRanks }

    /// The scope in effect.
    var scope: RivalScope? { routeScope?.coerced(experimentalRanks: experimentalRanks) }

    /// The rival's name: the loaded one, else the route's.
    var displayName: String? { detail?.rival.displayName ?? routeName }

    override var pageTools: [UKPageTool] {
        [Self.tool(title: "View Profile", symbol: "person.crop.circle", identifier: profileIdentifier) { [weak self] in
            guard let self else { return }
            self.context.navigator?.push(.player(accountId: self.rivalId, displayName: self.displayName))
        }]
    }

    /// Reads the rival detail and the catalogue lookup, then calls ``didLoad(_:)``.
    ///
    /// - Parameters:
    ///   - loadingLabel: Spoken label of the spinner.
    func loadDetail(loadingLabel: String) {
        showLoading(loadingLabel)
        let scope = scope
        let visible = UKRivalsInstruments.visible()
        runTask { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.session.rivalDetail(forScope: scope, rivalId: self.rivalId, visibleInstruments: visible)
                if let payload = try? await self.session.catalog() {
                    self.songsById = Dictionary(
                        payload.catalog.songs.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first }
                    )
                }
                guard !Task.isCancelled else { return }
                self.detail = response
                self.didLoad(response)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus(ServiceIssue(error), title: "Rivals Unavailable") { [weak self] in self?.loadDetail(loadingLabel: loadingLabel) }
            }
        }
    }

    /// Builds the loaded page. Subclasses override.
    func didLoad(_ detail: RivalDetailResponse) {}

    /// A song row; a button when the song is in the catalogue.
    ///
    /// - Parameters:
    ///   - song: The comparison.
    ///   - rivalName: The rival's display name.
    /// - Returns: The row.
    func songRow(_ song: RivalSongComparison, rivalName: String) -> UIView {
        let match = songsById[song.songId]
        let row = UKRivalSongRowView(
            song: song, albumArt: match?.albumArt, session: session,
            playerName: session.selectedPlayer?.displayName ?? "You", rivalName: rivalName, opensSong: match != nil
        )
        if let match {
            row.onSelect = { [weak navigator = context.navigator] in navigator?.push(.songDetail(match)) }
        }
        return row
    }
}

// MARK: - Rival Detail

/// `/rivals/:rivalId`: a themed breakdown of every shared song against one rival
/// (``RivalDetailScreen``): the rival's name over the list they belong to, then one card per
/// category (up to five songs, ending in View All), each with its own Quick Links entry.
final class UKRivalDetailViewController: UKRivalComparisonViewController {
    /// Creates the page.
    ///
    /// - Parameters:
    ///   - context: The context it was created in.
    ///   - rivalId: Rival account id.
    ///   - name: Rival display name, if known.
    ///   - scope: Scope that produced the tapped row, or nil.
    init(context: UKContext, rivalId: String, name: String?, scope: RivalScope?) {
        super.init(
            context: context, rivalId: rivalId, name: name, scope: scope, profileIdentifier: "fst.rival-detail.view-profile"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var columnInsets: (top: CGFloat, bottom: CGFloat) { (12, 12) }

    private var pageTitle: String { displayName ?? "Rival" }

    override func build() {
        ukSetPageTitle(pageTitle, mode: .inline)
        setPinnedTitle(
            instrument: nil, title: pageTitle, subtitle: RivalDetailScreen.subtitle(for: scope),
            subtitleInstrument: RivalDetailScreen.subtitleInstrument(for: scope), pinnedIdentifier: "fst.rival-detail.pinned-title"
        )
        guard session.selectedPlayer != nil else {
            showChooseProfile()
            return
        }
        makeQuickLinks()
        loadDetail(loadingLabel: "Loading rival detail")
    }

    override func didLoad(_ detail: RivalDetailResponse) {
        let categories = RivalCategorization.categorize(detail.songs)
        guard !categories.isEmpty else {
            showEmpty("No Shared Songs", systemImage: "music.note.list", subtitle: "You and this rival don't share any scored songs yet.")
            return
        }
        showScroll()
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        clearQuickLinks()
        column.spacing = 12
        ukSetPageTitle(pageTitle, mode: .inline)
        let scope = scope
        let rivalName = detail.rival.displayName ?? routeName ?? "Rival"
        let hero = makeHeroTitle(
            instrument: nil, title: pageTitle, subtitle: RivalDetailScreen.subtitle(for: scope),
            subtitleInstrument: RivalDetailScreen.subtitleInstrument(for: scope),
            identifier: "fst.rival-detail.title", pinnedIdentifier: "fst.rival-detail.pinned-title"
        )
        add(hero)
        UKFadeIn.fadeIn(hero)
        let cards = UIStackView()
        cards.axis = .vertical
        cards.spacing = 20
        add(cards)
        for (index, category) in categories.enumerated() {
            let group = UKGroupSectionView(category.title, subtitle: category.subtitle)
            group.setRows(category.songs.prefix(5).map { songRow($0, rivalName: rivalName) })
            group.setAction(UKPurpleActionButton(
                title: "View All", identifier: "fst.rival-detail.category.\(category.key).view-all", card: category.title
            ) { [weak self] in
                guard let self else { return }
                self.context.navigator?.push(.rivalry(rivalId: self.rivalId, mode: category.key, name: detail.rival.displayName ?? self.routeName, scope: scope))
            })
            let padded = group.ukPadded()
            cards.addArrangedSubview(padded)
            registerQuickLink(category.quickLinkSection, view: padded)
            UKFadeIn.fadeIn(padded, staggerIndex: index)
        }
    }
}

// MARK: - Rivalry

/// `/rivals/:rivalId/rivalry`: the full song list of one category (``RivalryScreen``), led by
/// the section name over the rival's name. One flat list, so no Quick Links.
final class UKRivalryViewController: UKRivalComparisonViewController {
    private let mode: String

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - context: The context it was created in.
    ///   - rivalId: Rival account id.
    ///   - mode: The category key.
    ///   - name: Rival display name, if known.
    ///   - scope: Scope forwarded from Rival Detail.
    init(context: UKContext, rivalId: String, mode: String, name: String?, scope: RivalScope?) {
        self.mode = mode
        super.init(context: context, rivalId: rivalId, name: name, scope: scope, profileIdentifier: "fst.rivalry.view-profile")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var columnInsets: (top: CGFloat, bottom: CGFloat) { (12, 12) }

    private var pageTitle: String { RivalryScreen.title(for: mode) }
    private var subtitle: String { RivalryScreen.subtitle(rivalName: displayName) }

    override func build() {
        ukSetPageTitle(pageTitle, mode: .inline)
        setPinnedTitle(instrument: nil, title: pageTitle, subtitle: subtitle, pinnedIdentifier: "fst.rivalry.pinned-title")
        guard session.selectedPlayer != nil else {
            showChooseProfile()
            return
        }
        loadDetail(loadingLabel: "Loading rivalry")
    }

    override func didLoad(_ detail: RivalDetailResponse) {
        guard let category = RivalCategorization.categorize(detail.songs).first(where: { $0.key == mode }), !category.songs.isEmpty else {
            showEmpty("No Songs", systemImage: "music.note.list", subtitle: "There are no songs in this category.")
            return
        }
        showScroll()
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        column.spacing = 12
        let hero = makeHeroTitle(
            instrument: nil, title: pageTitle, subtitle: subtitle, identifier: "fst.rivalry.title", pinnedIdentifier: "fst.rivalry.pinned-title"
        )
        add(hero)
        UKFadeIn.fadeIn(hero)
        let rivalName = detail.rival.displayName ?? routeName ?? "Rival"
        let group = UKGroupSectionView()
        group.setRows(category.songs.map { songRow($0, rivalName: rivalName) })
        let padded = group.ukPadded()
        add(padded)
        UKFadeIn.fadeIn(padded)
    }
}
#endif
