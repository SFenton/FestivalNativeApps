import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - SongsToolbarFold (issue #92)

@Suite("Songs Sort and Filter fold")
struct SongsToolbarFoldTests {
    @Test("Standard iPhone widths keep Sort and Filter as two buttons")
    func standardWidthsKeepBoth() {
        for width in [393.0, 402.0, 440.0] {
            #expect(!SongsToolbarFold.folds(width: width, dynamicTypeSize: .large, chrome: .tabBar))
        }
    }

    @Test("Narrow iPhones fold Sort and Filter into one menu")
    func narrowWidthsFold() {
        for width in [320.0, 375.0, 389.0] {
            #expect(SongsToolbarFold.folds(width: width, dynamicTypeSize: .large, chrome: .tabBar))
        }
    }

    @Test("An unmeasured width never folds")
    func unmeasuredWidth() {
        #expect(!SongsToolbarFold.folds(width: 0, dynamicTypeSize: .large, chrome: .tabBar))
    }

    @Test("Accessibility text sizes fold at any width; larger standard sizes do not")
    func dynamicType() {
        #expect(SongsToolbarFold.folds(width: 440, dynamicTypeSize: .accessibility1, chrome: .tabBar))
        #expect(SongsToolbarFold.folds(width: 0, dynamicTypeSize: .accessibility5, chrome: .tabBar))
        #expect(!SongsToolbarFold.folds(width: 402, dynamicTypeSize: .xxxLarge, chrome: .tabBar))
    }

    @Test("The Duo vertical bar and iPad sidebar shell rely on system overflow")
    func systemOverflowChromes() {
        for chrome: DeviceLayout.SectionChrome in [.verticalBar(.leading), .verticalBar(.trailing), .sidebar] {
            #expect(!SongsToolbarFold.folds(width: 320, dynamicTypeSize: .accessibility3, chrome: chrome))
        }
    }
}
