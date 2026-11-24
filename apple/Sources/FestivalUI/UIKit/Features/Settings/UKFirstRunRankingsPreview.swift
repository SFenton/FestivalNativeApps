#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Score and ranking guide previews

/// The read-only score and ranking cards. They draw the same sample rows as SwiftUI,
/// never the active profile or the results of a leaderboard request.
final class UKFirstRunRankingsPreview: UIView {
    private let pulseGroup: UKFirstRunPulseGroup

    /// The heading (when present), rows and View All, in entrance order.
    let entranceItems: [UIView]
    /// The delay between successive illustrations in the entrance.
    let staggerInterval: Double

    /// Creates a score history, song leaderboard or rankings illustration.
    ///
    /// - Parameter slideID: The slide's registered catalogue identifier.
    init?(slideID: String) {
        let showsInstrument: Bool
        let rows: [UIView]
        let actionTitle: String
        let spacing: CGFloat
        switch slideID {
        case "songinfo-view-all":
            showsInstrument = false
            rows = Self.historyRows()
            actionTitle = "View All Scores"
            spacing = 8
            staggerInterval = FirstRunMotion.staggerSeconds
        case "songinfo-top-scores":
            showsInstrument = true
            rows = Self.topScoreRows()
            actionTitle = "View Full Leaderboard"
            spacing = 8
            staggerInterval = FirstRunMotion.staggerSeconds
        case "leaderboards-overview", "compete-leaderboards":
            showsInstrument = true
            rows = Self.rankingRows(Array(FirstRunDemoPool.rankings.prefix(5)))
            actionTitle = "View all rankings (12,480)"
            spacing = 10
            staggerInterval = FirstRunMotion.rowStaggerSeconds
        case "leaderboards-your-rank":
            showsInstrument = false
            rows = Self.rankingRows(FirstRunDemoPool.rankingNeighborhood)
            actionTitle = "View all rankings (12,480)"
            spacing = 10
            staggerInterval = FirstRunMotion.rowStaggerSeconds
        default:
            return nil
        }
        let heading = showsInstrument ? Self.instrumentHeading() : nil
        let action = UKPurpleActionButton(title: actionTitle, card: nil, identifier: "")
        entranceItems = [heading].compactMap { $0 } + rows + [action]
        pulseGroup = UKFirstRunPulseGroup(
            targets: [action], shape: .roundedRect(cornerRadius: PurpleActionSurface.cornerRadius)
        )
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true

        let card = UKGroupSectionView(rows: .flush(separatorInset: UKLeaderboardMetrics.horizontalPadding))
        card.setRows(rows)
        card.setAction(action)
        let stack = UIStackView(arrangedSubviews: [heading, card].compactMap { $0 })
        stack.axis = .vertical
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        pulseGroup.updatePulse()
    }

    /// - Parameter active: Whether this illustration is on the current slide.
    func setActive(_ active: Bool) { pulseGroup.setActive(active) }

    private static func instrumentHeading() -> UIView {
        let icon = UKInstrumentIconView(.lead, size: 36, hidesFromAccessibility: true)
        let title = UKLabel(Instrument.lead.label, style: .title3, weight: .bold)
        let heading = UIStackView(arrangedSubviews: [icon, title, UIView()])
        heading.alignment = .center
        heading.spacing = 10
        return heading
    }

    private static func historyRows() -> [UIView] {
        let entries = FirstRunDemoPool.ownHistory
        let columns = LeaderboardRowColumns.scoreHistory(entries.map(\.newScore))
        return entries.enumerated().map { index, entry in
            let row = UKScoreHistoryRowView(
                entry: entry, isBest: index == 0, seasonColumn: false, currentSeason: nil,
                grouped: true, scoreTemplate: columns.scoreLabel
            )
            guard index == entries.count - 1 else { return row }
            // The last score stays muted even once its enclosing entrance has settled.
            row.alpha = 0.45
            let holder = UIView()
            holder.ukPin(row)
            return holder
        }
    }

