import Vision
import XCTest

/// Rendered-pixel contrast for accessibility-audit issues on iPad
/// (`.agents/testing/apple/accessibility.md`, iPad section).
///
/// The audit's contrast verdicts on iPadOS 26.5 misjudge white text on translucent
/// materials and glass. This measures the element's own frame in a full-screen capture
/// taken in the same run: the glyph pixels' upper quartile (text core) against the median
/// pixel (surface), as a WCAG luminance ratio (``measure(luminances:)``). A
/// contrast waiver (``IPadAuditWaivers``) only applies when this measurement passes.
enum IPadAuditRenderedContrast {
    /// The interface orientation when `XCUIDevice` does not know it: iPhone Duo's pose and
    /// rotation come from Device Hub, so the audit sets this from the app window's aspect.
    @MainActor static var interfaceIsLandscape: Bool?
    /// The app window's size in points, when the screen to capture must be chosen by it:
    /// on iPhone Duo `XCUIScreen.main` is the outer display, black while the app runs on
    /// the inner one (measured 2026-10-05: 1398 × 2034 px of black for a 951 × 669 pt window).
    @MainActor static var windowSize: CGSize?
    /// iPhone Duo: the quarter turn that reads upright, found once by text recognition
    /// (Device Hub decides the inner display's rotation, so `XCUIDevice` cannot say).
    @MainActor static var duoClockwise: Bool?

    // MARK: - Capture

    /// A full-screen capture with the screen's size in points, in the current interface
    /// orientation.
    struct Capture {
        /// Opaque RGBA bytes, row-major.
        let pixels: [UInt8]
        /// Bitmap width in pixels.
        let width: Int
        /// Bitmap height in pixels.
        let height: Int
        /// Screen size in points in the same orientation as the bitmap.
        let screen: CGSize
        /// The upright image (written next to the JSON as evidence).
        let image: CGImage
        /// True when the raw capture was portrait while the interface was landscape.
        let rotated: Bool

        /// Capture the whole screen (element frames are screen coordinates, so a ⅓ window
        /// away from the screen origin still maps correctly).
        ///
        /// In landscape the simulator's capture can stay in portrait framebuffer
        /// orientation; the capture is rotated upright when its aspect disagrees with the
        /// interface orientation (see ``upright(_:landscape:)``).
        ///
        /// - Returns: The capture, or nil when no bitmap is available.
        @MainActor
        static func screen() -> Capture? {
            let shot = screenshotMatchingWindow().image
            guard let raw = shot.cgImage else { return nil }
            let landscape = interfaceIsLandscape ?? XCUIDevice.shared.orientation.isLandscape
            let image: CGImage?
            if windowSize != nil, landscape, raw.height > raw.width {
                image = duoUpright(raw, scale: max(1, shot.scale))
            } else {
                image = upright(raw, landscape: landscape)
            }
            guard let image, let pixels = try? bitmapPixels(image) else { return nil }
            // Points from the bitmap itself: SpringBoard's frame (1194 pt) is shorter than
            // the 11-inch framebuffer (1210 pt) the app's window and frames use.
            let scale = max(1, shot.scale)
            let points = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            return Capture(pixels: pixels, width: image.width, height: image.height, screen: points,
                           image: image, rotated: image !== raw)
        }
    }

    /// The screenshot of the screen showing the app: `XCUIScreen.main`, or with
    /// ``windowSize`` set the screen whose size matches the window in either orientation.
    @MainActor
    static func screenshotMatchingWindow() -> XCUIScreenshot {
        guard let window = windowSize else { return XCUIScreen.main.screenshot() }
        for screen in XCUIScreen.screens {
            let shot = screen.screenshot()
            let scale = max(1, shot.image.scale)
            let size = CGSize(width: shot.image.size.width * shot.image.scale / scale,
                              height: shot.image.size.height * shot.image.scale / scale)
            let matches = { (a: CGSize) in abs(a.width - window.width) < 3 && abs(a.height - window.height) < 3 }
            if matches(size) || matches(CGSize(width: size.height, height: size.width)) { return shot }
        }
        return XCUIScreen.main.screenshot()
    }

