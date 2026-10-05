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
public struct FestivalGlassSection<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let content: Content

    /// Create a section card.
    ///
    /// - Parameters:
    ///   - title: Title Case header, or nil for an untitled card.
    ///   - subtitle: Optional muted description under the title.
    ///   - content: Rows; each top-level child becomes one padded row.
    public init(
        _ title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                FestivalSectionHeader(title, subtitle: subtitle)
                    .padding(.horizontal, 4)
            }
            rows
                .frame(maxWidth: .infinity, alignment: .leading)
                .festivalCard(cornerRadius: 22)
        }
    }

    /// Each child view padded as a row, with hairline separators where supported.
    @ViewBuilder private var rows: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(BrandTokens.glassBorder)
                                .frame(height: 1)
                                .padding(.leading, 16)
                                .accessibilityHidden(true)
                        }
                        row.modifier(FestivalRowPadding())
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                content.modifier(FestivalRowPadding())
            }
            .padding(.vertical, 4)
        }
    }
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
