import SwiftUI
import FestivalDesign

// MARK: - Section header

/// White, Title Case section title shared by every page, sheet and drawer.
///
/// Callers pass the title already in Title Case ("Find a Profile"); the web app's
/// sentence-case strings are not transformed automatically because some words
/// (instrument names, "FC") have fixed casing.
public struct FestivalSectionHeader: View {
    private let title: String
    private let subtitle: String?

    /// Create a section header.
    ///
    /// - Parameters:
    ///   - title: Title Case heading text.
    ///   - subtitle: Optional supporting line (white: headers can sit over artwork).
    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(BrandTokens.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textCase(nil)
    }
}
