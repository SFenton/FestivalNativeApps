import CoreGraphics

// MARK: - Profile avatar pixels

/// Measures the selected player's top-bar avatar in a screenshot (issue #311).
///
/// The avatar is a blue-to-purple disc (`BrandTokens.accentBlue` → `accentPurple`). On
/// iOS 26 it must fill the bar item's whole 44 pt circle with no Liquid Glass ring
/// around it. Before #311 a 30 pt outlined disc sat inside the item's 44 pt glass
/// circle, so the measured disc was 30 pt and a lighter glass band surrounded it.
///
/// Kept free of XCTest so the same measurement can be checked against saved PNGs.
struct ProfileAvatarPixels {
    /// One avatar measurement, in points.
    struct Measurement: Equatable {
        /// Disc width in points.
        let width: CGFloat
        /// Disc height in points.
        let height: CGFloat
        /// Disc centre in screenshot points.
        let center: CGPoint
        /// Median luminance (0–255) of the band just outside the disc minus the band
        /// farther out, over the leading, upper and trailing rays. A glass ring around
        /// the disc lifts the inner band; a borderless disc on the bar leaves it flat.
        let rimLift: Double
    }

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

    /// Ray directions (unit vectors, y down) that stay in the bar: leading, upper
    /// leading, up, upper trailing and trailing. Content can scroll under the bar below
    /// the avatar, so downward rays are not sampled.
    static let rays: [CGVector] = [
        CGVector(dx: -1, dy: 0), CGVector(dx: -0.7071, dy: -0.7071), CGVector(dx: 0, dy: -1),
        CGVector(dx: 0.7071, dy: -0.7071), CGVector(dx: 1, dy: 0),
    ]
    /// Band just outside the disc edge, in points from the edge.
    static let innerBand: ClosedRange<CGFloat> = 1.5...4.5
    /// Reference band farther out, in points from the edge.
    static let outerBand: ClosedRange<CGFloat> = 8...11

    /// Whether a pixel belongs to the avatar's blue-to-purple fill.
    ///
    /// - Parameters:
    ///   - red: Red channel, 0–255.
    ///   - green: Green channel, 0–255.
    ///   - blue: Blue channel, 0–255.
    /// - Returns: True for the saturated brand blue/purple; false for glass, the bar,
    ///   artwork and the white initial.
    static func isAvatar(red: Int, green: Int, blue: Int) -> Bool {
        blue >= 170 && blue - red >= 60 && blue - green >= 60
    }

    /// Measure the avatar disc near a button.
    ///
    /// - Parameters:
    ///   - frame: The profile button's frame in screenshot points.
    ///   - margin: Points searched beyond the frame on every side.
    /// - Returns: The disc's size, centre and rim lift, or nil when no avatar pixels are
    ///   found.
    func measure(around frame: CGRect, margin: CGFloat = 16) -> Measurement? {
        let search = frame.insetBy(dx: -margin, dy: -margin)
        let minX = max(Int((search.minX * scale).rounded(.down)), 0)
        let maxX = min(Int((search.maxX * scale).rounded(.up)), width - 1)
        let minY = max(Int((search.minY * scale).rounded(.down)), 0)
        let maxY = min(Int((search.maxY * scale).rounded(.up)), height - 1)
        guard minX < maxX, minY < maxY else { return nil }
        // Count per column/row, so a few stray brand-coloured pixels cannot widen the box.
        var columns = [Int](repeating: 0, count: maxX - minX + 1)
        var rows = [Int](repeating: 0, count: maxY - minY + 1)
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = (y * width + x) * 4
                if Self.isAvatar(
                    red: Int(pixels[offset]), green: Int(pixels[offset + 1]),
                    blue: Int(pixels[offset + 2])
                ) {
                    columns[x - minX] += 1
                    rows[y - minY] += 1
                }
            }
        }
        let minimum = max(Int(scale), 2)
        guard let left = columns.firstIndex(where: { $0 >= minimum }),
              let right = columns.lastIndex(where: { $0 >= minimum }),
              let top = rows.firstIndex(where: { $0 >= minimum }),
              let bottom = rows.lastIndex(where: { $0 >= minimum }) else { return nil }
        let widthPixels = CGFloat(right - left + 1)
        let heightPixels = CGFloat(bottom - top + 1)
        let center = CGPoint(
            x: CGFloat(minX + left) + widthPixels / 2, y: CGFloat(minY + top) + heightPixels / 2
        )
        let radius = (widthPixels + heightPixels) / 4
        let lifts = Self.rays.compactMap { ray -> Double? in
            guard let inner = bandLuminance(center, radius, ray, Self.innerBand),
                  let outer = bandLuminance(center, radius, ray, Self.outerBand) else { return nil }
            return inner - outer
        }.sorted()
        return Measurement(
            width: widthPixels / scale, height: heightPixels / scale,
            center: CGPoint(x: center.x / scale, y: center.y / scale),
            rimLift: lifts.isEmpty ? 0 : lifts[lifts.count / 2]
        )
    }

    /// Mean luminance along a ray between two distances past the disc edge.
    ///
    /// - Parameters:
    ///   - center: Disc centre in pixels.
    ///   - radius: Disc radius in pixels.
    ///   - ray: Unit direction.
    ///   - band: Distances past the edge, in points.
    /// - Returns: Mean luminance 0–255, or nil if the band leaves the bitmap.
    private func bandLuminance(
        _ center: CGPoint, _ radius: CGFloat, _ ray: CGVector, _ band: ClosedRange<CGFloat>
    ) -> Double? {
        var total = 0.0
        var count = 0
        var distance = radius + band.lowerBound * scale
        while distance <= radius + band.upperBound * scale {
            let x = Int((center.x + ray.dx * distance).rounded())
            let y = Int((center.y + ray.dy * distance).rounded())
            guard x >= 0, x < width, y >= 0, y < height else { return nil }
            let offset = (y * width + x) * 4
            total += 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                + 0.0722 * Double(pixels[offset + 2])
            count += 1
            distance += 1
        }
        return count == 0 ? nil : total / Double(count)
    }
}
