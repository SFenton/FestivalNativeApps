import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - FestivalTitlePlacement (issue #632)

@Suite("Page title placement")
struct PageTitlePlacementTests {
    @Test("Titles are leading where page tools float (iPhone), the page's own mode elsewhere")
    func resolvesFromTheFloatingToolsWindow() {
        #expect(FestivalTitlePlacement.resolve(floatsPageTools: true) == .leading)
        #expect(FestivalTitlePlacement.resolve(floatsPageTools: false) == .standard)
    }

    @Test("Only a compact tab-bar window gets leading titles; Duo, iPad and Mac keep theirs")
    func followsTheFloatingToolsHost() {
        let phone = FloatingPageToolsHost.floatsPageTools(in: DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 402, height: 874), widthClass: .compact,
            safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        )))
        #expect(phone)
        #expect(FestivalTitlePlacement.resolve(floatsPageTools: phone) == .leading)
        let folded = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 466, height: 678), widthClass: .compact,
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
            verticalBarEdge: .trailing, hinge: .closed
        ))
        #expect(FestivalTitlePlacement.resolve(
            floatsPageTools: FloatingPageToolsHost.floatsPageTools(in: folded)
        ) == .standard)
        let pad = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 1180, height: 820), widthClass: .regular
        ))
        #expect(FestivalTitlePlacement.resolve(
            floatsPageTools: FloatingPageToolsHost.floatsPageTools(in: pad)
        ) == .standard)
    }
}
