#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalUI

/// At accessibility text sizes a ``MarqueeText`` wraps instead of scrolling or
/// truncating, unless its container opts out (navigation-bar titles).
@MainActor
struct MarqueeAccessibilitySizeTests {
    private let long = "Synthetic Quartet and the Very Long Artist Name"

    /// Height the marquee takes in a 120 pt column at a Dynamic Type size.
    private func height(_ size: DynamicTypeSize, wraps: Bool = true) -> CGFloat {
        let host = NSHostingView(rootView: MarqueeText(long, font: .body)
            .environment(\.dynamicTypeSize, size)
            .environment(\.marqueeWrapsAtAccessibilitySizes, wraps)
            .environment(\.marqueeAnimationEnabled, false)
            .frame(width: 120))
        return host.fittingSize.height
    }

    @Test func wrapsOnlyAtAccessibilitySizes() {
        let standard = height(.xxxLarge)
        let accessibility = height(.accessibility5)
        let optedOut = height(.accessibility5, wraps: false)
        // Wrapping makes the text several lines tall (macOS hosting keeps the font size,
        // so the one-line heights match; iOS also grows the font).
        #expect(accessibility > optedOut * 1.8, "AX5 wraps: \(accessibility) vs one line \(optedOut)")
        #expect(standard <= optedOut, "standard sizes stay on one line")
    }
}
#endif
