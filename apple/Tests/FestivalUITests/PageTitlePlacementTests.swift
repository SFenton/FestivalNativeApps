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

    @Test("Leading titles are inline in the editor role; elsewhere the page keeps its own mode")
    func resolvesTheDisplayModeAndRole() {
        for mode in [FestivalTitlePlacement.PageMode.automatic, .inline, .large] {
            #expect(FestivalTitlePlacement.leading.displayMode(for: mode) == .inline)
            #expect(FestivalTitlePlacement.standard.displayMode(for: mode) == mode)
        }
        #expect(FestivalTitlePlacement.leading.usesEditorRole)
        #expect(!FestivalTitlePlacement.standard.usesEditorRole)
    }

    @Test("A page's automatic title call adopts the explicit mode set around it (#633)")
    func automaticAdoptsTheOuterExplicitMode() {
        #expect(FestivalTitlePlacement.effectiveMode(.automatic, outer: nil) == .automatic)
        #expect(FestivalTitlePlacement.effectiveMode(.automatic, outer: .large) == .large)
        #expect(FestivalTitlePlacement.effectiveMode(.automatic, outer: .inline) == .inline)
        #expect(FestivalTitlePlacement.effectiveMode(.inline, outer: .large) == .inline)
        #expect(FestivalTitlePlacement.effectiveMode(.large, outer: nil) == .large)
    }

    @Test("Every tab-bar window gets leading titles; the Duo rail, iPad sidebar and Mac keep theirs")
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
            size: CGSize(width: 1180, height: 820), widthClass: .regular, usesSidebarShell: true
        ))
        #expect(FestivalTitlePlacement.resolve(
            floatsPageTools: FloatingPageToolsHost.floatsPageTools(in: pad)
        ) == .standard)
        // iPhone Duo inner portrait: the horizontal tab bar takes the iPhone header (#633).
        let innerPortrait = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
        ))
        #expect(FestivalTitlePlacement.resolve(
            floatsPageTools: FloatingPageToolsHost.floatsPageTools(in: innerPortrait)
        ) == .leading)
    }
}
