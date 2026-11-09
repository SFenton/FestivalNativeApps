#if os(iOS)
import FestivalDesign
import Testing
import UIKit
@testable import FestivalCore
@testable import FestivalUI

extension UKFoundationTests {
@MainActor
private final class UKTraitContentContainer: UIViewController {
    private let child: UIViewController
    private let traits: UITraitCollection

    init(child: UIViewController, traits: UITraitCollection) {
        self.child = child
        self.traits = traits
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(child)
        view.addSubview(child.view)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        setOverrideTraitCollection(traits, forChild: child)
        child.didMove(toParent: self)
    }
}

/// Focused UIKit component checks for the shared feature views owned by this lane.
@MainActor
@Suite(.serialized)
struct UKFeatureComponentTests {
    @Test
    func marqueeDebugStopRestoresTheRequestWithoutDiscardingNormalAnimationState() {
        let state = PerfComponentDebugState()
        let id = UUID()
        state.beginMarqueeComponent()

        #expect(!state.marqueeComponentReady)
        state.marqueeRequested = true
        state.updateMarquee(
            id, rendererClass: "MarqueeText", overflow: true, visible: true,
            reduceMotion: false, sceneActive: true, animation: true,
            textLength: 40, textWidth: 300, viewportWidth: 120
        )
        #expect(state.marqueeComponentReady)

        state.marqueeRequested = false
        #expect(!state.marqueeComponentRestored)
        state.removeMarquee(id)
        #expect(state.marqueeComponentRestored)

        let normal = PerfComponentDebugState()
        normal.updateMarquee(
            id, rendererClass: "MarqueeText", overflow: true, visible: true,
            reduceMotion: false, sceneActive: true, animation: true,
            textLength: 40, textWidth: 300, viewportWidth: 120
        )
        normal.beginMarqueeComponent()
        normal.marqueeRequested = true
        normal.marqueeRequested = false
        #expect(normal.marqueeComponentRestored)
        #expect(normal.marqueeAnimating)
    }

    @Test
    func explicitFirstContentMarkerReportsActualLoadedBodyCount() async throws {
        FirstContentProbe.reset()
        defer { FirstContentProbe.reset() }
        FirstContentProbe.markFirstContent(rows: 4)
        let probe = FirstContentProbe()
        probe.start()
        defer { probe.stop() }

        for _ in 0..<10 where probe.contentMs == nil {
            try await Task.sleep(for: .milliseconds(16))
        }

        #expect(probe.contentMs != nil)
        #expect(probe.contentSource == "explicit")
        #expect(probe.visibleRows == 4)
    }

    @Test
    func chartDateAxisKeepsNewestAndAvoidsOverlaps() {
        let centres: [CGFloat] = [8, 24, 40, 56, 72, 88]
        let widths: [CGFloat] = Array(repeating: 22, count: centres.count)
        let bounds = CGRect(x: 0, y: 0, width: 96, height: 0)

        let shown = UKChartDateAxis.visibleIndices(
            centres: centres, widths: widths, bounds: bounds, minimumGap: 6
        )
        #expect(shown.last == centres.indices.last)
        #expect(shown == [0, 2, 5])
    }

    @Test
    func chartDateAxisPinsLabelsInsideThePlot() {
        let frames = UKChartDateAxis.labelFrames(
            centres: [-20, 50, 120], widths: [30, 30, 30],
            bounds: CGRect(x: 0, y: 20, width: 100, height: 24), height: 24
        )
        #expect(frames.map(\.minX) == [0, 35, 70])
        #expect(frames.allSatisfy { $0.minY == 20 && $0.height == 24 })
    }

