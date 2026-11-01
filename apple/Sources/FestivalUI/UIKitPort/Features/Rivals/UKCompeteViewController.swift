#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Compete ranking row

// MARK: - Compete

/// `/compete`: the hub combining Leaderboards and Rivals (``CompeteScreen``). The whole page
/// loads behind one spinner (``CompeteHubModel``), then its headers and cards fade in on one
/// stagger: a Leaderboards section (a Top 5 preview per ranking scope, the player's own row
/// under it when they rank lower) and a Rivals section (one rivals card per scope). At regular
/// width the two sections sit side by side, split at an iPhone Duo fold.
///
/// The Duo dual-source layout (``CompeteDualSource``) is shelved with ``DualSourcePolicy``, so
/// this page only draws the stacked and side-by-side hubs.
final class UKCompeteViewController: UKRivalsPageViewController {
    private let model = CompeteHubModel()
    private var gate: UKReloadGate?
    private var key: CompetePageLoadKey?
    private var revealed = false

    override var columnInsets: (top: CGFloat, bottom: CGFloat) { (12, 12) }
    override var columnSpacing: CGFloat { 24 }

    /// Creates the page.
    ///
    /// - Parameter context: The context it was created in.
    override init(context: UKContext) {
        super.init(context: context)
        ukSetPageTitle("Compete")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var settingsSignature: AnyHashable { UKRivalsInstruments.visible() }

    override func build() {
        guard session.selectedPlayer != nil else {
            showChooseProfile()
            return
        }
        makeQuickLinks()
        let key = CompetePageLoadKey(instruments: UKRivalsInstruments.visible(), session: session)
        self.key = key
        revealed = false
        let gate = UKReloadGate(
            key: key, isLoading: model.isLoading(for: key), spinnerLabel: "Loading Compete", spinnerIdentifier: "fst.compete.loading"
        )
        self.gate = gate
        gate.onReveal = { [weak self] in self?.revealPage() }
        showFill(gate, edgeToEdge: true)
        scrollView.isHidden = true
        gate.contentView.addSubview(scrollView)
        scrollView.ukPin(to: gate.contentView)
        let model = model
        let session = session
        runTask { [weak self] in
            await model.load(key, session: session)
            self?.loadSettled()
        }
        observations.observe { [weak self] in
            guard let self, let key = self.key else { return }
            let loading = self.model.isLoading(for: key)
            self.gate?.update(key: key, isLoading: loading)
            if !loading, self.revealed { self.render() }
        }
    }

    private func loadSettled() {
        guard let key else { return }
        gate?.update(key: key, isLoading: model.isLoading(for: key))
    }

    private func revealPage() {
        revealed = true
        render()
    }

    private func retry() {
        guard let key else { return }
        let model = model
        let session = session
        runTask { await model.load(key, session: session) }
    }

    // MARK: Render

    private func render() {
        guard let key else { return }
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        clearQuickLinks()
        if let issue = model.fullPageIssue(for: key) {
            // Web: every leaderboard failing shows one page-wide error.
            scrollView.isHidden = true
            let status = UKServiceStatusView(issue, title: "Compete unavailable", scope: "compete") { [weak self] in self?.retry() }
            status.translatesAutoresizingMaskIntoConstraints = false
            gate?.contentView.addSubview(status)
            status.ukPin(to: gate!.contentView)
            return
        }
        scrollView.isHidden = false
        needsInitialOffset = true
        let leaderboards = leaderboardsSection(key)
        let rivals = rivalsSection(key)
        let wide = ukLayout.widthClass == .regular
        if wide {
            let row = UIStackView(arrangedSubviews: [leaderboards, rivals])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .top
            row.distribution = .fillEqually
            add(row)
        } else {
            add(leaderboards)
            add(rivals)
        }
        registerQuickLink(QuickLinkSection(id: "leaderboards", title: "Leaderboards", icon: .system("trophy.fill")), view: leaderboards)
        registerQuickLink(QuickLinkSection(id: "rivals", title: "Rivals", icon: .system("person.2.fill")), view: rivals)
    }

    private func sectionHeader(_ title: String, index: Int) -> UIView {
        let header = UKSectionHeaderView(title)
        let padded = header.ukPadded()
        UKFadeIn.fadeIn(padded, staggerIndex: index)
        return padded
    }

    private func leaderboardsSection(_ key: CompetePageLoadKey) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(sectionHeader("Leaderboards", index: 0))
        if key.instruments.isEmpty {
            let note = UKFootnoteLabel("Enable at least one instrument in Settings to see leaderboards.").ukPadded()
            stack.addArrangedSubview(note)
            UKFadeIn.fadeIn(note, staggerIndex: 1)
        } else {
            for (offset, scope) in key.scopes.enumerated() {
                let card = leaderboardCard(scope: scope, index: 1 + offset)
                stack.addArrangedSubview(card)
            }
        }
        return stack
    }

