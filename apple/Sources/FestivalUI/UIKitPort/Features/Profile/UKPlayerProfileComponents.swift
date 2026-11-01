#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Instrument header

/// The web's `InstrumentHeader` at medium size (``InstrumentSectionHeader``): a 48 pt icon
/// and a bold title3 name drawn above the card it titles, never inside it. The icon is
/// decorative; the name is a heading.
final class UKProfileInstrumentHeader: UIView {
    /// Creates the header.
    ///
    /// - Parameter instrument: Chart whose icon and name to draw.
    init(_ instrument: Instrument) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let icon = UKInstrumentIconView(instrument, size: 48, hidesFromAccessibility: true)
        let label = UKLabel(instrument.label, style: .title3, weight: .bold).asHeader()
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        ukPin(row, insets: UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Percentile pill

/// The web's `PercentilePill` (``PercentilePill``): "Top N%" in a small rounded pill, a gold
/// outline for the top 5%, a sheared gold outline for the top 1%, else a subtle fill.
final class UKPercentilePillView: UIView {
    private let topPercent: Int
    private let shape = CAShapeLayer()
    private let label: UKLabel

    /// Creates the pill.
    ///
    /// - Parameter topPercent: The band's upper bound.
    init(topPercent: Int) {
        self.topPercent = topPercent
        let isTopOne = topPercent <= 1
        let isGold = topPercent <= 5
        let font = UKFont.font(.subheadline, weight: isGold ? .bold : .semibold, monospacedDigit: true, italic: isTopOne)
        label = UKLabel("Top \(topPercent)%", style: .subheadline, color: isGold ? BrandUIColors.gold : BrandUIColors.textPrimary, lines: 1, alignment: .center)
        label.font = font
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.addSublayer(shape)
        shape.fillColor = isGold ? UIColor.clear.cgColor : UIColor.white.withAlphaComponent(0.1).cgColor
        shape.strokeColor = isGold ? BrandUIColors.goldStroke.cgColor : nil
        shape.lineWidth = isGold ? 2 : 0
        ukPin(label, insets: UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8))
        widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
        shape.path = Self.path(in: bounds, skewed: topPercent <= 1).cgPath
    }

    /// The badge outline (``GoldSkewBadgeShape``): 8 pt corners, optionally sheared -8 degrees,
    /// inset horizontally before shearing so it still fits the rect.
    ///
    /// - Parameters:
    ///   - rect: The pill's bounds.
    ///   - skewed: Apply the shear.
    /// - Returns: The outline.
    static func path(in rect: CGRect, skewed: Bool) -> UIBezierPath {
        guard skewed, rect.width > 0, rect.height > 0 else {
            return UIBezierPath(roundedRect: rect, cornerRadius: min(8, rect.height / 2))
        }
        let shift = tan(8 * CGFloat.pi / 180) * rect.height / 2
        let local = CGRect(x: shift, y: 0, width: max(0, rect.width - 2 * shift), height: rect.height)
        let path = UIBezierPath(roundedRect: local, cornerRadius: min(8, rect.height / 2))
        path.apply(SongLeaderboardEntryRow.goldSkew(height: rect.height).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
        return path
    }
}

// MARK: - Percentile table card

/// One instrument's percentile table on its own card (``PlayerPercentileTableCard``): a
/// "Percentile | Songs" header, then one row per non-empty "Top N%" band. A row opens Songs
/// filtered to that band when the page allows the link; otherwise it is plain.
final class UKPlayerPercentileTableCardView: UIView {
    private let instrument: Instrument
    private let linkFilter: (PlayerStatLink?) -> PlayerStatLink?
    private let onSelect: (PlayerStatLink) -> Void
    private let card = UKCardView(cornerRadius: 16)
    private let stack = UIStackView()
    private var buckets: [PlayerPercentileBucket]

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - buckets: The non-empty bands, best first.
    ///   - instrument: Chart.
    ///   - linkFilter: The page's rule for which links may be drawn.
    ///   - onSelect: Follows a tapped row's link.
    init(
        buckets: [PlayerPercentileBucket], instrument: Instrument,
        linkFilter: @escaping (PlayerStatLink?) -> PlayerStatLink?, onSelect: @escaping (PlayerStatLink) -> Void
    ) {
        self.buckets = buckets
        self.instrument = instrument
        self.linkFilter = linkFilter
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        card.embed(stack)
        ukPin(card)
        ukContain(identifier: "fst.player.percentiles.\(instrument.rawValue)", label: "\(instrument.label) Percentiles")
        isHidden = buckets.isEmpty
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Re-evaluates which rows link (the page's selection or identity changed).
    func refreshLinks() { rebuild() }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !buckets.isEmpty else { return }
        stack.addArrangedSubview(header())
        for bucket in buckets {
            stack.addArrangedSubview(UKHairlineView())
            stack.addArrangedSubview(row(bucket))
        }
    }

    private func header() -> UIView {
        let title = UKLabel("Percentile".uppercased(), style: .caption1, weight: .semibold)
        let songs = UKLabel("Songs".uppercased(), style: .caption1, weight: .semibold)
        let row = UIStackView(arrangedSubviews: [title, UIView(), songs])
        row.axis = .horizontal
        row.spacing = 8
        let holder = UIView()
        holder.ukPin(row, insets: UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16))
        holder.isAccessibilityElement = false
        holder.accessibilityElementsHidden = true
        return holder
    }

    private func row(_ bucket: PlayerPercentileBucket) -> UIView {
        let link = linkFilter(PlayerStatLinks.percentileBucket(instrument, percentile: bucket.topPercent))
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        let pill = UKPercentilePillView(topPercent: bucket.topPercent)
        let count = UKLabel(bucket.count.formatted(), style: .body, weight: .semibold, monospacedDigit: true, lines: 1)
        var arranged: [UIView] = [pill, UIView(), count]
        if link != nil {
            let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
            chevron.tintColor = BrandUIColors.textMuted
            chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
            chevron.setContentHuggingPriority(.required, for: .horizontal)
            arranged.append(chevron)
        }
        let content = UIStackView(arrangedSubviews: arranged)
        content.axis = .horizontal
        content.spacing = 10
        content.alignment = .center
        content.isUserInteractionEnabled = false
        control.ukPin(content, insets: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16))
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        control.isAccessibilityElement = true
        control.accessibilityLabel = Self.label(bucket)
        control.accessibilityValue = "\(bucket.count.formatted()) \(bucket.count == 1 ? "song" : "songs")"
        control.accessibilityIdentifier = "fst.player.percentile-row.\(instrument.rawValue).\(bucket.topPercent)"
        if let link {
            control.accessibilityHint = "Shows these songs in Songs"
            control.accessibilityTraits = .button
            control.addAction(UIAction { [onSelect] _ in onSelect(link) }, for: .touchUpInside)
            control.addAction(UIAction { [weak control] _ in control?.backgroundColor = UIColor.white.withAlphaComponent(0.06) }, for: .touchDown)
            control.addAction(UIAction { [weak control] _ in control?.backgroundColor = nil }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        } else {
            control.isUserInteractionEnabled = false
        }
        return control
    }

    /// "Top N%", the web's `PercentilePill` text.
    ///
    /// - Parameter bucket: One non-empty band.
    /// - Returns: Row and VoiceOver label.
    static func label(_ bucket: PlayerPercentileBucket) -> String { PlayerPercentileTableCard.label(bucket) }
}

// MARK: - Instrument stats card

/// One played instrument's stat tiles plus three global-rank tiles (``InstrumentStatsCard``).
///
/// The page normally reads the ranking before it shows anything, so the tiles open final;
/// on Retry the rank tiles become placeholders while the read is in flight. A failed read
/// keeps the grid's shape (em dashes) and adds an inline retry line.
final class UKInstrumentStatsCardView: UIView, UKWidthDependent {
    private let session: FestivalSession
    private let accountId: String
    private let instrument: Instrument
    private var baseTiles: [StatTile]
    private var linkFilter: (PlayerStatLink?) -> PlayerStatLink?
    private let grid: UKStatGridView
    private let failure = UIStackView()
    private let failureLabel = UKLabel(style: .caption1, lines: 0)
    private let stack = UIStackView()
    private var phase: InstrumentStatsCard.Phase
    private var loadTask: Task<Void, Never>?

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - accountId: Viewed account.
    ///   - instrument: Played, Settings-visible chart.
    ///   - tiles: Profile tiles before the rank tiles.
    ///   - preloaded: The page's finished ranking read.
    ///   - linkFilter: The page's rule for drawable links.
    ///   - layoutProvider: The window layout.
    ///   - onSelect: Follows a tapped tile's link.
    init(
        session: FestivalSession, accountId: String, instrument: Instrument, tiles: [StatTile],
        preloaded: InstrumentStatsCard.Phase?, linkFilter: @escaping (PlayerStatLink?) -> PlayerStatLink?,
        layoutProvider: @escaping () -> DeviceLayout, onSelect: @escaping (PlayerStatLink) -> Void
    ) {
        self.session = session
        self.accountId = accountId
        self.instrument = instrument
        self.baseTiles = tiles
        self.linkFilter = linkFilter
        phase = preloaded ?? .loading
        let initial = tiles + PlayerProfileTiles.rank(preloaded ?? .loading, instrument: instrument, link: linkFilter)
        grid = UKStatGridView(tiles: initial, scope: instrument.rawValue, layoutProvider: layoutProvider)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        grid.onSelect = onSelect
        failure.axis = .horizontal
        failure.spacing = 8
        failure.alignment = .center
        failure.addArrangedSubview(failureLabel)
        failure.addArrangedSubview(UKProfileRetryButton { [weak self] in self?.reload() })
        failure.isHidden = true
        stack.axis = .vertical
        stack.spacing = 8
        stack.addArrangedSubview(grid)
        stack.addArrangedSubview(UKProfileInset(failure, horizontal: 4))
        ukPin(stack)
        refresh()
        if case .loading = phase { reload() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { loadTask?.cancel() }

    func prepare(width: CGFloat) { grid.prepare(width: width) }

    /// Re-evaluates the tiles' links and values (selection or identity changed).
    ///
    /// - Parameters:
    ///   - tiles: New profile tiles, when they changed.
    ///   - linkFilter: New link rule, when it changed.
    func update(tiles: [StatTile]? = nil, linkFilter: ((PlayerStatLink?) -> PlayerStatLink?)? = nil) {
        if let tiles { baseTiles = tiles }
        if let linkFilter { self.linkFilter = linkFilter }
        refresh()
    }

    private func refresh() {
        grid.setTiles(baseTiles + PlayerProfileTiles.rank(phase, instrument: instrument, link: linkFilter))
        let id = PlayerProfileTiles.rankPhaseIdentifier(phase)
        grid.ukContain(identifier: "fst.player.global-rank.\(instrument.rawValue).\(id)")
        if case let .failed(message) = phase {
            failureLabel.text = "Global rank unavailable: \(message)"
            failure.isHidden = false
            failure.superview?.ukContain(identifier: "fst.player.global-rank.\(instrument.rawValue).error")
        } else {
            failure.isHidden = true
            failure.superview?.accessibilityIdentifier = nil
            failure.superview?.accessibilityContainerType = .none
        }
    }

    /// Read the pure per-instrument rankings-board row, never player-stats.
    private func reload() {
        loadTask?.cancel()
        phase = .loading
        refresh()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.session.playerInstrumentRanking(instrument: self.instrument, accountId: self.accountId)
                try Task.checkCancellation()
                switch payload.state {
                case .available: self.phase = payload.ranking.map(InstrumentStatsCard.Phase.available) ?? .unranked
                case .unranked: self.phase = .unranked
                }
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
            self.refresh()
        }
    }
}
#endif
