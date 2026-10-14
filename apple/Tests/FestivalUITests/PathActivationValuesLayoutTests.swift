#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Paths activation values (#626)

/// Fitted size of three fixed-width blocks (Beat, Time, Score stand-ins) laid out by
/// `PathActivationValuesLayout` when offered `width`.
///
/// - Parameters:
///   - widths: Each block's width; every block is 20 pt tall.
///   - width: The offered row width.
///   - alwaysStacked: The accessibility-size flag.
/// - Returns: The layout's fitted size.
@MainActor
private func fittedValues(_ widths: [CGFloat], width: CGFloat, alwaysStacked: Bool = false) -> CGSize {
    let view = PathActivationValuesLayout(alwaysStacked: alwaysStacked) {
        ForEach(Array(widths.enumerated()), id: \.offset) { _, blockWidth in
            Color.white.frame(width: blockWidth, height: 20)
        }
    }
    return NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 10_000))
}

/// Equal columns need the widest value's natural width in each third, not just the sum.
@Test func activationValuesFitRuleUsesTheWidestColumn() {
    // 40 + 120 + 40 + gaps = 224 fits 300 by sum, but three 120-pt columns need 384.
    #expect(!PathActivationValuesLayout.fitsSideBySide(widths: [40, 120, 40], available: 300))
    #expect(PathActivationValuesLayout.fitsSideBySide(widths: [40, 120, 40], available: 384))
    #expect(!PathActivationValuesLayout.fitsSideBySide(widths: [40, 120, 40], available: 383))
    #expect(PathActivationValuesLayout.fitsSideBySide(widths: [40, 120, 40], available: nil))
}

/// Values sit side by side in one row while they fit, else stack, and always stack at
/// accessibility sizes, so the time never shrinks to keep the columns.
@MainActor
@Test func activationValuesStackRatherThanSqueeze() {
    let side = fittedValues([40, 120, 40], width: 400)
    #expect(side.height == 20, "side by side is one row: \(side)")
    let stacked = fittedValues([40, 120, 40], width: 300)
    let stackHeight = 20 * 3 + PathActivationValuesLayout.stackSpacing * 2
    #expect(stacked.height == stackHeight, "a squeezed row stacks: \(stacked)")
    let accessibility = fittedValues([40, 120, 40], width: 400, alwaysStacked: true)
    #expect(accessibility.height == stackHeight, "accessibility sizes stack: \(accessibility)")
}
#endif
