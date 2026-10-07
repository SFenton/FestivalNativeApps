import SwiftUI
import Testing
@testable import FestivalUI
#if os(macOS)
import AppKit
#endif

// MARK: - Full-width top scrim (issue #335)

/// The page's top gradient extends under the top and both horizontal safe areas (the
/// iPhone Duo vertical bar is a leading or trailing inset), never the bottom.
@Test func topScrimExtendsUnderTheVerticalBarEdges() {
    let edges = TopEdgeScrim.extendedEdges
    #expect(edges.contains(.top))
    #expect(edges.contains(.leading))
    #expect(edges.contains(.trailing))
    #expect(!edges.contains(.bottom))
}

#if os(macOS)
/// A page beside a horizontal safe-area inset (standing in for the Duo vertical bar)
/// darkens its top edge equally on both sides of the inset's edge: the backdrop under
/// the bar gets the same scrim as the page.
@MainActor
@Test(arguments: [HorizontalEdge.trailing, .leading])
func topScrimDarkensUnderTheBarLikeThePage(barEdge: HorizontalEdge) throws {
    let size = CGSize(width: 400, height: 300)
    let bar: CGFloat = 60
    let page = ZStack {
        Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1).ignoresSafeArea()
        Color.clear.modifier(TopEdgeScrim())
    }
    .safeAreaInset(edge: barEdge) { Color.clear.frame(width: bar) }
    let host = nativeHostedView(page, size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try nativeHostedImage(host)
    let scale = CGFloat(image.width) / size.width

    // Points either side of the bar's inner edge, near the top (inside the gradient).
    let edgeX = barEdge == .trailing ? size.width - bar : bar
    let underBar = barEdge == .trailing ? edgeX + bar / 2 : edgeX - bar / 2
    let onPage = barEdge == .trailing ? edgeX - bar / 2 : edgeX + bar / 2
    let bitmap = NSBitmapImageRep(cgImage: image)
    func luminance(x: CGFloat, y: CGFloat) throws -> CGFloat {
        let color = try #require(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale)))
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3
    }
    for y: CGFloat in [4, 40] {
        let bar = try luminance(x: underBar, y: y)
        let content = try luminance(x: onPage, y: y)
        // The scrim is present at all (darker than the 0.5 backdrop) ...
        #expect(content < 0.45)
        // ... and the same under the bar as on the page.
        #expect(abs(bar - content) < 0.02, "y \(y): bar \(bar) vs page \(content)")
    }
    // Below the gradient both sides show the undimmed backdrop.
    #expect(abs(try luminance(x: underBar, y: 280) - luminance(x: onPage, y: 280)) < 0.02)
}
#endif
