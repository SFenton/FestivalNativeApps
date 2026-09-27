#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

/// Keep real AppKit-backed controls in a sized native host for fixture tests.
///
/// - Parameters:
///   - content: SwiftUI screen with its actual native pickers and text fields.
///   - size: Window-like content dimensions in points, not backing pixels.
/// - Returns: Offscreen native host that can survive asynchronous state changes.
@MainActor
func nativeHostedView<Content: View>(
    _ content: Content, size: CGSize
) -> NSHostingView<Content> {
    let host = NSHostingView(rootView: content)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    return host
}

/// Realize lazy AppKit List rows without presenting a window to the operator.
///
/// - Parameters:
///   - host: Already sized native SwiftUI host.
///   - size: Matching content dimensions in points.
/// - Returns: A never-shown offscreen window the caller retains while capturing rows.
@MainActor
func nativeHostedWindow<Content: View>(
    _ host: NSHostingView<Content>, size: CGSize
) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(
            x: -10_000, y: -10_000, width: size.width, height: size.height
        ),
        styleMask: .borderless, backing: .buffered, defer: false
    )
    window.contentView = host
    window.orderOut(nil)
    host.layoutSubtreeIfNeeded()
    return window
}

/// Capture native widgets instead of ImageRenderer's yellow AppKit placeholders.
///
/// - Parameter host: The same retained host after the state being asserted has settled.
/// - Returns: Composited pixels at the host's actual backing scale.
/// - Throws: An unavailable native bitmap or missing image.
@MainActor
func nativeHostedImage<Content: View>(_ host: NSHostingView<Content>) throws -> CGImage {
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return try #require(bitmap.cgImage)
}

/// Recognize real bright labels and selected controls without exact ColorSync RGB guesses.
///
/// - Parameter image: Native AppKit bitmap at its actual backing scale.
/// - Returns: Sampled bright text, selected blue and yellow pixels. A view with
///   intentional gold content cannot treat every yellow pixel as a placeholder.
@MainActor
func nativeHostedControlPixels(_ image: CGImage) -> (
    bright: Int, selected: Int, placeholder: Int
) {
    let bitmap = NSBitmapImageRep(cgImage: image)
    var bright = 0
    var selected = 0
    var placeholder = 0
    for y in stride(from: 0, to: image.height, by: 4) {
        for x in stride(from: 0, to: image.width, by: 4) {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            let red = color.redComponent
            let green = color.greenComponent
            let blue = color.blueComponent
            if min(red, green, blue) > 0.7 { bright += 1 }
            if blue > 0.6 && green > 0.25 && red < 0.55
                && blue > red * 1.3 { selected += 1 }
            if red > 0.8 && green > 0.6 && blue < 0.25 { placeholder += 1 }
        }
    }
    return (bright, selected, placeholder)
}

/// Optionally retain synthetic native screenshots outside the source worktree.
///
/// - Parameters:
///   - image: AppKit-hosted bitmap to encode as PNG.
///   - filename: Deterministic evidence name for this view and state.
///   - environment: Optional private output directory variable.
/// - Returns: PNG bytes for deterministic state comparison.
/// - Throws: Missing PNG data or an explicitly requested output-write failure.
@MainActor
func nativeHostedPNG(
    _ image: CGImage, filename: String, environment: String
) throws -> Data {
    let png = try #require(
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    )
    if let directory = ProcessInfo.processInfo.environment[environment] {
        try png.write(
            to: URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(filename),
            options: .atomic
        )
    }
    return png
}
#endif
