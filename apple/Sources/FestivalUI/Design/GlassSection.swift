import SwiftUI
import FestivalDesign

// MARK: - Section card

/// A titled group of rows on one Festival material card (``View/festivalCard(cornerRadius:)``) — the native form of the web's
/// `SectionHeader` + `FrostedCard` pair (Settings, Profile, Statistics cards).
///
/// The header sits **outside** the card (white, Title Case) like the web; rows inside
/// are separated by inset hairlines on iOS 18+ and by spacing on iOS 17.
///
/// ```swift
/// FestivalGlassSection("Item Shop", subtitle: "Control how Item Shop availability is displayed.") {
///     Toggle("Hide Item Shop", isOn: $hideShop)
///     Toggle("Highlight Shop Items", isOn: $highlight)
/// }
/// ```
///
/// Repeated entries that draw their own row padding (leaderboard previews, score
/// history, Rivals-style lists) use ``FestivalGroupRows/flush(separatorInset:)``: one
/// card per group, edge-to-edge rows clipped to the card's corners, and
/// ``EnvironmentValues/festivalGroupedRow`` set so each row drops its own card and
/// draws flat fills instead (issue #381, surface-materials R6/R11).
public struct FestivalGlassSection<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let rowStyle: FestivalGroupRows
    private let content: Content

    /// The card's corner radius (the Rivals and Settings group card).
    static var cornerRadius: CGFloat { 22 }

    /// Create a section card.
    ///
    /// - Parameters:
    ///   - title: Title Case header, or nil for an untitled card.
    ///   - subtitle: Optional muted description under the title.
    ///   - rows: How the card lays out its rows; ``FestivalGroupRows/padded`` by default.
    ///   - content: Rows; each top-level child becomes one row.
    public init(
        _ title: String? = nil, subtitle: String? = nil, rows: FestivalGroupRows = .padded,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rowStyle = rows
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                FestivalSectionHeader(title, subtitle: subtitle)
                    .padding(.horizontal, 4)
            }
            card
        }
    }

    /// The rows on the shared material card; flush rows are clipped to its corners so a
    /// selected row's full-width fill follows the card's shape.
    @ViewBuilder private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        switch rowStyle {
        case .padded:
            rows
                .frame(maxWidth: .infinity, alignment: .leading)
                .festivalCard(cornerRadius: Self.cornerRadius)
        case .flush:
            rows
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.festivalGroupedRow, true)
                .clipShape(shape)
                .festivalCard(cornerRadius: Self.cornerRadius)
        }
    }

    /// Each child view as a row, with hairline separators where supported.
    @ViewBuilder private var rows: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(BrandTokens.glassBorder)
                                .frame(height: 1)
                                .padding(.leading, rowStyle.separatorInset)
                                .accessibilityHidden(true)
                        }
                        switch rowStyle {
                        case .padded: row.modifier(FestivalRowPadding())
                        case .flush: row
                        }
                    }
                }
            }
        } else {
            switch rowStyle {
            case .padded:
                VStack(alignment: .leading, spacing: 4) {
                    content.modifier(FestivalRowPadding())
                }
                .padding(.vertical, 4)
            case .flush:
                // iOS 17 / macOS 14 cannot enumerate subviews: flush rows stack without
                // hairlines, one card still holding them.
                VStack(alignment: .leading, spacing: 0) { content }
            }
        }
    }
}

// MARK: - Row style

/// How a ``FestivalGlassSection`` lays out its rows.
public enum FestivalGroupRows: Equatable, Sendable {
    /// Settings-style controls: each child padded to a 44 pt (Mac 28 pt) row, hairlines
    /// inset 16 pt.
    case padded
    /// Repeated entries that bring their own padding and minimum height (leaderboard,
    /// score-history and rival rows): no extra padding, hairlines inset to the rows'
    /// text, and rows told they are grouped (``EnvironmentValues/festivalGroupedRow``).
    ///
    /// - Parameter separatorInset: Leading hairline inset, matching the rows' own
    ///   horizontal padding.
    case flush(separatorInset: CGFloat = 12)

    /// The leading inset of the hairline between two rows.
    var separatorInset: CGFloat {
        switch self {
        case .padded: 16
        case .flush(let inset): inset
        }
    }
}

// MARK: - Grouped-row environment

extension EnvironmentValues {
    /// True for a row inside a flush ``FestivalGlassSection``: the group card is the
    /// row's surface, so the row draws no card of its own and keeps only flat,
    /// full-width fills (the selected player's purple), with Mac hover and focus
    /// following the row's rectangle rather than a separate rounded card (issue #381).
    @Entry var festivalGroupedRow: Bool = false
}

/// Standard row insets and minimum hit height inside a section card: 44 pt on touch
/// platforms, the Mac's 28 pt default control size (HIG Accessibility › Mobility) so
/// pointer-driven forms stay dense.
struct FestivalRowPadding: ViewModifier {
    #if os(macOS)
    private static let minimumHeight: CGFloat = 28
    #else
    private static let minimumHeight: CGFloat = 44
    #endif

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }
}

// MARK: - Supporting text

/// Muted footnote row used for explanations inside a section card.
public struct FestivalFootnote: View {
    private let text: String

    /// Create a footnote row.
    ///
    /// - Parameter text: Sentence-case explanatory text.
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(FestivalText.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
