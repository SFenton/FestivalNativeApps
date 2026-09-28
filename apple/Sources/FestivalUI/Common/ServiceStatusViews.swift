import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

enum OfflineDisclosure {
    enum Content: Sendable {
        case songs
        case scores
        case paths
        case shop
    }

    /// Name the source of an offline page without promoting observed IDs to proof.
    ///
    /// - Parameters:
    ///   - content: Catalogue or solo chart being shown from process memory.
    ///   - publicationId: Response-proven generation, nil for headerless bytes.
    /// - Returns: A distinct, accessible freshness and provenance statement.
    static func label(_ content: Content, publicationId: Int?) -> String {
        switch (content, publicationId) {
        case (.songs, nil):
            "Offline - last seen songs (publication unverified)"
        case (.scores, nil):
            "Offline - last seen scores (publication unverified)"
        case (.paths, nil):
            "Offline - last seen paths (publication unverified)"
        case (.shop, nil):
            "Offline - last seen shop (publication unverified)"
        case (.songs, .some):
            "Offline - showing cached songs"
        case (.scores, .some):
            "Offline - showing cached scores"
        case (.paths, .some):
            "Offline - showing cached paths"
        case (.shop, .some):
            "Offline - showing cached shop"
        }
    }
}

/// Wrapping native text with a stable icon and explicit screen-reader label.
struct FreshnessDisclosure: View {
    let message: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(BrandTokens.gold)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            BrandTokens.cardBackground,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Scalable error content: the iOS 26 system unavailable view fails the Dynamic Type audit.
struct ServiceUnavailableView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.largeTitle)
                        .foregroundStyle(BrandTokens.textSecondary)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(BrandTokens.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(BrandTokens.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: retry) {
                        Text("Retry")
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, 12)
                            .background(
                                BrandTokens.cardBackground,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Typed native navigation within the Songs tab, separate from other tab stacks.

struct RefreshErrorBanner: View {
    let message: String

    var body: some View {
        Label("Update failed: \(message)", systemImage: "exclamationmark.triangle")
            .foregroundStyle(BrandTokens.gold)
            .accessibilityIdentifier("fst.songs.refresh-error")
    }
}

/// A row's text, artwork and charted meter remain one accessible navigation action.

struct HighContrastPagerStyle: ButtonStyle {
    /// Render the label without the plain style's automatic disabled dimming.
    ///
    /// - Parameter configuration: Native press state and the button's label.
    /// - Returns: A readable label with pressed-state feedback.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