    @Test
    func hostedMarqueeLayoutSettlesAfterApplyingUnchangedText() async throws {
        let harness = try await UKHostedWindow.make()
        defer { harness.close() }
        let marquee = UKMarqueeLabel("A deliberately overflowing fixture title")
        harness.root.view.addSubview(marquee)
        NSLayoutConstraint.activate([
            marquee.centerXAnchor.constraint(equalTo: harness.root.view.centerXAnchor),
            marquee.topAnchor.constraint(equalTo: harness.root.view.safeAreaLayoutGuide.topAnchor, constant: 24),
            marquee.widthAnchor.constraint(equalToConstant: 120),
            marquee.heightAnchor.constraint(equalToConstant: 28),
        ])
        try await UKHostedWindow.wait { marquee.window === harness.window && marquee.bounds.width == 120 }
        harness.window.layoutIfNeeded()

        #expect(marquee.window === harness.window)
        #expect(!marquee.layer.needsLayout())
    }

    @Test
    func sharedChartMathBuildsAPathForEmptySingleAndMultiplePoints() {
        #expect(UKChartMath.monotonePath([]) == nil)
        let single = UKChartMath.monotonePath([CGPoint(x: 0, y: 1)])
        #expect(single != nil)
        let multiple = UKChartMath.monotonePath([
            CGPoint(x: 0, y: 1), CGPoint(x: 20, y: 4), CGPoint(x: 40, y: 2)
        ])
        #expect(multiple != nil)
    }

    @Test
    func sharedMetadataFieldKeepsSpokenStateAtAccessibilitySize() {
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let field = UKSongMetadataFieldView(
            field: .season(15, current: true), traits: traits,
            accessibilityIdentifier: "fst.feature-component.season"
        )

        let size = field.fittedSize(maxWidth: 240)
        #expect(size.height >= 44)
        #expect(field.isAccessibilityElement)
        #expect(field.accessibilityLabel == "Current season 15")
        #expect(field.accessibilityIdentifier == "fst.feature-component.season")
    }

    @Test
    func sharedMetadataFieldHasARealHostedAccessibilityTarget() async throws {
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let field = UKSongMetadataFieldView(
            field: .percentile("Top 1%", tier: .topOne), traits: traits,
            accessibilityIdentifier: "fst.feature-component.percentile"
        )
        let size = field.fittedSize(maxWidth: 240)
        let controller = UIViewController()
        controller.loadViewIfNeeded()
        controller.view.backgroundColor = BrandUIColors.appBackground
        field.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(field)
        NSLayoutConstraint.activate([
            field.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            field.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 24),
            field.widthAnchor.constraint(equalToConstant: size.width),
            field.heightAnchor.constraint(equalToConstant: size.height),
        ])

        let hosted = try await UKHostedWindow.make()
        defer { hosted.close() }
        try await hosted.present(controller)
        try await UKHostedWindow.wait {
            field.window != nil && controller.view.window != nil && field.bounds.height > 0
        }

        let screenFrame = UIAccessibility.convertToScreenCoordinates(field.bounds, in: field)
        #expect(screenFrame.height >= 44)
        #expect(field.accessibilityLabel == "Top 1%")
        #expect(field.accessibilityTraits == UIAccessibilityTraits.staticText)
    }

    @Test
    func bandSongPercentileConsumerKeepsCanonicalPillMetricsAndRowOwnedA11y() {
        let pill = UKPercentilePillView(topPercent: 1)
        let size = pill.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)