    private static func topScoreRows() -> [UIView] {
        FirstRunDemoPool.topScores.map { sample in
            UKSongLeaderboardEntryRowView(
                entry: LeaderboardEntry(
                    accountId: "fre-\(sample.rank)", displayName: sample.name, score: sample.score, rank: sample.rank,
                    accuracy: Double(sample.accuracyPercent) * 10_000, isFullCombo: sample.isFullCombo,
                    stars: sample.isFullCombo ? 6 : 5, season: nil, difficulty: nil
                ),
                isPlayer: false, columns: nil, currentSeason: nil, chevron: nil, horizontalPadding: 14
            )
        }
    }

    /// Builds inert native ranking rows for the Rankings and Compete lessons.
    static func rankingRows(_ entries: [FirstRunDemoPool.RankingEntry]) -> [UIView] {
        entries.map { entry in
            let row = UKRankingRowView()
            row.apply(.init(
                rank: entry.rank, name: entry.name, songs: entry.songs, spokenSongs: "",
                rating: entry.rating, emphasized: entry.isPlayer, identifier: "", opensSomething: false
            ))
            return UKCardRowControl(content: row, selectedBand: entry.isPlayer, onTap: nil)
        }
    }
}

// MARK: - Guide pulse

/// The same read-only pulse as SwiftUI's `firstRunPulse`, shared by UIKit guide surfaces.
@MainActor
final class UKFirstRunPulseGroup {
    private let pulses: [ShopPulseView]
    private let shape: FirstRunGlowShape
    private var accessibilityObserver: UKAccessibilityObserver?
    private nonisolated(unsafe) var sceneObservers: [NSObjectProtocol] = []
    private var active = false

    /// - Parameters:
    ///   - targets: The decorative surfaces receiving the border.
    ///   - shape: The border shared by those surfaces.
    init(targets: [UIView], shape: FirstRunGlowShape) {
        self.shape = shape
        pulses = targets.map { target in
            let pulse = ShopPulseView()
            target.ukPin(pulse)
            return pulse
        }
        accessibilityObserver = UKAccessibilityObserver { [weak self] in self?.updatePulse() }
        let center = NotificationCenter.default
        sceneObservers = [UIScene.didActivateNotification, UIScene.willDeactivateNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let scene = note.object as? UIScene else { return }
                let sceneID = ObjectIdentifier(scene)
                MainActor.assumeIsolated {
                    guard let self, let scene = self.pulses.first?.window?.windowScene,
                          ObjectIdentifier(scene) == sceneID else { return }
                    self.updatePulse(sceneActive: name == UIScene.didActivateNotification)
                }
            }
        }
    }

    deinit { sceneObservers.forEach(NotificationCenter.default.removeObserver) }

    /// - Parameter active: Whether this illustration is on the current slide.
    func setActive(_ active: Bool) {
        self.active = active
        updatePulse()
    }

    /// - Parameter sceneActive: The new scene phase during a UIKit lifecycle notification.
    func updatePulse(sceneActive: Bool? = nil) {
        let foreground = pulses.first?.window?.windowScene?.activationState == .foregroundActive
        let running = FirstRunPulsePolicy.runs(
            slideActive: active && (sceneActive ?? foreground),
            reduceMotion: UKAccessibility.reduceMotion, stillBackground: DebugAnimationOverride.stillBackground
        )
        let layer = ShopPulseLayer(
            shape: shape.pulseShape,
            color: BrandTokens.accentBlue, period: ShopRowPulseBorder.period,
            restingOpacity: ShopRowPulseBorder.peak, running: running
        ) { ShopRowPulseBorder.opacity(at: $0, animating: true) }
        for pulse in pulses { pulse.apply(layer, color: BrandUIColors.accentBlue.cgColor) }
    }
}
#endif
