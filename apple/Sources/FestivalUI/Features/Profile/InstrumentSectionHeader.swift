import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - InstrumentSectionHeader

/// The web's `InstrumentHeader` (`components/display/InstrumentHeader.tsx`): an instrument
/// icon and its name, drawn **above** the card it titles, never inside it (operator rule,
/// 2026-09-28).
///
/// Sizes follow the web config: `.small` = `InstrumentHeaderSize.SM` (36 pt icon, bold
/// 14 pt label; Rivals, Compete), `.medium` = `MD` (48 pt icon, bold 20 pt label; player
/// profile). Labels scale with Dynamic Type and are white (`FestivalText.primary`).
struct InstrumentSectionHeader<Trailing: View>: View {
    /// Web `InstrumentHeaderSize` subset used on these pages.
    enum Size {
        case small
        case medium

        var icon: CGFloat { self == .small ? 36 : 48 }
        var font: Font { self == .small ? .subheadline.bold() : .title3.bold() }
        var spacing: CGFloat { self == .small ? 8 : 12 }
    }

    let instrument: Instrument
    var title: String?
    var size: Size = .small
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: size.spacing) {
            InstrumentIcon(instrument, size: size.icon)
                .accessibilityHidden(true)
            Text(title ?? instrument.label)
                .font(size.font)
                .foregroundStyle(FestivalText.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 4)
    }
}

extension InstrumentSectionHeader where Trailing == EmptyView {
    /// A header with no trailing accessory.
    ///
    /// - Parameters:
    ///   - instrument: Chart whose icon and name to draw.
    ///   - title: Label override (defaults to the instrument name).
    ///   - size: Web header size.
    init(_ instrument: Instrument, title: String? = nil, size: Size = .small) {
        self.instrument = instrument
        self.title = title
        self.size = size
        self.trailing = { EmptyView() }
    }
}
