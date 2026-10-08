import SwiftUI
import FestivalDesign

// MARK: - Section card

/// A Settings section on the shared ``FestivalGlassSection`` card, titled on the single
/// long page and on the Mac panes, untitled on a list/detail topic page (issue #371),
/// where the pane's navigation title already names it: the description then sits above
/// the card on its own.
struct SettingsSectionCard<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let titled: Bool
    private let content: Content

    /// Create a section.
    ///
    /// - Parameters:
    ///   - title: Title Case section title.
    ///   - subtitle: Optional sentence-case description.
    ///   - titled: False on a topic page: no header, only the description.
    ///   - content: Rows; each top-level child becomes one row.
    init(
        _ title: String, subtitle: String? = nil, titled: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titled = titled
        self.content = content()
    }

    var body: some View {
        if titled {
            FestivalGlassSection(title, subtitle: subtitle) { content }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                FestivalGlassSection { content }
            }
        }
    }
}
