import CoreGraphics
import FestivalCore
import SwiftUI
import Testing
@testable import FestivalUI

/// Where Paths presents and which view modes it offers (owner, issue #368).
struct SongPathsPolicyTests {
    private let phone = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 402, height: 874), widthClass: .compact
    ))
    /// A large iPhone in landscape is regular width but keeps the sheet.
    private let phoneLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 956, height: 440), widthClass: .regular, heightClass: .compact
    ))
    private let folded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed
    ))
    private let unfolded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    private let unfoldedPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
    ))
    private let book = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .partiallyOpen
    ))
    private let iPad = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 1210, height: 834), widthClass: .regular, usesSidebarShell: true
    ))
    /// An iPad window in Slide Over or a narrow split keeps the tab bar and the sheet.
    private let compactIPad = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 375, height: 834), widthClass: .compact
    ))
    /// A narrow Mac pane: the sidebar shell still covers the whole window.
    private let macPane = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 420, height: 700), widthClass: .compact, usesSidebarShell: true
    ))

    @Test func iPhoneFoldedDuoAndCompactIPadKeepTheSheet() {
        for layout in [phone, phoneLandscape, folded, compactIPad] {
            #expect(SongPathsPolicy.coverage(layout) == .sheet)
            #expect(SongPathsPolicy.modes(for: layout) == [.image, .text])
            #expect(SongPathsPolicy.showsViewMenu(layout))
        }
    }

    @Test func duoInnerDisplayIPadAndMacCoverTheWindowWithThreeModes() {
        for layout in [unfolded, unfoldedPortrait, iPad, macPane] {
            #expect(SongPathsPolicy.coverage(layout) == .fullScreen)
            #expect(SongPathsPolicy.modes(for: layout) == [.image, .text, .sideBySide])
            #expect(SongPathsPolicy.showsViewMenu(layout))
        }
    }

    @Test func bookPoseForcesSideBySide() {
        #expect(book.pose == .partiallyFolded)
        #expect(SongPathsPolicy.coverage(book) == .fullScreen)
        #expect(SongPathsPolicy.modes(for: book) == [.sideBySide])
        #expect(!SongPathsPolicy.showsViewMenu(book))
        for selection in PathViewMode.allCases {
            #expect(SongPathsPolicy.resolve(selection, layout: book, fallback: .image) == .sideBySide)
        }
    }

    @Test func sideBySideFallsBackToTheSettingsDefaultWhereItDoesNotFit() {
        #expect(SongPathsPolicy.resolve(.sideBySide, layout: folded, fallback: .text) == .text)
        #expect(SongPathsPolicy.resolve(.sideBySide, layout: phone, fallback: .image) == .image)
        #expect(SongPathsPolicy.resolve(.text, layout: folded, fallback: .image) == .text)
        #expect(SongPathsPolicy.resolve(.sideBySide, layout: unfolded, fallback: .text) == .sideBySide)
        #expect(SongPathsPolicy.resolve(.image, layout: iPad, fallback: .text) == .image)
    }

    @Test func modesLoadTheirFormsImageFirst() {
        #expect(PathViewMode.image.displays == [.image])
        #expect(PathViewMode.text.displays == [.text])
        #expect(PathViewMode.sideBySide.displays == [.image, .text])
        #expect(PathViewMode(.text) == .text)
        #expect(PathViewMode.allCases.map(\.label) == ["Image", "Text", "Side by Side"])
    }

    #if os(macOS)
    @Test func macFullWindowSheetMatchesTheParentContentArea() {
        #expect(MacWindowSizedSheet<EmptyView>.size(window: CGSize(width: 1280, height: 748))
            == CGSize(width: 1280, height: 748))
        #expect(MacWindowSizedSheet<EmptyView>.size(window: CGSize(width: 400, height: 300))
            == MacWindowSizedSheet<EmptyView>.minimumSize)
        #expect(MacWindowSizedSheet<EmptyView>.size(window: nil) == MacWindowSizedSheet<EmptyView>.minimumSize)
    }
    #endif
}