    private func rivalsSection(_ key: CompetePageLoadKey) -> UIView {
        let header = key.scopes.count + 1
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(sectionHeader("Rivals", index: header))
        if key.instruments.isEmpty {
            let note = UKFootnoteLabel("Enable at least one instrument in Settings to see rivals.").ukPadded()
            stack.addArrangedSubview(note)
            UKFadeIn.fadeIn(note, staggerIndex: header + 1)
        } else {
            for (offset, scope) in key.scopes.enumerated() {
                let state = model.rivals[scope] ?? .loading
                if let card = UKRivalCards.songCard(
                    scope: scope, state: state, emptyMessage: "No rivals found for \(scope.label) yet.", context: context,
                    retry: { [weak self] in self?.retry() }
                ) {
                    stack.addArrangedSubview(card)
                    UKFadeIn.fadeIn(card, staggerIndex: header + 1 + offset)
                }
            }
        }
        return stack
    }

    // MARK: Leaderboard preview card

    private func isSelected(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }

    private func fullBoardRoute(_ scope: RankingScope) -> AppRoute {
        switch scope {
        case let .instrument(instrument): .fullRankings(instrument: instrument, rankBy: CompetePreviewSpotlight.metric.rawValue)
        case let .combo(combo): .fullComboRankings(combo: combo, rankBy: CompetePreviewSpotlight.metric.rawValue)
        }
    }

    private func leaderboardCard(scope: RankingScope, index: Int) -> UIView {
        let header = UKInstrumentSectionHeaderView(scope: scope)
        let state = model.boards[scope] ?? .loading
        let body: UIView
        switch state {
        case .loading:
            // Not reached: the page gate shows one spinner until every read settles.
            body = UIView()
        case let .failed(issue):
            body = noteCard(UKServiceStatusInlineView(issue, scope: "compete.\(scope.id)") { [weak self] in self?.retry() })
        case let .loaded(payload) where payload.rankings.entries.isEmpty:
            body = noteCard(UKFootnoteLabel("No ranked \(scope.label) players yet."))
        case let .loaded(payload):
            body = boardCard(scope: scope, payload: payload)
        }
        let stack = UIStackView(arrangedSubviews: [header, body])
        stack.axis = .vertical
        stack.spacing = 8
        let padded = stack.ukPadded()
        padded.isAccessibilityElement = false
        padded.accessibilityIdentifier = "fst.compete.leaderboard-card.\(scope.id)"
        UKFadeIn.fadeIn(padded, staggerIndex: index)
        return padded
    }

    private func noteCard(_ content: UIView) -> UIView {
        let card = UKCardView(cornerRadius: 12)
        card.embed(content, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        return card
    }

    private func boardCard(scope: RankingScope, payload: RankingsPayload) -> UIView {
        let spotlight = model.spotlights[scope]
        let entries = payload.rankings.entries
        let cardRows = entries + (spotlight.map { [$0] } ?? [])
        let metric = CompetePreviewSpotlight.metric
        let columns = UKRankingRowModels.fittingSongs(
            LeaderboardRowColumns.rankings(cardRows, metric: metric),
            names: cardRows.map { RankingRowName(name: AccountRankingRow.displayName($0), emphasized: isSelected($0.accountId)) },
            sectionWidth: max(view.bounds.width - 32, 0), rowInset: 0, pageColumns: 1, traits: traitCollection
        )
        let group = UKGroupSectionView(rows: .flush(separatorInset: UKLeaderboardMetrics.horizontalPadding))
        var rows: [UIView] = entries.map { entry in
            let content = UKRankingRowView()
            content.apply(UKRankingRowModels.account(entry: entry, metric: metric, isSelected: isSelected(entry.accountId), columns: columns))
            return UKCardRowControl(content: content, selectedBand: isSelected(entry.accountId), onTap: entry.hasAccount ? { [weak navigator = context.navigator] in
                navigator?.selectDetail(AccountRankingRow.route(entry))
            } : nil)
        }
        if let spotlight {
            var spotlightModel = UKRankingRowModels.account(entry: spotlight, metric: metric, isSelected: true, columns: columns, opensProfile: false)
            spotlightModel.identifier = "fst.compete.leaderboard-card.\(scope.id).spotlight"
            spotlightModel.opensSomething = true
            spotlightModel.spokenOverride = CompetePreviewSpotlight.action(for: spotlight)
                .footerLabel(for: .player, rank: spotlight.rank(for: metric))
            let content = UKRankingRowView()
            content.apply(spotlightModel)
            rows.append(UKCardRowControl(content: content, selectedBand: true, onTap: { [weak navigator = context.navigator] in
                navigator?.selectDetail(CompetePreviewSpotlight.route(for: spotlight, scope: scope))
            }))
        }
        group.setRows(rows)
        group.setAction(UKPurpleActionButton(
            title: "View Full Leaderboard", card: scope.label, identifier: "fst.compete.leaderboard-card.\(scope.id).view-all"
        ) { [weak navigator = context.navigator, route = fullBoardRoute(scope)] in navigator?.push(route) })
        return group
    }
}
#endif
