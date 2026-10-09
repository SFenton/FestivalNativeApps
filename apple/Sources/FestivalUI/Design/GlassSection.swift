import SwiftUI
import FestivalDesign

// MARK: - Section card

/// A titled group of rows on one Festival material card (``View/festivalCard(cornerRadius:)``) — the native form of the web's
/// `SectionHeader` + `FrostedCard` pair (Settings, Profile, Statistics cards).
///
/// The header sits **outside** the card (white, Title Case) like the web; rows inside
/// are separated by inset hairlines (padded rows on iOS 17 / macOS 14 by spacing; flush
/// rows keep their hairlines there too).
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
///
/// A card that previews part of a longer list ends with its "View All" call to action
/// **inside** the card, below the last row (view-all-cta R1, issue #382). Pass it as
/// `action`; the card insets it by ``actionInset`` so its corners are concentric with
/// the card's, and tells it through ``EnvironmentValues/festivalCardAction`` to draw a
/// flat fill rather than a second material (surface-materials R6):
///
/// ```swift
/// FestivalGlassSection("Common Rivals") {
///     ForEach(rivals) { RivalRowContent(rival: $0) }
/// } action: {
///     PurpleActionLink(title: "View All Rivals", route: route, identifier: id)
/// }
/// ```
public struct FestivalGlassSection<Content: View, Action: View>: View {
    private let title: String?
    private let subtitle: String?
    private let rowStyle: FestivalGroupRows
    private let content: Content
    private let action: Action
    /// Draw the iOS 17 / macOS 14 row stack even where subviews can be enumerated.
    private var forcesStackedRows = false

    /// The card's corner radius (the Rivals and Settings group card).
    static var cornerRadius: CGFloat { 22 }

    /// Margin between the card's edge and its in-card action on every side. With the
    /// action's 12 pt corners it keeps the two shapes concentric (22 − 10 = 12).
    static var actionInset: CGFloat { cornerRadius - PurpleActionSurface.cornerRadius }

    /// Create a section card whose last element is a call to action inside the card.
    ///
    /// - Parameters:
    ///   - title: Title Case header, or nil for an untitled card.
    ///   - subtitle: Optional muted description under the title.
    ///   - rows: How the card lays out its rows; ``FestivalGroupRows/padded`` by default.
    ///   - content: Rows; each top-level child becomes one row.
    ///   - action: The card's "View All" button (view-all-cta), or no view while the
    ///     card shows no rows; it is not a row, so no hairline sits above it.
    public init(
        _ title: String? = nil, subtitle: String? = nil, rows: FestivalGroupRows = .padded,
        @ViewBuilder content: () -> Content, @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rowStyle = rows
        self.content = content()
        self.action = action()
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

    /// This section drawn with the iOS 17 / macOS 14 row stack, so hosted tests on a newer
    /// OS cover the back-deployed layout.
    ///
    /// - Returns: A copy that never enumerates its subviews.
    func stackedRows() -> Self {
        var copy = self
        copy.forcesStackedRows = true
        return copy
    }

    /// The rows on the shared material card; flush rows are clipped to its corners so a
    /// selected row's full-width fill follows the card's shape. The action follows the
    /// rows inside the card.
    @ViewBuilder private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        switch rowStyle {
        case .padded:
            VStack(alignment: .leading, spacing: 0) {
                rows
                actionArea
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .festivalCard(cornerRadius: Self.cornerRadius)
        case .flush:
            VStack(alignment: .leading, spacing: 0) {
                rows.environment(\.festivalGroupedRow, true)
                actionArea
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(shape)
            .festivalCard(cornerRadius: Self.cornerRadius)
        }
    }

    /// The in-card action, inset by ``actionInset`` on every side. An absent action
    /// (`EmptyView` or a false `if`) has no content to pad, so it adds no space.
    private var actionArea: some View {
        action
            .padding(Self.actionInset)
            .environment(\.festivalCardAction, true)
    }

    /// Each child view as a row, with hairline separators where supported.
    @ViewBuilder private var rows: some View {
        if #available(iOS 18.0, macOS 15.0, *), !forcesStackedRows {
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
                // iOS 17 / macOS 14 cannot enumerate subviews: each row carries a hairline
                // above it, and the stack starts one point above the clipped card so the
                // first row's hairline is cut off. Rows and hairlines match the iOS 18 layout.
                VStack(alignment: .leading, spacing: 0) {
                    content.modifier(FestivalLeadingHairline(inset: rowStyle.separatorInset))
                }
                .padding(.top, -FestivalLeadingHairline.height)
            }
        }
    }
}

// MARK: - Card without an action

extension FestivalGlassSection where Action == EmptyView {
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
        self.init(title, subtitle: subtitle, rows: rows, content: content, action: { EmptyView() })
    }
}

// MARK: - Stacked-row hairline