        #expect(size.width >= 80)
        #expect(size.height >= 28)
        #expect(!pill.isAccessibilityElement)
    }

    @Test
    func leaderboardCellExposesItsHostedRowAccessibilityContainer() {
        let cell = UKLeaderboardRowCell(frame: CGRect(x: 0, y: 0, width: 320, height: 48))
        let entry = ScoreHistoryEntry(
            songId: "fixture-pulse", instrument: Instrument.lead.rawValue, newScore: 850_000,
            accuracy: 991_200, isFullCombo: false, season: 40, changedAt: "2024-02-08T00:00:00Z"
        )
        let model = UKBoardScoreHistoryRowView.Model(
            entry: entry, isBest: true, seasonColumn: false, currentSeason: nil,
            columns: nil, identifier: "fst.history.row.0"
        )
        let row = UKLeaderboardRow(
            kind: .history, make: { UKBoardScoreHistoryRowView() },
            apply: { ($0 as? UKBoardScoreHistoryRowView)?.apply(model) },
            bare: true
        )

        cell.configure(row, segment: FestivalGroupSegment(isFirst: true, isLast: true))

        #expect(!cell.isAccessibilityElement)
        #expect(!cell.contentView.isAccessibilityElement)
        #expect(cell.accessibilityElements?.count == 1)
        #expect(cell.contentView.accessibilityElements?.count == 1)
        let host = cell.accessibilityElements?.first as? UKBoardScoreHistoryRowView
        #expect(host?.accessibilityElements?.count == 1)
        #expect((host?.accessibilityElements?.first as? UKScoreHistoryRowView)?.accessibilityIdentifier == "fst.history.row.0")
        var ancestor: UIView? = host
        while let view = ancestor, view !== cell {
            #expect(!view.isHidden, "A bare score row must not remain inside the hidden cell card")
            ancestor = view.superview
        }
        #expect(!cell.isHidden)
    }

    @Test
    func rankingRowsStackFullScoreValuesAtAccessibilitySize() async throws {
        let content = UIViewController()
        let row = UKRankingRowView()
        content.view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.view.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: content.view.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: content.view.topAnchor),
            row.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
        ])
        let model = UKRankingRowView.Model(
            rank: 1, name: "Fixture Player 1", songs: "79 / 100", spokenSongs: "79 songs",
            rating: "178,000,000", bayesian: nil, columns: nil, identifier: "fst.feature-ranking-row",
            opensSomething: true
        )
        let hosted = try await UKHostedWindow.make()
        defer { hosted.close() }
        let container = UKTraitContentContainer(
            child: content,
            traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )
        try await hosted.present(container)
        row.apply(model)
        try await UKHostedWindow.wait { row.window != nil && row.bounds.height >= 100 }

        #expect(row.bounds.height >= 100)
        #expect(row.accessibilityLabel?.contains("178,000,000") == true)
    }

    @Test
    func boardRowsSelfSizeInTwoColumnsAtNormalAndAX5TextSizes() async throws {
        let model = UKRankingRowView.Model(
            rank: 1, name: "Fixture Team One", songs: "79 / 100", spokenSongs: "79 songs",
            rating: "178,000,000", bayesian: nil, columns: nil, identifier: "fst.feature-board-row",
            opensSomething: true
        )
        let row = UKLeaderboardRow(
            kind: .ranking,
            make: { UKRankingRowView() },
            apply: { ($0 as? UKRankingRowView)?.apply(model) }
        )
        let categories: [(UIContentSizeCategory, CGFloat)] = [
            (.large, 44),
            (.accessibilityExtraExtraExtraLarge, UIFont.preferredFont(
                forTextStyle: .body,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            ).lineHeight * 2),
        ]

        for (category, minimumHeight) in categories {
            let board = UKBoardView(
                gateKey: "board-row-sizing-\(category.rawValue)", isLoading: false,
                spinnerLabel: "Loading", spinnerIdentifier: nil, retainsFrame: false
            )
            board.setColumns(2)
            board.setContent(
                headViews: [],
                rowItems: [("row-1", row), ("row-2", row)]
            )
            let content = UIViewController()
            content.view.addSubview(board)
            board.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                board.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
                board.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
                board.topAnchor.constraint(equalTo: content.view.topAnchor),
                board.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
            ])
            let container = UKTraitContentContainer(child: content, traits: UITraitCollection(
                preferredContentSizeCategory: category
            ))
            let hosted = try await UKHostedWindow.make()
            defer { hosted.close() }
            try await hosted.present(container)
            board.reconfigureRows()
            try await UKHostedWindow.wait {
                board.collectionView.layoutIfNeeded()
                let cells = board.collectionView.visibleCells.compactMap { $0 as? UKLeaderboardRowCell }
                return cells.count == 2 && cells.allSatisfy { $0.bounds.height >= minimumHeight }
            }

            let cells = board.collectionView.visibleCells.compactMap { $0 as? UKLeaderboardRowCell }
            try #require(cells.count == 2)
            #expect(cells.allSatisfy { $0.bounds.height >= minimumHeight }, "\(category.rawValue): \(cells.map(\.bounds))")
            for cell in cells {
                let frame = cell.convert(cell.bounds, to: board.collectionView)
                #expect(frame.minX >= 0, "\(category.rawValue): \(frame)")
                #expect(frame.maxX <= board.collectionView.bounds.width, "\(category.rawValue): \(frame)")
            }
        }
    }

    @Test
    func songBoardRowsExposeHostedAXStopAndActivateAtAX5() async throws {
        let entry = LeaderboardEntry(
            accountId: "fixture-player-25", displayName: "Fixture Player 25", score: 178_000_000,
            rank: 1, localRank: nil, accuracy: 991_200, isFullCombo: false, stars: 5, season: 40, difficulty: 3
        )
        var activationCount = 0
        let row = UKLeaderboardRow(
            kind: .song,
            make: { UKSongScoreRowView() },
            apply: {
                ($0 as? UKSongScoreRowView)?.apply(.init(
                    entry: entry, columns: nil, identifier: "fst.song-leaderboard.row.fixture-player-25"
                ))
            },
            onTap: { activationCount += 1 },
            detailSelection: nil
        )
        let board = UKBoardView(
            gateKey: "song-board-cell-hit-surface", isLoading: false,
            spinnerLabel: "Loading", spinnerIdentifier: nil, retainsFrame: false
        )
        board.setContent(headViews: [], rowItems: [("row-1", row)])
        let content = UIViewController()
        content.view.addSubview(board)
        board.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            board.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            board.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
            board.topAnchor.constraint(equalTo: content.view.topAnchor),
            board.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
        ])
        let hosted = try await UKHostedWindow.make()
        defer { hosted.close() }
        let container = UKTraitContentContainer(
            child: content,
            traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )
        try await hosted.present(container)
        try await UKHostedWindow.wait {
            board.collectionView.layoutIfNeeded()
            return board.collectionView.visibleCells.contains {
                ($0 as? UKLeaderboardRowCell)?.accessibilityElements?.first is UKSongScoreRowView
            }
        }

        func hostedRow(in cell: UKLeaderboardRowCell) -> UKSongLeaderboardEntryRowView? {
            (cell.accessibilityElements?.first as? UKSongScoreRowView)?.accessibilityElements?.first
                as? UKSongLeaderboardEntryRowView
        }
        let visibleCells = board.collectionView.visibleCells.compactMap { $0 as? UKLeaderboardRowCell }
        let targetIdentifier = "fst.song-leaderboard.row.fixture-player-25"
        let visibleDump = visibleCells.map { cell in
            let row = hostedRow(in: cell)
            return "\(String(describing: type(of: cell))): id=\(row?.accessibilityIdentifier ?? "<nil>") frame=\(cell.frame) rowFrame=\(row?.frame ?? .zero) rowAX=\(row?.isAccessibilityElement ?? false) traits=\(row?.accessibilityTraits.rawValue ?? 0) onTap=\(row?.onTap != nil)"
        }.joined(separator: " | ")
        let match = visibleCells.first { hostedRow(in: $0)?.accessibilityIdentifier == targetIdentifier }
        let cell = try #require(match, "No visible configured terminal row \(targetIdentifier); \(visibleDump)")
        #expect(cell.bounds.height >= 44)
        let terminalRow = try #require(hostedRow(in: cell), "\(visibleDump)")
        #expect(terminalRow.accessibilityIdentifier == targetIdentifier)
        #expect(terminalRow.isAccessibilityElement, "\(visibleDump)")
        #expect(terminalRow.accessibilityTraits == .button, "\(visibleDump)")
        #expect(terminalRow.accessibilityLabel?.contains("Fixture Player 25") == true, "\(visibleDump)")
        #expect(terminalRow.bounds.height >= 44)
        #expect(terminalRow.point(inside: CGPoint(x: terminalRow.bounds.midX, y: terminalRow.bounds.midY), with: nil))
        #expect(terminalRow.accessibilityActivate())
        #expect(activationCount == 1)
    }

    @Test
    func songLeaderboardRowsKeepAX5HeightAndCellOwnedInteraction() {
        let entry = LeaderboardEntry(
            accountId: "fixture-player-1", displayName: "Fixture Player 1", score: 178_000_000,
            rank: 1, localRank: nil, accuracy: 991_200, isFullCombo: false, stars: 5, season: 40, difficulty: 3
        )
        let row = UKSongLeaderboardEntryRowView(
            entry: entry, isPlayer: false, columns: nil, currentSeason: nil,
            chevron: true, separateParts: true, horizontalPadding: 14,
            traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )
        let size = row.systemLayoutSizeFitting(
            CGSize(width: 320, height: 1000),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(size.height >= 100)
        #expect(row.isEnabled)
        #expect(row.isUserInteractionEnabled)

        var activationCount = 0
        row.onTap = { activationCount += 1 }
        #expect(row.isAccessibilityElement)
        #expect(row.accessibilityLabel?.contains("Fixture Player 1") == true)
        #expect(row.accessibilityTraits == .button)
        #expect(row.accessibilityActivate())
        #expect(activationCount == 1)

        row.onTap = nil
        #expect(!row.isAccessibilityElement)
        #expect(row.accessibilityLabel == nil)
        #expect(!row.accessibilityTraits.contains(.button))
        #expect(!row.accessibilityActivate())
        #expect(activationCount == 1)

        row.onTap = { activationCount += 1 }
        #expect(row.isAccessibilityElement)
        #expect(row.accessibilityLabel?.contains("Fixture Player 1") == true)
        #expect(row.accessibilityTraits == .button)
        #expect(row.accessibilityActivate())
        #expect(activationCount == 2)
    }

    @Test
    func songStatusChipsStayHiddenInsideTheRowAccessibilityContainer() {
        let chips = UKSongStatusChipsView(
            badges: [SongInstrumentBadge(instrument: .lead, status: .noScore)],
            keyboard: false, traits: .current, accessibilityIdentifier: "fst.feature-status"
        )

        #expect(!chips.isAccessibilityElement)
        #expect(chips.accessibilityElementsHidden)
    }

    @Test
    func formActionRowsKeepTheirNativeTouchTargetAtDefaultTextSize() async throws {
        let harness = try await UKHostedWindow.make()
        defer { harness.close() }
        let form = UKFormViewController()
        let button = form.buttonRow("Reset Filters", color: .red, identifier: "fst.test.reset", action: {})
        button.translatesAutoresizingMaskIntoConstraints = false
        harness.root.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: harness.root.view.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: harness.root.view.trailingAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: harness.root.view.safeAreaLayoutGuide.topAnchor, constant: 20),
        ])
        harness.root.view.layoutIfNeeded()

        #expect(button.window === harness.window)
        #expect(button.bounds.height >= 44)
        #expect(button.bounds.width >= 44)
    }

    @Test
    func rowSwitchDoesNotHandleNativeSwitchDescendantTouchesTwice() {
        let row = UIView()
        let label = UILabel()
        let toggle = UKRowSwitch()
        let switchChild = UIView()
        row.addSubview(label)
        row.addSubview(toggle)
        toggle.addSubview(switchChild)
        toggle.installRowTap(on: row)

        #expect(toggle.handlesRowTap(from: label))
        #expect(!toggle.handlesRowTap(from: toggle))
        #expect(!toggle.handlesRowTap(from: switchChild))

        var changes = 0
        toggle.addAction(UIAction { _ in changes += 1 }, for: .valueChanged)
        toggle.flip()
        #expect(toggle.isOn)
        #expect(changes == 1)
        toggle.isEnabled = false
        toggle.flip()
        #expect(changes == 1)
    }

    @Test
    func paddedSwitchAccessibilityTargetIsAlsoARealTouchTarget() async throws {
        let harness = try await UKHostedWindow.make()
        defer { harness.close() }
        let holder = UIView(frame: CGRect(x: 20, y: 100, width: 300, height: 44))
        let row = UKToggleRow(
            title: "Has Scores", hint: nil, identifier: "fst.test.has-scores", accessibilityHint: nil
        )
        row.frame = CGRect(x: 16, y: 6, width: 268, height: 32)
        holder.addSubview(row)
        harness.root.view.addSubview(holder)
        row.layoutIfNeeded()
        let point = CGPoint(x: holder.bounds.maxX - 12, y: holder.bounds.midY)

        #expect(holder.hitTest(point, with: nil) === row)
        let target = row.convert(row.bounds.inset(by: row.toggle.framePadding), to: harness.window)
        let activationPoint = holder.convert(point, to: harness.window)
        #expect(target.contains(activationPoint))
    }

    @Test
    func bottomSearchFieldKeepsARealNativeInputTarget() async throws {
        let harness = try await UKHostedWindow.make()
        defer { harness.close() }
        let search = UKBottomSearchField(
            prompt: "Filter Songs", label: "Filter Songs", identifier: "fst.test.bottom-field",
            clearIdentifier: "fst.test.bottom-clear"
        )
        search.install(in: harness.root, layout: { .standardPhone })
        harness.root.view.layoutIfNeeded()
        let height = search.bounds.height
        #expect(search.field.bounds.height >= 44)
        #expect(search.field.bounds.width > search.bounds.width / 2)

        search.text = "Fixture"
        harness.root.view.layoutIfNeeded()
        #expect(search.field.bounds.height >= 44)
        #expect(search.field.bounds.width > search.bounds.width / 2)
        #expect(search.bounds.height == height)
    }

    @Test
    func reusedRowsDropTheirPreviousDetailSelectionOwner() async throws {
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let shell = UKShellState()
        shell.selectedSection = .leaderboards
        shell.splitOpen = true
        let context = UKContext(session: session).with {
            $0.shell = shell
            $0.section = .leaderboards
        }
        let route = AppRoute.fullRankings(instrument: .lead, rankBy: "totalscore")
        let button = UIButton()
        button.ukBindDetailSelection(route, context: context)
        shell.detailSelection = route
        try await UKHostedWindow.wait { button.isSelected }

        button.ukClearDetailSelection()
        shell.detailSelection = nil
        shell.detailSelection = route
        await Task.yield()
        #expect(!button.isSelected)
        #expect(!button.accessibilityTraits.contains(.selected))
    }

    @Test
    func detailSelectionFollowsTheWindowRouteAndClearsOnClose() async throws {
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let shell = UKShellState()
        shell.selectedSection = .leaderboards
        let context = UKContext(session: session).with {
            $0.shell = shell
            $0.section = .leaderboards
        }
        let route = AppRoute.fullRankings(instrument: .lead, rankBy: "totalscore")
        let button = UIButton()
        button.accessibilityTraits = .button
        button.ukBindDetailSelection(route, context: context)
        shell.splitOpen = true
        shell.detailSelection = route
        try await UKHostedWindow.wait { button.isSelected }
        #expect(button.accessibilityTraits.contains(.selected))

        shell.detailSelection = nil
        shell.splitOpen = false
        try await UKHostedWindow.wait { !button.isSelected }
        #expect(!button.accessibilityTraits.contains(.selected))
    }
}
}
#endif
