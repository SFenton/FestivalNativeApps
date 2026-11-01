#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Compete ranking row

/// One row of a Compete leaderboard preview (``AccountRankingRow``, lane-local until it
/// merges with the Leaderboards lane's shared row on `UKLeaderboardColumnSlot`): `#rank`, the
/// name as a marquee, the songs played/total column when the card has room, the accent-blue
/// rating and a chevron. The selected player's own row is bold on the purple band. At
/// accessibility sizes the columns stack (rank and name, then songs and rating).
final class UKCompeteRankingRow: UIControl {
    /// Padding inside the row.
    static let horizontalPadding: CGFloat = 14
    /// Spacing between the columns.
    static let columnSpacing: CGFloat = 10

    private let band = UIView()
    /// Called when the row is pressed.
    var onSelect: (() -> Void)?

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - entry: The ranking row.
    ///   - columns: The card's shared columns.
    ///   - isSelected: The selected player's own row.
    ///   - opensProfile: Whether the row opens the player's profile (the spotlight row's caller wires its own action).
    ///   - identifier: Accessibility identifier.
    init(entry: AccountRankingEntry, columns: LeaderboardRowColumns, isSelected: Bool, opensProfile: Bool, identifier: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let metric = RankingMetric.totalscore
        let rank = entry.rank(for: metric)
        let name = AccountRankingRow.displayName(entry)
        let songs = entry.songsLabel(for: metric)
        let spokenSongs = RankingsCountText.spokenSongs(songs, fullCombos: false)
        let rating = RankingFormatting.rating(entry.ratingValue(for: metric), metric: metric)
        let accessibilitySize = UKFont.isAccessibilitySize(traitCollection)
        let links = opensProfile && entry.hasAccount

        band.backgroundColor = UIColor(red: 75 / 255, green: 15 / 255, blue: 99 / 255, alpha: 0.75)
        band.isHidden = !isSelected
        band.isUserInteractionEnabled = false
        band.translatesAutoresizingMaskIntoConstraints = false
        addSubview(band)
        band.ukPin(to: self)

        let rankLabel = UKLabel("#\(rank.formatted())", style: .body, monospacedDigit: true, lines: 1)
        rankLabel.setContentHuggingPriority(.required, for: .horizontal)
        rankLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let nameView: UIView
        if accessibilitySize {
            nameView = UKLabel(name, style: .body, weight: isSelected ? .bold : nil)
        } else {
            nameView = UKMarqueeLabel(name, font: UKFont.font(.body, weight: isSelected ? .bold : nil))
        }
        let songsLabel = UKLabel(songs, style: .subheadline, weight: isSelected ? .bold : .regular, monospacedDigit: true, lines: 1)
        songsLabel.accessibilityLabel = spokenSongs
        let ratingLabel = UKLabel(rating, style: .body, weight: isSelected ? .bold : .semibold, monospacedDigit: true, color: UKAccentText.blue, lines: 1)
        for label in [songsLabel, ratingLabel] {
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
        chevron.tintColor = BrandUIColors.textPrimary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.isHidden = !entry.hasAccount && !isSelected

        let content: UIView
        if accessibilitySize {
            let top = UIStackView(arrangedSubviews: [rankLabel, nameView])
            top.spacing = 8
            top.alignment = .firstBaseline
            let bottom = UIStackView(arrangedSubviews: [songsLabel, UIView(), ratingLabel])
            bottom.spacing = 8
            bottom.alignment = .firstBaseline
            let column = UIStackView(arrangedSubviews: [top, bottom])
            column.axis = .vertical
            column.spacing = 4
            content = column
        } else {
            let rankSlot = UKLeaderboardColumnSlot(template: columns.rankLabel, content: rankLabel)
            let ratingSlot = UKLeaderboardColumnSlot(template: columns.ratingLabel, content: ratingLabel)
            var views: [UIView] = [rankSlot, nameView]
            if columns.showsSongs { views.append(UKLeaderboardColumnSlot(template: columns.songsLabel, style: .subheadline, content: songsLabel)) }
            views.append(ratingSlot)
            views.append(chevron)
            let row = UIStackView(arrangedSubviews: views)
            row.spacing = Self.columnSpacing
            row.alignment = .center
            content = row
        }
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            heightAnchor.constraint(greaterThanOrEqualToConstant: UKLeaderboardRowMetrics.minHeight),
        ])

