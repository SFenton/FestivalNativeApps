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
}
