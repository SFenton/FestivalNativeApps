import SwiftUI
import FestivalCore

// MARK: - Instrument icon

/// Bundled instrument artwork matching the web app's `/instruments/*.png` assets.
public struct InstrumentIcon: View {
    private let instrument: Instrument
    private let keyboard: Bool
    private let size: CGFloat

    /// Create an instrument icon.
    ///
    /// - Parameters:
    ///   - instrument: Chart whose icon to show.
    ///   - keyboard: Use the keys variant for Lead/Pro Lead when the song `sig` is `Keyboard`.
    ///   - size: Point width and height of the square icon.
    public init(_ instrument: Instrument, keyboard: Bool = false, size: CGFloat = 20) {
        self.instrument = instrument
        self.keyboard = keyboard
        self.size = size
    }

    public var body: some View {
        Image(Self.assetName(for: instrument, keyboard: keyboard), bundle: .module)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityLabel(instrument.label)
    }

    /// Resolve the bundled resource name for an instrument.
    ///
    /// - Parameters:
    ///   - instrument: Chart whose icon to resolve.
    ///   - keyboard: Whether to prefer the keys variant for Lead/Pro Lead.
    /// - Returns: Resource name inside `Resources/Instruments`.
    static func assetName(for instrument: Instrument, keyboard: Bool) -> String {
        let file: String = switch instrument {
        case .lead: keyboard ? "keys" : "guitar"
        case .bass: "bass"
        case .drums: "drums"
        case .vocals: "vocals"
        case .proLead: keyboard ? "pro_keys" : "pro_guitar"
        case .proBass: "pro_bass"
        case .karaoke: "peripheral_vocals"
        case .proCymbals: "peripheral_cymbals"
        case .proDrums: "peripheral_drums"
        }
        return "instrument_\(file)"
    }

    // MARK: - Menu image

    /// Side of an instrument icon inside a native menu or pop-up button, in points.
    static let menuIconSide: CGFloat = 24

    @MainActor private static var menuImages: [String: Image] = [:]

    /// The instrument artwork pre-sized for a native menu item or pop-up button.
    ///
    /// Menus render a label's image at its intrinsic size, ignoring `resizable()` and
    /// `frame`, and the bundled artwork is 144 pt; this redraws it once at
    /// ``menuIconSide`` (original colours) and reuses it.
    ///
    /// - Parameters:
    ///   - instrument: Chart whose icon to show.
    ///   - keyboard: Use the keys variant for Lead/Pro Lead when the song `sig` is `Keyboard`.
    /// - Returns: An original-colour image ``menuIconSide`` points square.
    @MainActor
    static func menuImage(for instrument: Instrument, keyboard: Bool) -> Image {
        let name = assetName(for: instrument, keyboard: keyboard)
        if let cached = menuImages[name] { return cached }
        let image: Image
        #if canImport(UIKit)
        image = menuPlatformImage(for: instrument, keyboard: keyboard).map(Image.init(uiImage:))
            ?? Image(name, bundle: .module)
        #elseif canImport(AppKit)
        image = menuPlatformImage(for: instrument, keyboard: keyboard).map(Image.init(nsImage:))
            ?? Image(name, bundle: .module)
        #else
        image = Image(name, bundle: .module)
        #endif
        menuImages[name] = image
        return image
    }

    #if canImport(UIKit)
    /// The bundled artwork redrawn at ``menuIconSide`` points in original colours.
    ///
    /// - Parameters:
    ///   - instrument: Chart whose icon to draw.
    ///   - keyboard: Use the keys variant for Lead/Pro Lead.
    /// - Returns: The resized image, or nil if the asset is missing.
    static func menuPlatformImage(for instrument: Instrument, keyboard: Bool) -> UIImage? {
        guard let source = UIImage(
            named: assetName(for: instrument, keyboard: keyboard), in: .module, compatibleWith: nil
        ) else { return nil }
        let size = CGSize(width: menuIconSide, height: menuIconSide)
        return UIGraphicsImageRenderer(size: size).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        .withRenderingMode(.alwaysOriginal)
    }
    #elseif canImport(AppKit)
    /// The bundled artwork sized to ``menuIconSide`` points (a copy; the asset is shared).
    ///
    /// - Parameters:
    ///   - instrument: Chart whose icon to draw.
    ///   - keyboard: Use the keys variant for Lead/Pro Lead.
    /// - Returns: The resized image, or nil if the asset is missing.
    static func menuPlatformImage(for instrument: Instrument, keyboard: Bool) -> NSImage? {
        guard let source = Bundle.module.image(
            forResource: assetName(for: instrument, keyboard: keyboard)
        )?.copy() as? NSImage else { return nil }
        source.size = NSSize(width: menuIconSide, height: menuIconSide)
        return source
    }
    #endif
}
