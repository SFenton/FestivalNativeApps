#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

/// Read-only Rank By, Compete Hub and Rivals illustrations over the shared sample data.
@MainActor
final class UKFirstRunCompetitionPreview: UIView {
    private enum Mode {
        case metrics, hub, groups(Int), instruments
    }

    private let mode: Mode
    private let stack = UIStackView()
    private var metricTop: NSLayoutConstraint?
    private var above: FirstRunWindowRotation<FirstRunDemoPool.RivalEntry>
    private var below: FirstRunWindowRotation<FirstRunDemoPool.RivalEntry>
    private var rivalSlots: [UIView] = []
    private var metricIcons: [UIImageView] = []
    private var positions = Array(repeating: 0, count: 6)
    private var previousSlots: Set<Int> = []
    private var tick = 0
    private var active = false
    private var playback: Task<Void, Never>?
    private var animator: UIViewPropertyAnimator?
    private var animatedViews: [UIView] = []
    private var accessibilityObserver: UKAccessibilityObserver?
    private nonisolated(unsafe) var sceneObservers: [NSObjectProtocol] = []

    /// Headers and rows that enter using the guide's 80 ms ranking cascade.
    private(set) var entranceItems: [UIView] = []

    /// - Parameter slideID: The registered lesson ID, or an unrelated lesson to skip.
    init?(slideID: String) {
        switch slideID {
        case "leaderboards-experimental-metrics": mode = .metrics
        case "compete-hub": mode = .hub
        case "compete-rivals": mode = .groups(2)
        case "rivals-overview": mode = .groups(3)
        case "rivals-instruments": mode = .instruments
        default: return nil
        }
        let count = if case let .groups(visible) = mode { visible } else { 2 }
        above = FirstRunWindowRotation(pool: FirstRunDemoPool.rivalsAbove, count: count)
        below = FirstRunWindowRotation(pool: FirstRunDemoPool.rivalsBelow, count: count)
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let center = stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        center.priority = .defaultLow
        let top = stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor), center,
        ])
        if case .metrics = mode { metricTop = top } else { top.isActive = true }
        switch mode {
        case .metrics: makeMetrics()
        case .hub: renderHub()
        case .groups: makeGroups(stagger: true)
        case .instruments: makeInstruments()
        }
        accessibilityObserver = UKAccessibilityObserver { [weak self] in self?.refreshPlayback() }
        let centerObserver = NotificationCenter.default
        sceneObservers = [UIScene.didActivateNotification, UIScene.willDeactivateNotification].map { name in
            centerObserver.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let scene = note.object as? UIScene else { return }
                let sceneID = ObjectIdentifier(scene)
                MainActor.assumeIsolated {
                    guard let self, let scene = self.window?.windowScene, ObjectIdentifier(scene) == sceneID else { return }
                    self.refreshPlayback(sceneActive: name == UIScene.didActivateNotification)
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        sceneObservers.forEach(NotificationCenter.default.removeObserver)
        playback?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshPlayback()
    }

    /// - Parameter active: Whether this illustration is on the current slide.
    func setActive(_ active: Bool) {
        self.active = active
        refreshPlayback()
    }

    /// Keep Rank By's first choice visible in compact and accessibility-size previews.
    ///
    /// - Parameter compact: Whether the slide uses its short, scrolling layout.
    func setCompact(_ compact: Bool) {
        if let metricTop, metricTop.isActive != compact { metricTop.isActive = compact }
    }

    private func makeMetrics() {
        let metrics = FirstRunLeaderboardsExperimentalMetricsDemo.metrics
        let choices = UIStackView(arrangedSubviews: [UKLabel("Rank By", style: .caption1, weight: .semibold)])
        choices.axis = .vertical
        choices.spacing = 10
        for (title, description) in metrics {
            let icon = UIImageView()
            icon.preferredSymbolConfiguration = .init(font: UKFont.font(.body))
            icon.setContentHuggingPriority(.required, for: .horizontal)
            metricIcons.append(icon)
            let column = UIStackView(arrangedSubviews: [
                UKLabel(title, style: .body),
                UKLabel(description, style: .caption2, color: BrandUIColors.textMuted),
            ])
            column.axis = .vertical
            column.spacing = 1
            let row = UIStackView(arrangedSubviews: [icon, column])
            row.alignment = .center
            row.spacing = 8
            choices.addArrangedSubview(row)
        }
        let card = UKCardView(cornerRadius: 16)
        let inset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.contentView.ukPin(choices, insets: inset)
        stack.addArrangedSubview(card)
        updateMetric()
    }

    private func updateMetric() {
        for (index, icon) in metricIcons.enumerated() {
            let selected = index == tick % metricIcons.count
            icon.image = UIImage(systemName: selected ? "largecircle.fill.circle" : "circle")
            icon.tintColor = selected ? BrandUIColors.accentBlue : BrandUIColors.textMuted
        }
    }

    private func renderHub() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rivalSlots.removeAll()
        if tick.isMultiple(of: 2) {
            let rows = Array(FirstRunDemoPool.rankings.prefix(4)) + [FirstRunDemoPool.rankingNeighborhood[3]]
            let card = UKGroupSectionView(rows: .flush(separatorInset: UKLeaderboardMetrics.horizontalPadding))
            card.setRows(UKFirstRunRankingsPreview.rankingRows(rows))
            stack.addArrangedSubview(card)
        } else {
            makeGroups(stagger: false)
        }
    }

    private func makeGroups(stagger: Bool) {
        for (title, entries, direction) in [("Above You", above.rows, RivalDirection.above), ("Below You", below.rows, .below)] {
            let heading = UKLabel(title, style: .subheadline, weight: .bold)
            let (group, slots) = Self.makeRivalCard(count: entries.count)
            for (slot, rival) in zip(slots, entries) { Self.setRival(rival, direction: direction, in: slot) }
            stack.addArrangedSubview(heading)
            stack.addArrangedSubview(group)
            rivalSlots += slots
            if stagger { entranceItems += [heading] + slots }
        }
    }

    private func makeInstruments() {
        stack.spacing = 12
        for (index, instrument) in FirstRunRivalsInstrumentsDemo.instruments.enumerated() {
            let heading = UKInstrumentSectionHeaderView(scope: .instrument(instrument), title: "\(instrument.label) Rivals")
            let (group, slots) = Self.makeRivalCard(count: 2)
            let section = UIStackView(arrangedSubviews: [heading, group])
            section.axis = .vertical
            section.spacing = 6
            stack.addArrangedSubview(section)
            rivalSlots += slots
            entranceItems += [heading] + slots
            replaceInstrumentRivals([index * 2, index * 2 + 1])
        }
    }

    private static func makeRivalCard(count: Int) -> (UKGroupSectionView, [UIView]) {
        let card = UKGroupSectionView(rows: .flush(separatorInset: 16))
        let slots = (0..<count).map { _ in UIView() }
        card.setRows(slots.map { UKGroupSectionView.paddedRow($0) })
        return (card, slots)
    }

    private static func setRival(_ rival: FirstRunDemoPool.RivalEntry, direction: RivalDirection, in slot: UIView) {
        slot.subviews.forEach { $0.removeFromSuperview() }
        slot.ukPin(UKRivalRowView(
            displayName: rival.displayName, behindCount: rival.behindCount, aheadCount: rival.aheadCount,
            direction: direction, identifier: ""
        ))
    }

    private func replaceInstrumentRivals(_ indices: [Int]) {
        for index in indices {
            guard let rival = FirstRunRivalsInstrumentsDemo.rival(slot: index, position: positions[index]) else { continue }
            Self.setRival(rival, direction: index.isMultiple(of: 2) ? .above : .below, in: rivalSlots[index])
        }
    }

    private func refreshPlayback(sceneActive: Bool? = nil) {
        let visible = active && (sceneActive ?? (window?.windowScene?.activationState == .foregroundActive))
        let runs = FirstRunDemoTickerPolicy.runs(
            active: visible, enabled: true, constrained: false,
            reduceMotion: UKAccessibility.reduceMotion, stillBackground: DebugAnimationOverride.stillBackground
        )
        if runs, playback == nil {
            playback = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: FirstRunDemoTiming.swapInterval) } catch { return }
                    guard let self else { return }
                    await self.advance()
                }
            }
        } else if !runs, let playback {
            playback.cancel()
            self.playback = nil
            if animator?.state == .active { animator?.stopAnimation(true) }
            animator = nil
            for view in animatedViews {
                view.alpha = 1
                view.transform = .identity
            }
            animatedViews.removeAll()
        }
    }

    private func advance() async {
        switch mode {
        case .metrics:
            tick += 1
            updateMetric()
        case .hub:
            await swap([stack], drop: 6) {
                tick += 1
                renderHub()
            }
        case let .groups(count):
            let top = tick.isMultiple(of: 2)
            let range = top ? 0..<count : count..<(2 * count)
            let slots = Array(rivalSlots[range])
            await swap(slots, drop: 4) {
                tick += 1
                if top { above.advance() } else { below.advance() }
                for (slot, rival) in zip(slots, top ? above.rows : below.rows) {
                    Self.setRival(rival, direction: top ? .above : .below, in: slot)
                }
            }
        case .instruments:
            let indices = FirstRunDemoRotation.swapIndices(rowCount: positions.count, tick: tick, avoiding: previousSlots)
            await swap(indices.map { rivalSlots[$0] }, drop: 4) {
                tick += 1
                previousSlots = Set(indices)
                for index in indices { positions[index] += 1 }
                replaceInstrumentRivals(indices)
            }
        }
    }

    private func swap(_ views: [UIView], drop: CGFloat, update: () -> Void) async {
        animatedViews = views
        fade(views, alpha: 0, y: drop)
        do { try await Task.sleep(for: FirstRunDemoTiming.fade) } catch { return }
        guard !Task.isCancelled else { return }
        update()
        fade(views, alpha: 1, y: 0)
    }

    private func fade(_ views: [UIView], alpha: CGFloat, y: CGFloat) {
        let curve = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.25, y: 0.1), controlPoint2: CGPoint(x: 0.25, y: 1))
        let animator = UIViewPropertyAnimator(duration: FirstRunDemoTiming.fadeSeconds, timingParameters: curve)
        animator.addAnimations {
            for view in views {
                view.alpha = alpha
                view.transform = CGAffineTransform(translationX: 0, y: y)
            }
        }
        self.animator = animator
        animator.startAnimation()
    }
}