/// The iOS 17 / macOS 14 flush-row separator: a hairline in a one-point band above the row,
/// inset like the iOS 18 separator (issue #381, surface-materials R8).
struct FestivalLeadingHairline: ViewModifier {
    /// The hairline's thickness, the same as the enumerated separator.
    static var height: CGFloat { 1 }

    let inset: CGFloat

    // Padding and overlay apply to each row of a multi-row `content`; a container here
    // would merge the rows into one.
    func body(content: Content) -> some View {
        content
            .padding(.top, Self.height)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(BrandTokens.glassBorder)
                    .frame(height: Self.height)
                    .padding(.leading, inset)
                    .accessibilityHidden(true)
            }
    }
}

// MARK: - Group card segments

/// Where one row of a full board sits in the board's group card (owner-approved
/// variant, issue #543; leaderboard-row R10, surface-materials R8).
///
/// A full board (song, song band, Full Rankings and Band Rankings) shows each page's
/// rows in one ``FestivalGlassSection`` card, like the previews and Rivals. Its rows
/// stay separate lazy list rows (virtualization, row identities for the selected-row
/// reveal, row-major wide-columns pairs), so each row draws its own **segment** of the
/// card instead: the first row carries the card's top corners, the last its bottom
/// corners, and every row below the first a hairline above it. In wide-columns pairs
/// each column is one card.
struct FestivalGroupSegment: Equatable, Sendable {
    /// The row is in the card's first row (its top corners and rim).
    var isFirst: Bool
    /// The row is in the card's last row (its bottom corners).
    var isLast: Bool
    /// The row shares a wide-columns pair and stretches to the pair's height, so the
    /// column's card has no gap below a shorter cell.
    var fillsPair = false

    /// The segment of the item at `index` in a board of `count` items laid out row-major
    /// in `columns` columns, one card per column.
    ///
    /// - Parameters:
    ///   - index: The item's position on the page.
    ///   - count: Items on the page.
    ///   - columns: Columns across the page (1 outside wide landscape).
    /// - Returns: The item's segment.
    static func position(index: Int, count: Int, columns: Int) -> FestivalGroupSegment {
        let columns = max(1, columns)
        return FestivalGroupSegment(
            isFirst: index < columns, isLast: index + columns >= count, fillsPair: columns > 1
        )
    }

    /// The segment's corner radii: the group card's on its open card ends only.
    ///
    /// - Parameter radius: The group card's corner radius.
    /// - Returns: Top corners for the first row, bottom corners for the last.
    func cornerRadii(_ radius: CGFloat) -> RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: isFirst ? radius : 0, bottomLeading: isLast ? radius : 0,
            bottomTrailing: isLast ? radius : 0, topTrailing: isFirst ? radius : 0
        )
    }
}

extension View {
    /// Draw this row as one segment of a full board's group card
    /// (``FestivalGroupSegment``, issue #543): the shared material card clipped to the
    /// segment, a hairline above every row but the first, and
    /// ``EnvironmentValues/festivalGroupedRow`` set so the row draws no card of its own
    /// and a selected row fills the full width.
    ///
    /// Apply it outside the row's fade-in, so the card stays whole while rows stagger.
    ///
    /// - Parameters:
    ///   - segment: Where the row sits in the card.
    ///   - separatorInset: Leading hairline inset, the row's own horizontal padding.
    /// - Returns: The row on its card segment.
    func festivalGroupSegment(_ segment: FestivalGroupSegment, separatorInset: CGFloat) -> some View {
        modifier(FestivalGroupSegmentModifier(segment: segment, separatorInset: separatorInset))
    }
}

/// Implementation of ``SwiftUI/View/festivalGroupSegment(_:separatorInset:)``.
struct FestivalGroupSegmentModifier: ViewModifier {
    let segment: FestivalGroupSegment
    let separatorInset: CGFloat

    func body(content: Content) -> some View {
        let radius = FestivalGlassSection<EmptyView, EmptyView>.cornerRadius
        let shape = UnevenRoundedRectangle(cornerRadii: segment.cornerRadii(radius), style: .continuous)
        content
            .environment(\.festivalGroupedRow, true)
            .padding(.top, segment.isFirst ? 0 : FestivalLeadingHairline.height)
            .frame(maxWidth: .infinity, maxHeight: segment.fillsPair ? .infinity : nil, alignment: .top)
            .overlay(alignment: .top) {
                if !segment.isFirst {
                    Rectangle()
                        .fill(BrandTokens.glassBorder)
                        .frame(height: FestivalLeadingHairline.height)
                        .padding(.leading, separatorInset)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(shape)
            .modifier(FestivalCardModifier(
                shape: shape, comparisonRole: .card, segment: segment, segmentRadius: radius
            ))
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

    /// True for the call to action inside a ``FestivalGlassSection`` (its `action`): the
    /// card is the button's backdrop, so ``PurpleActionSurface`` draws a flat purple
    /// fill with no material or rim of its own (surface-materials R6, issue #382).
    @Entry var festivalCardAction: Bool = false
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
