#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Monogram

/// The selected player's monogram: the UIKit counterpart of ``ProfileAvatar`` and its
/// ``MonogramImageCache``, drawn with Core Graphics (no SwiftUI `ImageRenderer`).
///
/// A circle with the brand blue→purple gradient and the name's first letter or digit in
/// a rounded semibold face, 46 % of the diameter. The image depends only on the initial,
/// size, scale, rim and overhang, so names sharing an initial share one image.
@MainActor
enum UKMonogram {
    private static var cache: [MonogramImageKey: UIImage] = [:]

    /// The monogram image for a player.
    ///
    /// - Parameters:
    ///   - name: Display name.
    ///   - size: Diameter in points.
    ///   - scale: Display scale.
    ///   - outlined: Whether the avatar draws its 1 pt `glassBorder` rim.
    ///   - overhang: Points the circle draws past its alignment rect on each side
    ///     (``RootProfileButton/MonogramMetrics/overhang``).
    /// - Returns: An original-rendering image `size` points square.
    static func image(
        name: String, size: CGFloat, scale: CGFloat, outlined: Bool = true, overhang: CGFloat = 0
    ) -> UIImage {
        let key = MonogramImageKey(name: name, size: size, scale: scale, outlined: outlined, overhang: overhang)
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = key.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        var image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let cg = context.cgContext
            cg.saveGState()
            cg.addEllipse(in: rect)
            cg.clip()
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [BrandUIColors.accentBlue.cgColor, BrandUIColors.accentPurple.cgColor] as CFArray,
                locations: [0, 1]
            )
            if let gradient {
                cg.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: size, y: size), options: []
                )
            }
            cg.restoreGState()
            if outlined {
                BrandUIColors.glassBorder.setStroke()
                let path = UIBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 1
                path.stroke()
            }
            let descriptor = UIFont.systemFont(ofSize: size * 0.46, weight: .semibold)
                .fontDescriptor.withDesign(.rounded)
            let font = descriptor.map { UIFont(descriptor: $0, size: size * 0.46) }
                ?? .systemFont(ofSize: size * 0.46, weight: .semibold)
            let text = NSAttributedString(
                string: key.initial,
                attributes: [.font: font, .foregroundColor: BrandUIColors.textPrimary]
            )
            let bounds = text.size()
            text.draw(at: CGPoint(x: (size - bounds.width) / 2, y: (size - bounds.height) / 2))
        }.withRenderingMode(.alwaysOriginal)
        if key.overhang > 0 {
            image = image.withAlignmentRectInsets(UIEdgeInsets(top: 0, left: key.overhang, bottom: 0, right: key.overhang))
        }
        cache[key] = image
        return image
    }
}
#endif
