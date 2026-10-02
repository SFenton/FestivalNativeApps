import CoreGraphics
import SwiftUI

// MARK: - Row layout

/// Whether a Songs row puts its instrument chips on one line beside the title (the
/// web's desktop `songRow`: artwork, a ≥ 200 px info column and the chip row, 64 px
/// tall) instead of under it (the web's mobile row), decided from the row's actual
/// width like the web's container-width `resolveCompactRowMode`.
///
/// Opt-in per shell through ``SwiftUI/EnvironmentValues/songRowsAllowSingleLine``:
/// the Mac turns it on (HIG Designing for macOS: "Use large displays to show more
/// content … while keeping information density comfortable"); iPhone and iPad keep
/// their layout until their lanes adopt it.
enum SongRowLayoutPolicy {
    /// Chip side and gap (web `InstrumentSize.chip` 34, `Gap.sm` 4).
    static let chipSide: CGFloat = 34
    static let chipGap: CGFloat = 4
    /// Narrowest title/artist column beside the chips (marquee scrolls longer text).
    static let infoMinimumWidth: CGFloat = 180
    /// Card padding (12 pt each side), artwork (44 pt) and the three 12 pt gaps.
    static let fixedWidth: CGFloat = 24 + 44 + 36
    /// The Item Shop bag's slot after the chips (16 pt plus a 12 pt gap), reserved on
    /// every one-line row so chips align down the list whether or not a song is in
    /// the Shop.
    static let shopSlotWidth: CGFloat = 16
    static let shopSlotGap: CGFloat = 12

    /// Width one line of chips needs.
    ///
    /// - Parameter count: Number of chips.
    /// - Returns: The chip row's width in points.
    static func chipRowWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * chipSide + CGFloat(count - 1) * chipGap
    }

    /// Whether the chips fit on one line beside the title.
    ///
    /// - Parameters:
    ///   - width: The row card's width in points (0 before layout).
    ///   - chipCount: Instrument chips shown.
    /// - Returns: True for the one-line layout. Independent of the row's own Shop
    ///   state, so every row of a list takes the same layout.
    static func fitsSingleLine(width: CGFloat, chipCount: Int) -> Bool {
        guard width > 0, chipCount > 0 else { return false }
        let needed = fixedWidth + infoMinimumWidth + chipRowWidth(count: chipCount)
            + shopSlotWidth + shopSlotGap
        return width >= needed
    }
}

extension EnvironmentValues {
    /// Whether Songs rows may put instrument chips beside the title when they fit
    /// (``SongRowLayoutPolicy``); set by the Mac shell.
    @Entry var songRowsAllowSingleLine = false
}
