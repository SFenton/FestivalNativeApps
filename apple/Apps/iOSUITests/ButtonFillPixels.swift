import CoreGraphics

// MARK: - Button fill pixels

/// Measures how much of a control's frame a screenshot paints in one hue (issue #351).
///
/// The Player page's Select / Switch action is a prominent (`.borderedProminent`) item
/// filled with `AccentText.prominentFill` (sRGB 31, 108, 203) in every placement,
/// including the iPhone Duo vertical bar; the drawer's Deselect is a red bordered
/// button. A plain rail symbol (the pre-#351 rendering) is a white glyph on dark glass,
/// so almost none of its frame is blue.
///
/// Kept free of XCTest so the same measurement can be checked against saved PNGs.
struct ButtonFillPixels {
    /// A pixel colour test on 0–255 channels.
    typealias Classifier = @Sendable (_ red: Int, _ green: Int, _ blue: Int) -> Bool

    /// RGBA bytes, premultiplied, row-major.
    let pixels: [UInt8]
    /// Bitmap width in pixels.
    let width: Int
    /// Bitmap height in pixels.
    let height: Int
    /// Pixels per point.
    let scale: CGFloat

    /// Wrap an RGBA bitmap.
    ///
    /// - Parameters:
    ///   - pixels: RGBA bytes, premultiplied, row-major.
    ///   - width: Bitmap width in pixels.
    ///   - height: Bitmap height in pixels.
    ///   - scale: Pixels per point.
    init(pixels: [UInt8], width: Int, height: Int, scale: CGFloat) {
        self.pixels = pixels
        self.width = width
        self.height = height
        self.scale = scale
    }

    /// Draw a screenshot into an RGBA bitmap.
    ///
    /// - Parameters:
    ///   - image: The screenshot.
    ///   - pointWidth: The screenshot's width in points.
    /// - Returns: Nil if the bitmap context cannot be created.
    init?(image: CGImage, pointWidth: CGFloat) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn, pointWidth > 0 else { return nil }
        self.init(
            pixels: bytes, width: image.width, height: image.height,
            scale: CGFloat(image.width) / pointWidth
        )
    }

    // MARK: - Classifiers

    /// The saturated accent blue of a prominent fill (`AccentText.prominentFill`, sRGB
    /// 31, 108, 203, possibly lightened by Liquid Glass). Rejects the white glyph, grey
    /// glass, the dark backdrop and the blue-to-purple avatar's purple end.
    static let accentBlue: Classifier = { red, green, blue in
        blue >= 150 && blue - red >= 90 && blue - green >= 40 && green >= red
    }

    /// The bright red of a destructive control's system-red title (the dark red-tinted
    /// `.bordered` capsule behind it is too dim to count).
    static let destructiveRed: Classifier = { red, green, blue in
        red >= 90 && red - green >= 45 && red - blue >= 45
    }

    // MARK: - Measurement

    /// The fraction of a frame's pixels that pass a classifier.
    ///
    /// - Parameters:
    ///   - frame: The control's frame in screenshot points.
    ///   - classifier: The pixel colour test.
    /// - Returns: 0…1, or nil when the frame lies outside the bitmap.
    func fraction(in frame: CGRect, matching classifier: Classifier) -> Double? {
        let minX = max(Int((frame.minX * scale).rounded(.up)), 0)
        let maxX = min(Int((frame.maxX * scale).rounded(.down)), width) - 1
        let minY = max(Int((frame.minY * scale).rounded(.up)), 0)
        let maxY = min(Int((frame.maxY * scale).rounded(.down)), height) - 1
        guard minX < maxX, minY < maxY else { return nil }
        var matched = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = (y * width + x) * 4
                if classifier(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2])) {
                    matched += 1
                }
            }
        }
        return Double(matched) / Double((maxX - minX + 1) * (maxY - minY + 1))
    }
}
