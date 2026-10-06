import SwiftUI

// MARK: - Page title

/// The title a page shows in its navigation bar, published up the view tree so the
/// ``PublicationRefreshBoundary`` page anchor can name the page for VoiceOver while it
/// refreshes (issue #304). The innermost title wins.
struct FestivalPageTitleKey: PreferenceKey {
    static let defaultValue: String? = nil

    static func reduce(value: inout String?, nextValue: () -> String?) {
        if value == nil { value = nextValue() }
    }
}

extension View {
    /// Set the page's navigation title and publish it for the publication refresh page
    /// anchor. Use for every page shown inside a ``PublicationRefreshBoundary`` (every
    /// pushed route and the refreshed tab roots) instead of `navigationTitle(_:)`.
    ///
    /// - Parameter title: The page title.
    /// - Returns: The view with the title set and published.
    func festivalNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .preference(key: FestivalPageTitleKey.self, value: title)
    }
}
