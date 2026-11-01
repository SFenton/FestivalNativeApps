#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Instrument card

/// One instrument's leaderboard preview on Song Detail (``SongScorePreview``): a large
/// instrument icon, the name and entry total above a group card holding the top ten, the
/// selected player's own row after them (when they rank below the top ten) and "View Full
/// Leaderboard" at the card's foot.
///
/// The page reads every chart before it appears and hands the result in as `preloaded`; the
/// card adopts it once and thereafter reloads itself only for a new publication, Filter
/// Invalid Scores / leeway change or Retry, keeping loaded rows when it reappears.
final class UKSongScorePreviewView: UIView {
    typealias LoadState = SongScorePreview.LoadState

    private struct RequestKey: Equatable {
        let publicationRevision: Int
        let leeway: Double?
    }

    private let song: Song
    private let instrument: Instrument
    private let context: UKContext
    private let hasPreload: Bool
    private let headerIcon: UKInstrumentIconView
    private let titleLabel: UKLabel
    private let subtitleLabel = UKLabel(style: .subheadline)
    private let header = UIView()
    private let body = UIView()
    private let observations = UKObservationBag()
    private var state: LoadState
    private var loadedKey: RequestKey?
    private var adoptedPreload = false
    private var task: Task<Void, Never>?
    private var renderedWidth: CGFloat = 0
    private var renderedSignature: String = ""
    private var currentBody: UIView?
    private var started = false
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    private var loadingKey: RequestKey?

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - song: The song.
    ///   - instrument: The chart.
    ///   - context: The page's context (session and navigator).
    ///   - preloaded: The page's finished read for this chart, if any.
    init(song: Song, instrument: Instrument, context: UKContext, preloaded: LoadState?) {
        self.song = song
        self.instrument = instrument
        self.context = context
        state = preloaded ?? .loading
        if case .loading? = preloaded { hasPreload = false } else { hasPreload = preloaded != nil }
        headerIcon = UKInstrumentIconView(
            instrument, keyboard: song.usesKeyboardIcon && (instrument == .lead || instrument == .proLead),
            size: UKFont.scaled(48, relativeTo: .title3), hidesFromAccessibility: true
        )
        titleLabel = UKLabel(instrument.label, style: .title3, weight: .bold)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let texts = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let row = UIStackView(arrangedSubviews: [headerIcon, texts])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor), row.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor),
            row.topAnchor.constraint(equalTo: header.topAnchor), row.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        header.isAccessibilityElement = true
        header.accessibilityTraits = .header
        header.accessibilityIdentifier = "fst.song-detail.card-header.\(instrument.rawValue)"
        let stack = UIStackView(arrangedSubviews: [header, body])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = "fst.song-detail.card.\(instrument.rawValue)"
        observations.observe { [weak self] in self?.sessionChanged() }
        settingsObserver = NotificationCenter.default.addObserver(forName: UKSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        task?.cancel()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    // MARK: Keys

    private var requestKey: RequestKey {
        let filter = UKSettings.bool("fst.settings.filterInvalidScores", default: false)
        let leeway = UserDefaults.standard.object(forKey: "fst.settings.leeway") as? Double ?? 1.0
        return RequestKey(
            publicationRevision: context.session.publicationRevision, leeway: filter ? (leeway * 10).rounded() / 10 : nil
        )
    }

    /// Re-renders when anything the rows read changes (the selected player, their scores,
    /// the current season) and re-evaluates the read for a new publication.
    private func sessionChanged() {
        let session = context.session
        _ = session.publicationRevision
        _ = session.selectedPlayer
        _ = session.selectedPlayerScores[song.songId]?[instrument]
        _ = session.catalogCurrentSeason
        guard started else { return }
        evaluate()
        render()
    }

    // MARK: Loading

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !started else { return }
        started = true
        evaluate()
    }

    /// The `.task(id: requestKey)` rule: keep rows already loaded for this key, adopt the
    /// page's preload once, otherwise read.
    private func evaluate() {
        let key = requestKey
        if case .loaded = state, loadedKey == key { return }
        if hasPreload, loadedKey == nil, !adoptedPreload {
            adoptedPreload = true
            if case .loaded = state { loadedKey = key }
            return
        }
        if task != nil, loadingKey == key { return }
        reload()
    }

    private func reload() {
        task?.cancel()
        loadingKey = requestKey
        task = Task { [weak self] in await self?.load() }
    }

    private func load() async {
        let requested = requestKey
        state = .loading
        render()
        do {
            let payload = try await context.session.leaderboard(
                songId: song.songId, instrument: instrument, page: 1, top: 10, leeway: requested.leeway
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            state = .loaded(payload)
            loadedKey = requested
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, requested == requestKey else { return }
            state = .failed(error.localizedDescription)
        }
        task = nil
        loadingKey = nil
        render()
        UKFadeIn.fadeIn(body, rises: false)
    }

    // MARK: Rendering

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bodyWidth
        if width != renderedWidth, case .loaded = state {
            render()
        }
    }

    private var bodyWidth: CGFloat { body.bounds.width.rounded() }

    private var showsViewFull: Bool {
        switch state {
        case .loading: false
        case .failed: true
        case let .loaded(payload): !payload.leaderboard.entries.isEmpty
        }
    }

    private func render() {
        var subtitle: String?
        if case let .loaded(payload) = state { subtitle = SongDetailPlan.entriesSubtitle(payload) }
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        header.accessibilityLabel = [instrument.label, subtitle].compactMap { $0 }.joined(separator: ", ")
        renderedWidth = bodyWidth
        let next: UIView
        switch state {
        case .loading:
            let loading = UKLoadingView(accessibilityLabel: "Loading \(instrument.label) scores")
            loading.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            let holder = UIView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            loading.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(loading)
            NSLayoutConstraint.activate([
                loading.leadingAnchor.constraint(equalTo: holder.leadingAnchor), loading.topAnchor.constraint(equalTo: holder.topAnchor),
                loading.bottomAnchor.constraint(equalTo: holder.bottomAnchor), loading.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
            ])
            next = holder
        case let .failed(message):
            next = failedBody(message)
        case let .loaded(payload):
            next = loadedBody(payload)
        }
        swapBody(to: next)
    }

    private func swapBody(to view: UIView) {
        currentBody?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: body.leadingAnchor), view.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            view.topAnchor.constraint(equalTo: body.topAnchor), view.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
        currentBody = view
    }

    private func viewFullButton() -> UIView {
        UKPurpleActionButton(
            title: "View Full Leaderboard", card: instrument.label,
            identifier: "fst.song-detail.leaderboard.\(instrument.rawValue)"
        ) { [weak self] in
            guard let self else { return }
            self.context.navigator?.selectDetail(.songLeaderboard(self.song, self.instrument, 1))
        }
    }

    private func failedBody(_ message: String) -> UIView {
        let section = UKGroupSectionView(rows: .padded)
        let text = UKLabel("Scores unavailable: \(message)")
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Retry \(instrument.label) scores"
        configuration.baseForegroundColor = UKAccentText.blue
        configuration.contentInsets = .zero
        configuration.titleAlignment = .leading
        let retry = UIButton(configuration: configuration)
        retry.contentHorizontalAlignment = .leading
        retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        retry.addAction(UIAction { [weak self] _ in self?.reload() }, for: .primaryActionTriggered)
        let column = UIStackView(arrangedSubviews: [text, retry])
        column.axis = .vertical
        column.spacing = 8
        column.alignment = .fill
        section.setRows([column])
        section.setAction(viewFullButton())
        return section
    }

    private func loadedBody(_ payload: LeaderboardPayload) -> UIView {
        let session = context.session
        let displayed = Array(payload.leaderboard.entries.prefix(10))
        let key = requestKey
        let raw = session.selectedPlayerScores[song.songId]?[instrument]
        let spotlight = SongPreviewSpotlightPolicy.footerEntry(
            selected: session.selectedPlayer,
            score: key.leeway.map { leeway in
                raw.flatMap { InvalidScorePolicy.filtered($0, song: song, leeway: leeway) }
            } ?? raw,
            displayed: displayed
        )
        let disclosure: UIView? = payload.publicationId == nil
            ? UKFreshnessDisclosureView(message: "Showing live scores without publication verification", symbol: "info.circle") : nil
        let content: UIView
        if displayed.isEmpty && spotlight == nil {
            let card = UKCardView(cornerRadius: 12)
            let text = UKLabel("When scores are submitted for \(instrument.label), they will show up here on the next leaderboard update.")
            text.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            card.embed(text, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
            content = card
        } else {
            let all = displayed + [spotlight].compactMap { $0 }
            let columns = LeaderboardRowColumns.fit(
                .topScores, width: Double(bodyWidth), ranks: all.map(\.rank), scores: all.map(\.score)
            )
            let section = UKGroupSectionView(rows: .flush(separatorInset: 12))
            var rows: [UIView] = displayed.map { entry in
                row(entry, highlighted: SongPreviewSpotlightPolicy.isSelected(entry, selected: session.selectedPlayer), isFooter: false, columns: columns)
                    .identified("fst.song-detail.preview-row.\(instrument.rawValue).\(entry.accountId)")
            }
            if let spotlight {
                rows.append(row(spotlight, highlighted: true, isFooter: true, columns: columns)
                    .identified("fst.song-detail.spotlight.\(instrument.rawValue)"))
            }
            section.setRows(rows)
            section.setAction(showsViewFull ? viewFullButton() : nil)
            content = section
        }
        guard let disclosure else { return content }
        let stack = UIStackView(arrangedSubviews: [disclosure, content])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func row(_ entry: LeaderboardEntry, highlighted: Bool, isFooter: Bool, columns: LeaderboardRowColumns) -> UIView {
        let session = context.session
        let route = SongPreviewSpotlightPolicy.route(
            for: entry, selected: session.selectedPlayer, song: song, instrument: instrument, isFooter: isFooter
        )
        let view = UKSongLeaderboardEntryRowView(
            entry: entry, isPlayer: highlighted, columns: columns, currentSeason: session.catalogCurrentSeason,
            chevron: route == nil ? false : true, hint: route.map(SongPreviewSpotlightPolicy.hint(for:))
        )
        if let route {
            view.onTap = { [weak self] in
                guard let navigator = self?.context.navigator else { return }
                if case .songLeaderboard = route { navigator.selectDetail(route) } else { navigator.push(route) }
            }
        }
        return view
    }
}

extension UIView {
    /// Sets the accessibility identifier and returns the view, for building row lists.
    func identified(_ identifier: String) -> Self {
        accessibilityIdentifier = identifier
        return self
    }
}
#endif
