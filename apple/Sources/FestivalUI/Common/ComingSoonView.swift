import SwiftUI
import FestivalDesign

// MARK: - Placeholder

/// Temporary body for a routed screen whose feature lane has not landed yet.
///
/// Feature lanes replace the placeholder body in their own screen file; they do
/// not delete this type (other placeholders may still use it).
struct ComingSoonView: View {
    let title: String
    let symbol: String

    /// Create a placeholder.
    ///
    /// - Parameters:
    ///   - title: Title Case page name shown in the navigation bar.
    ///   - symbol: SF Symbol for the empty state.
    init(_ title: String, symbol: String = "hammer") {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        FestivalEmptyState(
            title, systemImage: symbol, subtitle: "Coming soon",
            accessibilityIdentifier: "fst.placeholder.\(title)"
        )
        .festivalNavigationTitle(title)
    }
}