    /// Turn a portrait iPhone Duo inner-display framebuffer upright for a landscape
    /// window, choosing the direction once by which reads more text.
    @MainActor
    static func duoUpright(_ raw: CGImage, scale: CGFloat) -> CGImage? {
        func turned(_ clockwise: Bool) -> CGImage? { rotate(raw, clockwise: clockwise) }
        if let known = duoClockwise { return turned(known) }
        // Upside-down text is also "recognized" (equal line counts on the inner display,
        // 2026-10-05), so score by confidence-weighted characters: upright text reads
        // with high confidence, flipped text as low-confidence fragments.
        let scores = [true, false].map { clockwise -> Double in
            guard let image = turned(clockwise) else { return 0 }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return 0 }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first }
                .reduce(0) { $0 + Double($1.confidence) * Double($1.string.count) }
        }
        duoClockwise = scores[0] > scores[1]
        return turned(duoClockwise ?? false)
    }

    /// A quarter turn of `image`.
    static func rotate(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let width = image.height, height = image.width
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        if clockwise {
            context.translateBy(x: CGFloat(width), y: 0)
            context.rotate(by: .pi / 2)
        } else {
            context.translateBy(x: 0, y: CGFloat(height))
            context.rotate(by: -.pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    // MARK: - Measurement

    /// One rendered measurement.
    struct Measurement: Codable, Equatable {
        /// WCAG contrast ratio between the text pixels and the surface.
        let ratio: Double
        /// Pixels that differ from the surface by at least 1.5× luminance (glyph coverage).
        let glyphPixels: Int
    }

    /// Measure the rendered contrast inside `frame` (screen points).
    ///
    /// - Parameters:
    ///   - frame: The element frame reported by the audit.
    ///   - capture: The run's full-screen capture.
    /// - Returns: The measurement, or nil when the frame is empty, offscreen or covers
    ///   most of the screen (a container frame says nothing about one text run).
    static func measure(_ frame: CGRect, in capture: Capture) -> Measurement? {
        let screenRect = CGRect(origin: .zero, size: capture.screen)
        let visible = frame.intersection(screenRect)
        guard !visible.isNull, visible.width >= 4, visible.height >= 4,
              visible.width * visible.height < screenRect.width * screenRect.height * 0.25 else { return nil }
        let scaleX = Double(capture.width) / capture.screen.width
        let scaleY = Double(capture.height) / capture.screen.height
        let minX = max(0, Int(visible.minX * scaleX)), maxX = min(capture.width, Int(visible.maxX * scaleX))
        let minY = max(0, Int(visible.minY * scaleY)), maxY = min(capture.height, Int(visible.maxY * scaleY))
        guard maxX > minX, maxY > minY else { return nil }
        var luminances: [Double] = []
        luminances.reserveCapacity((maxX - minX) * (maxY - minY))
        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = (y * capture.width + x) * 4
                luminances.append(luminance(capture.pixels[offset], capture.pixels[offset + 1], capture.pixels[offset + 2]))
            }
        }
        return measure(luminances: luminances)
    }

    /// Glyph-core contrast: the upper quartile of the glyph pixels against the surface.
    ///
    /// The surface is the median pixel of the crop. Glyph pixels differ from it by at
    /// least 1.5× (WCAG luminance ratio), lighter or darker, whichever set is larger (the
    /// text's polarity). Their upper quartile (towards the stronger end) is the text's core
    /// colour: anti-aliased fringes and a pill's tinted outline sit below it. It does not
    /// depend on how much of a wide frame the text fills (a fixed top percentile of the
    /// whole crop read a 296 pt "Settings" row at 2.8:1 although its text is 17:1), and the
    /// median of the glyph pixels read 11 pt pill text at 4.3:1 where its colours give 6:1.
    /// Callers crop to one recognized word (``IPadAuditPageEvidence/reading(for:label:lines:capture:)``)
    /// so a differently coloured icon in the same element is left out.
    ///
    /// - Parameter luminances: Relative luminances of one crop's pixels.
    /// - Returns: The ratio and glyph pixel count.
    static func measure(luminances: [Double]) -> Measurement? {
        guard !luminances.isEmpty else { return nil }
        let sorted = luminances.sorted()
        let surface = sorted[sorted.count / 2] + 0.05
        let light = sorted.filter { ($0 + 0.05) / surface >= 1.5 }
        let dark = sorted.filter { surface / ($0 + 0.05) >= 1.5 }
        guard !(light.isEmpty && dark.isEmpty) else { return Measurement(ratio: 1, glyphPixels: 0) }
        // Sorted ascending: the light core is near the top, the dark core near the bottom.
        let core = light.count >= dark.count
            ? light[light.count * 3 / 4] + 0.05
            : dark[dark.count / 4] + 0.05
        let ratio = max(core / surface, surface / core)
        return Measurement(ratio: (ratio * 100).rounded() / 100, glyphPixels: max(light.count, dark.count))
    }

    /// WCAG relative luminance of one sRGB pixel.
    static func luminance(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Double {
        func linear(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    // MARK: - Bitmaps

    /// Rotate a capture upright when it is portrait while the interface is landscape.
    ///
    /// The simulator keeps its framebuffer in portrait while `XCUIDevice.orientation`
    /// rotates the interface; the content is then drawn rotated a quarter turn. A
    /// landscape-left interface (home edge on the left) reads upright after rotating the
    /// framebuffer clockwise.
    ///
    /// - Parameters:
    ///   - image: The raw capture.
    ///   - landscape: True when the interface orientation is landscape.
    /// - Returns: An upright image, or the input when no rotation is needed.
    static func upright(_ image: CGImage, landscape: Bool) -> CGImage? {
        let isPortrait = image.height > image.width
        guard landscape, isPortrait else { return image }
        let width = image.height, height = image.width
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let orientation = XCUIDevice.shared.orientation
        // Core Graphics' origin is bottom-left; rotate about the new canvas.
        if orientation == .landscapeRight {
            context.translateBy(x: 0, y: CGFloat(height))
            context.rotate(by: -.pi / 2)
        } else {
            context.translateBy(x: CGFloat(width), y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Decode an image into opaque RGBA bytes.
    static func bitmapPixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
