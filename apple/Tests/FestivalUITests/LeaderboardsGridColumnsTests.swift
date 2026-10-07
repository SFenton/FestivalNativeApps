import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - Leaderboards overview columns

/// The overview's two-column card grid keeps every card at least the Android
/// overview's 340 pt minimum (issue #352: a landscape iPad split's ~605 pt leading
/// pane drew ~276 pt cards that cut names to a few characters).
struct LeaderboardsGridColumnsTests {
    @Test func compactWidthIsAlwaysOneColumn() {
        #expect(!LeaderboardsScreen.usesTwoColumns(widthClass: .compact, contentWidth: 2_000))
        #expect(!LeaderboardsScreen.usesTwoColumns(widthClass: .compact, contentWidth: nil))
    }

    @Test func unmeasuredRegularWidthKeepsTwoColumns() {
        #expect(LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: nil))
        #expect(LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: 0))
    }

    @Test func narrowSplitPaneDropsToOneColumn() {
        // 11-inch iPad landscape split: the leading pane is 604.5 pt wide.
        #expect(!LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: 604.5))
        // 13-inch iPad landscape split: about 688 pt.
        #expect(!LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: 688))
    }

    @Test func fullWidthIPadKeepsTwoColumns() {
        // Portrait and landscape 11-inch iPad, no split.
        #expect(LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: 834))
        #expect(LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: 1_210))
    }

    @Test func thresholdIsTwoMinimumCardsPlusGapAndPadding() {
        let edge = 2 * LeaderboardsScreen.minimumCardWidth + LeaderboardsScreen.cardSpacing
            + 2 * LeaderboardsScreen.pagePadding
        #expect(LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: edge))
        #expect(!LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: edge - 1))
    }

    @Test func largerTextNeedsWiderCards() {
        // At a 1.5× Dynamic Type scale the 834 pt portrait iPad drops to one column.
        let scaled = LeaderboardsScreen.minimumCardWidth * 1.5
        #expect(!LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: 834, minimumCardWidth: scaled))
        #expect(LeaderboardsScreen.usesTwoColumns(widthClass: .regular, contentWidth: 1_210, minimumCardWidth: scaled))
    }
}
