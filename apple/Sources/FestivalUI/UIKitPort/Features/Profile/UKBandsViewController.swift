#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Bands landing

/// `/bands`: the band lookup landing page (``BandsScreen``). Band search by member name lives
/// in global search's Bands scope (issue #320); this page offers the selected player's own
/// bands and links into the public Band Rankings boards. Pure navigation: it makes no
/// request of its own.
@MainActor
final class UKBandsViewController: UKProfileScrollViewController {
    /// Creates the page.
    ///
    /// - Parameter context: The screen's context.
    override init(context: UKContext) {
        super.init(context: context)
        readableWidth = ReadableWidthContainer.columnWidth
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ukSetPageTitle("Bands")
        scrollView.accessibilityIdentifier = "fst.bands.screen"
        observations.observe { [weak self] in self?.rebuild() }
    }

    private var built = false

    private func rebuild() {
        let player = session.selectedPlayer
        var sections: [UIView] = []
        if let player {
            let section = UKGroupSectionView("Your Bands")
            let row = UKProfileChevronRow(title: "View \(player.displayName)'s Bands", identifier: "fst.bands.your-bands")
            row.onTap = { [weak self] in
                self?.context.navigator?.push(.playerBands(accountId: player.accountId, displayName: player.displayName, group: .all))
            }
            section.setRows([row])
            sections.append(section)
        }
        let rankings = UKGroupSectionView("Band Rankings", subtitle: "Public rankings by band size.")
        rankings.setRows(BandType.allCases.map { bandType in
            let row = UKProfileChevronRow(title: bandType.label, identifier: "fst.bands.rankings.\(bandType.rawValue)")
            row.onTap = { [weak self] in
                self?.context.navigator?.push(.bandRankings(bandType: bandType.rawValue))
            }
            return row
        })
        sections.append(rankings)
        let note = UKFootnoteLabel("To find a band by a member's name, use Search.")
        sections.append(UKProfileInset(note, horizontal: UKProfileMetrics.headerInset))
        setSections(sections, fadeIn: !built)
        built = true
    }
}
#endif
