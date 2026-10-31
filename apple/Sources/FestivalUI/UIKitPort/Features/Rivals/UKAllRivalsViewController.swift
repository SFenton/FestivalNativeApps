#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - All Rivals

/// `/rivals/all`: the full rival list for one scope (``AllRivalsScreen``): a leading
/// in-list title (pinned to the bar once it scrolls away) over one material card of every
/// rival, with the page's loading, failure, empty and unknown-category states.
final class UKAllRivalsViewController: UKRivalsPageViewController {
    private struct Row {
        let accountId: String
        let displayName: String?
        let behindCount: Int
        let aheadCount: Int
        let direction: RivalDirection

        init<Rival: RivalRowDisplayable>(_ rival: Rival, direction: RivalDirection) {
            accountId = rival.accountId
            displayName = rival.displayName
            behindCount = rival.behindCount
            aheadCount = rival.aheadCount
            self.direction = direction
        }
    }

    private let routeScope: RivalScope

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - context: The context it was created in.
    ///   - scope: The scope the route carried.
    init(context: UKContext, scope: RivalScope) {
        routeScope = scope
        super.init(context: context)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var experimentalRanks: Bool { UKSettings.bool(ExperimentalRanks.storageKey, default: ExperimentalRanks.defaultValue) }
    override var settingsSignature: AnyHashable { experimentalRanks }
    private var scope: RivalScope { routeScope.coerced(experimentalRanks: experimentalRanks) }

    override func build() {
        let scope = scope
        let title = AllRivalsScreen.title(for: scope)
        ukSetPageTitle(title, mode: .inline)
        setPinnedTitle(
            instrument: AllRivalsScreen.titleInstrument(for: scope), title: title,
            pinnedIdentifier: "fst.all-rivals.pinned-title"
        )
        if session.selectedPlayer == nil {
            showChooseProfile()
            return
        }
        let instruments = AllRivalsScreen.instruments(for: scope)
        guard !instruments.isEmpty else {
            showEmpty("Unknown Category", systemImage: "questionmark.circle", subtitle: "This rivals list could not be identified.")
            return
        }
        load(scope: scope, instruments: instruments, title: title)
    }

    private func load(scope: RivalScope, instruments: [Instrument], title: String) {
        showLoading("Loading rivals")
        runTask { [weak self] in
            guard let self else { return }
            do {
                let rows = try await Self.rows(session: self.session, scope: scope, instruments: instruments)
                guard !Task.isCancelled else { return }
                self.show(rows, scope: scope, title: title)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus(ServiceIssue(error), title: "Rivals Unavailable", scope: nil) { [weak self] in
                    self?.load(scope: scope, instruments: instruments, title: title)
                }
            }
        }
    }

    /// The scope's rivals, above rivals first.
    private static func rows(session: FestivalSession, scope: RivalScope, instruments: [Instrument]) async throws -> [Row] {
        func make<Rival: RivalRowDisplayable>(_ above: [Rival], _ below: [Rival]) -> [Row] {
            above.map { Row($0, direction: .above) } + below.map { Row($0, direction: .below) }
        }
        switch scope {
        case .song where AllRivalsScreen.isCommon(scope):
            var lists: [RivalsListResponse] = []
            for instrument in instruments {
                if let list = try? await session.rivalsList(instrument: instrument) { lists.append(list) }
            }
            let result = RivalCommonRivals.intersect(lists)
            return make(result.above, result.below)
        case .song:
            guard let instrument = instruments.first else { return [] }
            let response = try await session.rivalsList(instrument: instrument)
            return make(response.above, response.below)
        case let .leaderboard(_, rankBy):
            guard let instrument = instruments.first else { return [] }
            let response = try await session.leaderboardRivals(instrument: instrument, rankBy: rankBy)
            return make(response.above, response.below)
        case let .combo(token, _):
            let response = try await session.rivalsComboList(token: token)
            return make(response.above, response.below)
        }
    }

    private func show(_ rows: [Row], scope: RivalScope, title: String) {
        guard !rows.isEmpty else {
            showEmpty("No Rivals Yet", systemImage: "person.2.slash", subtitle: "No rivals have been found for this scope yet.")
            return
        }
        showScroll()
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        column.spacing = 12
        let hero = makeHeroTitle(
            instrument: AllRivalsScreen.titleInstrument(for: scope), title: title,
            identifier: "fst.all-rivals.title", pinnedIdentifier: "fst.all-rivals.pinned-title"
        )
        add(hero)
        UKFadeIn.fadeIn(hero)
        let group = UKGroupSectionView()
        let context = context
        group.setRows(rows.map { row in
            let view = UKRivalRowView(
                displayName: row.displayName, behindCount: row.behindCount, aheadCount: row.aheadCount,
                direction: row.direction, identifier: "fst.all-rivals.row.\(row.accountId)"
            )
            let route = AppRoute.rivalDetail(rivalId: row.accountId, name: row.displayName, scope: scope)
            view.onSelect = { [weak navigator = context.navigator] in navigator?.selectDetail(route) }
            return view
        })
        let padded = group.ukPadded()
        add(padded)
        UKFadeIn.fadeIn(padded)
    }

    override var columnInsets: (top: CGFloat, bottom: CGFloat) { (12, 12) }
}
#endif
