#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Loading section

/// One independently loaded card on the Rivals hub: it shows the card for its current
/// ``RivalsLoadState`` (the spinner, the failure with Retry, the rows, or nothing when the
/// result is empty and the page hides it), reads once when started and again on Retry, and
/// fades loaded rows in as they arrive. One slow or failed section never blocks its siblings.
@MainActor
final class UKRivalLoadingSection<Value>: UIView {
    private let load: @MainActor () async throws -> Value
    private let present: (RivalsLoadState<Value>, @escaping () -> Void) -> UIView?
    private var current: UIView?
    private nonisolated(unsafe) var task: Task<Void, Never>?
    /// Called with whether the section currently shows a loaded card (Quick Links follow it).
    var onLoadedChange: ((Bool) -> Void)?

    /// Creates a section.
    ///
    /// - Parameters:
    ///   - load: Reads the section's data.
    ///   - present: Builds the card for a state (and its retry action); nil hides the section.
    init(
        load: @escaping @MainActor () async throws -> Value,
        present: @escaping (RivalsLoadState<Value>, @escaping () -> Void) -> UIView?
    ) {
        self.load = load
        self.present = present
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        render(.loading, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { task?.cancel() }

    /// Reads the data and shows the result.
    func start() {
        task?.cancel()
        render(.loading, animated: false)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let value = try await self.load()
                guard !Task.isCancelled else { return }
                self.render(.loaded(value), animated: true)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.render(.failed(ServiceIssue(error)), animated: false)
            }
        }
    }

    private func render(_ state: RivalsLoadState<Value>, animated: Bool) {
        current?.removeFromSuperview()
        current = nil
        let card = present(state) { [weak self] in self?.start() }
        isHidden = card == nil
        var loaded = false
        if case .loaded = state { loaded = card != nil }
        onLoadedChange?(loaded)
        guard let card else { return }
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        card.ukPin(to: self)
        current = card
        if animated { UKFadeIn.fadeIn(card) }
    }
}

// MARK: - Card builders

/// Builds the rivals cards the hub, Compete and the Duo panes share: one material card of
/// preview rows ending in its purple "View All Rivals" button, with its header above it.
@MainActor
enum UKRivalCards {
    /// Rows previewed from each direction.
    static let previewCount = 3

    /// The spinner row every loading card shows.
    static func spinnerRow() -> UIView {
        let loading = UKLoadingView(accessibilityLabel: "Loading")
        let holder = UIView()
        loading.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            loading.topAnchor.constraint(equalTo: holder.topAnchor, constant: 12),
            loading.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -12),
        ])
        return holder
    }

    /// The inline failure row.
    static func failureRow(_ issue: ServiceIssue, scope: String, retry: @escaping () -> Void) -> UIView {
        UKServiceStatusInlineView(issue, scope: scope, retry: retry)
    }

    /// A page-width section: an optional titled material card of rows and an optional
    /// in-card action, padded 16 pt on each side.
    ///
    /// - Parameters:
    ///   - title: Title Case header inside the section (Common and Combo), or nil.
    ///   - header: A custom header above the card (the instrument header), or nil.
    ///   - rows: The card's rows.
    ///   - action: The in-card "View All" button.
    /// - Returns: The padded section.
    static func section(title: String? = nil, header: UIView? = nil, rows: [UIView], action: UIView? = nil) -> UIView {
        let group = UKGroupSectionView(title)
        group.setRows(rows)
        group.setAction(action)
        guard let header else { return group.ukPadded() }
        let stack = UIStackView(arrangedSubviews: [header, group])
        stack.axis = .vertical
        stack.spacing = 8
        return stack.ukPadded()
    }

    /// The first rows of a rivals result, above rivals first (`previewRows`).
    ///
    /// - Parameters:
    ///   - above: Rivals above the player.
    ///   - below: Rivals below the player.
    /// - Returns: Up to ``previewCount`` of each, tagged with their direction.
    static func preview<Rival: RivalRowDisplayable>(above: [Rival], below: [Rival]) -> [(rival: Rival, direction: RivalDirection)] {
        above.prefix(previewCount).map { ($0, RivalDirection.above) } + below.prefix(previewCount).map { ($0, RivalDirection.below) }
    }

    /// One rival's row, opening their detail beside the list (or pushed).
    ///
    /// - Parameters:
    ///   - rival: The rival.
    ///   - direction: Above or below the player.
    ///   - scope: Scope the detail opens with.
    ///   - identifier: Row identifier.
    ///   - context: The page's context.
    /// - Returns: The row.
    static func rivalRow<Rival: RivalRowDisplayable>(
        _ rival: Rival, direction: RivalDirection, scope: RivalScope?, identifier: String, context: UKContext
    ) -> UIView {
        let row = UKRivalRowView(
            displayName: rival.displayName, behindCount: rival.behindCount, aheadCount: rival.aheadCount,
            direction: direction, identifier: identifier
        )
        let route = AppRoute.rivalDetail(rivalId: rival.accountId, name: rival.displayName, scope: scope)
        row.onSelect = { [weak navigator = context.navigator] in navigator?.selectDetail(route) }
        return row
    }

    /// "View All Rivals" for a preview card.
    static func viewAll(route: AppRoute, identifier: String, card: String, context: UKContext) -> UIView {
        UKPurpleActionButton(title: "View All Rivals", identifier: identifier, card: card) { [weak navigator = context.navigator] in
            navigator?.push(route)
        }
    }

    /// One instrument's or combo's "shared songs" rivals card (``RivalInstrumentSongCard``).
    ///
    /// - Parameters:
    ///   - scope: The card's board.
    ///   - state: The rivals read.
    ///   - detailScope: Scope a tapped rival opens with; nil opens the card's own.
    ///   - emptyMessage: Copy for an empty result; nil hides the card.
    ///   - context: The page's context.
    ///   - retry: Reads the rivals again.
    /// - Returns: The card, or nil when it hides.
    static func songCard(
        scope: RankingScope, state: RivalsLoadState<RivalsListResponse>, detailScope: RivalScope? = nil,
        emptyMessage: String? = nil, context: UKContext, retry: @escaping () -> Void
    ) -> UIView? {
        let title = "\(scope.label) Rivals"
        let header = UKInstrumentSectionHeaderView(scope: scope, title: title)
        switch state {
        case .loading:
            return section(header: header, rows: [spinnerRow()])
        case let .failed(issue):
            return section(header: header, rows: [failureRow(issue, scope: "rivals.song.\(scope.id)", retry: retry)])
        case let .loaded(response) where response.isEmpty:
            guard let emptyMessage else { return nil }
            return section(header: header, rows: [UKFootnoteLabel(emptyMessage)])
        case let .loaded(response):
            let ownScope: RivalScope
            let stem: String
            switch scope {
            case let .instrument(instrument):
                ownScope = .song(instruments: [instrument.rawValue])
                stem = "fst.rivals.song.\(instrument.rawValue)"
            case let .combo(combo):
                ownScope = .combo(token: combo.comboId, instruments: combo.instruments.map(\.rawValue))
                stem = "fst.rivals.combo.\(combo.comboId)"
            }
            let rows = preview(above: response.above, below: response.below).map {
                rivalRow($0.rival, direction: $0.direction, scope: detailScope ?? ownScope, identifier: "fst.rivals.row.\($0.rival.accountId)", context: context)
            }
            return section(
                header: header, rows: rows,
                action: viewAll(route: .allRivals(scope: ownScope), identifier: "\(stem).view-all", card: title, context: context)
            )
        }
    }
}
#endif
