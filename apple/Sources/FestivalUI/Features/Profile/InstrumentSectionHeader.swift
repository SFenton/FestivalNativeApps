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
///
/// A combo board's header (Compete, issue #602) is the web `CompeteScopeHeader`: its
/// instruments' icons in a row (`Gap.sm`, 4 pt) above the "Lead + Bass" label (`Gap.xs`, 2 pt).
struct InstrumentSectionHeader<Trailing: View>: View {
    /// Web `InstrumentHeaderSize` subset used on these pages.
    enum Size {
        case small
        case medium

        var icon: CGFloat { self == .small ? 36 : 48 }
        var font: Font { self == .small ? .subheadline.bold() : .title3.bold() }
        var spacing: CGFloat { self == .small ? 8 : 12 }
    }

    /// The board the header titles: one instrument, or a combo.
    let scope: RankingScope
    var title: String?
    var size: Size = .small
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: size.spacing) {
            switch scope {
            case let .instrument(instrument):
                InstrumentIcon(instrument, size: size.icon)
                    .accessibilityHidden(true)
                label
            case let .combo(combo):
                VStack(alignment: .leading, spacing: 2) {
                    InstrumentIconRow(instruments: combo.instruments, side: size.icon)
                    label
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 4)
    }

    private var label: some View {
        Text(title ?? scope.label)
            .font(size.font)
            .foregroundStyle(FestivalText.primary)
            .accessibilityAddTraits(.isHeader)
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
        self.init(scope: .instrument(instrument), title: title, size: size)
    }

    /// A header for one instrument's or a combo's board, with no trailing accessory.
    ///
    /// - Parameters:
    ///   - scope: The board: an instrument (icon beside its name) or a combo (icons above
    ///     the "Lead + Bass" label).
    ///   - title: Label override (defaults to the scope's name).
    ///   - size: Web header size.
    init(scope: RankingScope, title: String? = nil, size: Size = .small) {
        self.scope = scope
        self.title = title
        self.size = size
        self.trailing = { EmptyView() }
    }
}