        isAccessibilityElement = true
        let hiddenSongs = !accessibilitySize && !columns.showsSongs
        var label = "#\(rank.formatted()), \(name), \(hiddenSongs ? "\(spokenSongs), " : "")\(rating)"
        if isSelected { label = "Your rank, \(RankingFormatting.ordinal(rank)). \(name)." }
        accessibilityLabel = label
        accessibilityTraits = links ? .button : .staticText
        if !entry.hasAccount && opensProfile { accessibilityHint = "Profile unavailable" }
        accessibilityIdentifier = identifier
        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    /// Whether every row of a card hides its songs column: the widest row (rank, longest
    /// name in the weight it is drawn in, songs, rating, chevron, spacing and padding) does
    /// not fit the card's width (``RankingSongsFit``).
    ///
    /// - Parameters:
    ///   - columns: The card's fitted columns.
    ///   - names: Every row's name and whether it is the selected player's.
    ///   - availableWidth: The card's width.
    /// - Returns: The columns with their songs decision made.
    static func fit(_ columns: LeaderboardRowColumns, names: [(name: String, emphasized: Bool)], availableWidth: CGFloat) -> LeaderboardRowColumns {
        func width(_ text: String?, _ font: UIFont) -> CGFloat {
            guard let text else { return 0 }
            return ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let bodyBold = UKFont.font(.body, weight: .bold, monospacedDigit: true)
        let widestName = names.map { width($0.name, UKFont.font(.body, weight: $0.emphasized ? .bold : nil)) }.max() ?? 0
        let required = 2 * horizontalPadding + width(columns.rankLabel, bodyBold) + widestName
            + width(columns.songsLabel, UKFont.font(.subheadline, weight: .bold, monospacedDigit: true))
            + width(columns.ratingLabel, bodyBold) + 16 + 4 * columnSpacing
        return columns.fittingSongs(availableWidth: Double(availableWidth), requiredWidth: Double(required))
    }
}

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
        let width = max(view.bounds.width - 32, 0)
        let columns = UKCompeteRankingRow.fit(
            LeaderboardRowColumns.rankings(cardRows, metric: .totalscore),
            names: cardRows.map { (AccountRankingRow.displayName($0), isSelected($0.accountId)) },
            availableWidth: width
        )
        let group = UKGroupSectionView(rows: .flush(separatorInset: UKCompeteRankingRow.horizontalPadding))
        var rows: [UIView] = entries.map { entry in
            let row = UKCompeteRankingRow(
                entry: entry, columns: columns, isSelected: isSelected(entry.accountId), opensProfile: true,
                identifier: "fst.rankings.row.\(entry.id)"
            )
            row.onSelect = { [weak navigator = context.navigator] in
                guard entry.hasAccount else { return }
                navigator?.selectDetail(AccountRankingRow.route(entry))
            }
            return row
        }
        if let spotlight {
            let row = UKCompeteRankingRow(
                entry: spotlight, columns: columns, isSelected: true, opensProfile: false,
                identifier: "fst.compete.leaderboard-card.\(scope.id).spotlight"
            )
            let rank = spotlight.rank(for: CompetePreviewSpotlight.metric)
            row.accessibilityLabel = CompetePreviewSpotlight.action(for: spotlight).footerLabel(for: .player, rank: rank)
            row.accessibilityTraits = .button
            row.onSelect = { [weak navigator = context.navigator] in
                navigator?.selectDetail(CompetePreviewSpotlight.route(for: spotlight, scope: scope))
            }
            rows.append(row)
        }
        group.setRows(rows)
        group.setAction(UKPurpleActionButton(
            title: "View Full Leaderboard", identifier: "fst.compete.leaderboard-card.\(scope.id).view-all", card: scope.label
        ) { [weak navigator = context.navigator, route = fullBoardRoute(scope)] in navigator?.push(route) })
        return group
    }
}
#endif
