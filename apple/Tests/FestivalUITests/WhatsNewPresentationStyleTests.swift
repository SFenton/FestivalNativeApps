import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

/// What's New opens as a centered sheet only on the iPhone Duo inner display.
struct WhatsNewPresentationStyleTests {
    @Test func duoInnerDisplayUsesASheet() {
        let portrait = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
        ))
        let landscape = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 951, height: 669), widthClass: .regular,
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
            verticalBarEdge: .trailing, hinge: .fullyOpen
        ))
        #expect(WhatsNewPresentationStyle.usesSheet(portrait))
        #expect(WhatsNewPresentationStyle.usesSheet(landscape))
    }

    @Test func iPhoneFoldedDuoAndIPadKeepTheCover() {
        let phone = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 402, height: 874), widthClass: .compact
        ))
        let folded = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 466, height: 678), widthClass: .compact,
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
            verticalBarEdge: .trailing, hinge: .closed
        ))
        let iPad = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 1210, height: 834), widthClass: .regular
        ))
        #expect(!WhatsNewPresentationStyle.usesSheet(phone))
        #expect(!WhatsNewPresentationStyle.usesSheet(folded))
        #expect(!WhatsNewPresentationStyle.usesSheet(iPad))
    }
}
