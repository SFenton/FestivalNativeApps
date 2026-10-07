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
        // Full width, but kept on its own side of an iPhone Duo book-pose fold
        // (section-headers R9, pattern `hinge-columns`).
        .staysOnHingeSide()
        .textCase(nil)
    }
}

// MARK: - View All link

/// The trailing "View All" push beside a section title (web `SectionHeader` `actionLabel`,
/// section-headers R8): the iPhone Duo secondary panes, their Song Detail history cards
/// and the profile's bands section share it. View All copy, never See All (#321).
/// HIG Accessibility: 44×44 pt default control size on iOS/iPadOS.
struct SectionViewAllLink: View {
    /// Full list to push.
    let route: AppRoute
    /// Accessibility identifier.
    let identifier: String
    /// What is listed, spoken after "View All" (e.g. "SFentonX's Bands").
    let listName: String

    var body: some View {
        NavigationLink(value: route) {
            Text("View All")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .tint(BrandTokens.accentBlue)
        .accessibilityLabel("View All \(listName)")
        .accessibilityIdentifier(identifier)
    }
}