// MARK: - Head-to-head lesson

/// The head-to-head guide's sample standings and bounded catalogue titles; no opponent lookup.
@MainActor
final class UKFirstRunRivalDetailPreview: UIView {
    nonisolated static let rowCount = 3

    private let track = UIStackView()
    private let heading = UKLabel(style: .subheadline, weight: .bold)
    private let rows = (0..<UKFirstRunRivalDetailPreview.rowCount).map { _ in UKCardView(cornerRadius: 12) }
    private var shownSongs: [Song]?
    private var shownPhase: Int?
    private var shownArtwork = false

    /// Heading then comparison rows, each with its reference entrance delay.
    var entrances: [(view: UIView, delay: TimeInterval)] {
        [(heading, 0)] + rows.enumerated().map { ($0.element, Double($0.offset + 1) * FirstRunMotion.detailStaggerSeconds) }
    }

    /// Builds the illustration before the catalogue is available.
    init(session: FestivalSession) {
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        track.axis = .vertical
        track.spacing = 10
        track.addArrangedSubview(heading)
        rows.forEach(track.addArrangedSubview)
        track.translatesAutoresizingMaskIntoConstraints = false
        addSubview(track)
        let center = track.centerYAnchor.constraint(equalTo: centerYAnchor)
        center.priority = .defaultLow
        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(greaterThanOrEqualTo: topAnchor), center,
        ])
        configure(songs: nil, phase: 0, session: session, allowsArtwork: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Updates sample standings and catalogue content without adding an interactive route.
    ///
    /// - Parameters:
    ///   - songs: Bounded catalogue rows, or nil for redaction.
    ///   - phase: The number of completed swaps.
    ///   - session: Shared cache for decorative artwork.
    ///   - allowsArtwork: Whether the current guide may load and animate song content.
    func configure(songs: [Song]?, phase: Int, session: FestivalSession, allowsArtwork: Bool) {
        guard songs != shownSongs || phase != shownPhase || allowsArtwork != shownArtwork else { return }
        shownSongs = songs
        shownPhase = phase
        shownArtwork = allowsArtwork
        let categories = FirstRunDemoPool.rivalDetailCategories
        let category = categories[phase % categories.count]
        heading.text = category.title
        for (index, card) in rows.enumerated() {
            let song = songs.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            let ranks = category.ranks[index]
            card.contentView.subviews.forEach { $0.removeFromSuperview() }
            card.contentView.ukPin(Self.comparison(song, ranks: ranks, session: session, allowsArtwork: allowsArtwork),
                                   insets: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
        }
    }

    /// Replays the per-row entrance after a category swap, or clears interrupted motion.
    func stagger(animated: Bool) {
        for (view, delay) in entrances {
            UKFirstRunSlideView.enter(view, delay: delay, visible: true, animated: animated)
        }
    }

    private static func comparison(
        _ song: Song?, ranks: FirstRunDemoPool.RivalComparison, session: FestivalSession, allowsArtwork: Bool
    ) -> UIView {
        let artwork = UKArtworkTileView(size: 44)
        if let song, allowsArtwork {
            artwork.configure(raw: song.albumArt, session: session)
        } else {
            artwork.backgroundColor = BrandUIColors.surfaceMuted
        }
        let title: UIView
        if let song {
            let label = UKMarqueeLabel(song.title, font: UKFont.font(.subheadline, weight: .semibold))
            label.animationEnabled = allowsArtwork
            title = label
        } else {
            let redaction = UIView()
            redaction.backgroundColor = BrandUIColors.textPrimary.withAlphaComponent(0.18)
            redaction.layer.cornerRadius = 4
            redaction.translatesAutoresizingMaskIntoConstraints = false
            let holder = UIView()
            holder.addSubview(redaction)
            NSLayoutConstraint.activate([
                redaction.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                redaction.widthAnchor.constraint(equalToConstant: 100),
                redaction.heightAnchor.constraint(equalToConstant: 10),
                holder.heightAnchor.constraint(equalToConstant: 17),
                redaction.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            ])
            title = holder
        }
        let ranks = UIStackView(arrangedSubviews: [
            rank(ranks.userRank, symbol: "person.fill", tint: BrandUIColors.accentBlue),
            rank(ranks.rivalRank, symbol: "person.fill.badge.plus", tint: BrandUIColors.statusRed),
            UIView(),
        ])
        ranks.spacing = 10
        let info = UIStackView(arrangedSubviews: [title, ranks])
        info.axis = .vertical
        info.spacing = 2
        let row = UIStackView(arrangedSubviews: [artwork, info])
        row.alignment = .center
        row.spacing = 12
        return row
    }

    private static func rank(_ value: Int, symbol: String, tint: UIColor) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.preferredSymbolConfiguration = .init(font: UKFont.font(.caption2, weight: .semibold))
        icon.tintColor = tint
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UKLabel("#\(value)", style: .caption2, weight: .semibold, color: tint, lines: 1)
        label.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.alignment = .center
        row.spacing = 4
        return row
    }
}
#endif
