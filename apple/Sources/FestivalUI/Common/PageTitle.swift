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
            .festivalTitleDisplayMode(.automatic)
    }

    /// Set the page's title display mode, leading-aligned on iPhone (issue #632).
    ///
    /// Where page tools float above the iPhone tab bar (a ``PageToolsRegistry`` is
    /// published), every page's title sits in the navigation bar's row right after the
    /// drawer button or Back chevron (``FestivalTitlePlacement``), instead of a large
    /// title below the bar or a centred inline title; elsewhere the page's own mode
    /// applies. Use instead of `navigationBarTitleDisplayMode(_:)`.
    ///
    /// - Parameter mode: The page's mode outside iPhone.
    /// - Returns: The page with its title display mode.
    func festivalTitleDisplayMode(_ mode: FestivalTitlePlacement.PageMode) -> some View {
        modifier(FestivalTitleDisplayModeModifier(mode: mode))
    }
}

// MARK: - Title placement

/// Where a page's navigation title sits (pure, unit-tested; issue #632).
///
/// Owner-approved iPhone variant (#632, `page-tools-and-nav-chrome`): header titles on
/// tab roots and pushed pages, pinned song titles included, are leading-aligned beside
/// the drawer button or Back chevron, like the web's `MobileHeader`. The public API is
/// the editor toolbar role (`toolbarRole(.editor)`, UIKit's `UINavigationItem.style =
/// .editor`) with an inline title, which lays the title out right after the leading
/// items (HIG Toolbars, leading zone: "Back/Forward, Show/Hide Sidebar, view title").
/// `inlineLarge` is not used: with a leading item it pushes the drawer into the `…`
/// overflow or draws a large title below the bar on pushed pages. Other chromes (iPad,
/// the iPhone Duo, Mac) keep each page's own mode.
enum FestivalTitlePlacement: Equatable {
    /// The title sits leading in the bar's row (iPhone).
    case leading
    /// The page's own mode (the system default, centred inline or large).
    case standard

    /// A page's title display mode outside iPhone.
    enum PageMode: Equatable {
        /// The system default (a large title on a tab root).
        case automatic
        /// A centred inline title.
        case inline
        /// A large title that collapses on scroll.
        case large
    }

    /// Resolve the placement for a window.
    ///
    /// - Parameter floatsPageTools: The window floats page tools above an iPhone tab bar
    ///   (``FloatingPageToolsHost/floatsPageTools(in:)``).
    /// - Returns: ``leading`` on iPhone, else ``standard``.
    nonisolated static func resolve(floatsPageTools: Bool) -> Self {
        floatsPageTools ? .leading : .standard
    }
}

extension FestivalTitlePlacement {
    /// The toolbar placement for a page's own title view (a pinned song or instrument
    /// title): the title slot, which the editor toolbar role lays out leading on iPhone,
    /// else the centred principal slot.
    var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        switch self {
        case .leading: .title
        case .standard: .principal
        }
        #else
        .principal
        #endif
    }
}

/// Implementation of ``SwiftUICore/View/festivalTitleDisplayMode(_:)``.
private struct FestivalTitleDisplayModeModifier: ViewModifier {
    let mode: FestivalTitlePlacement.PageMode
    @Environment(\.pageToolsRegistry) private var pageTools

    func body(content: Content) -> some View {
        #if os(iOS)
        switch FestivalTitlePlacement.resolve(floatsPageTools: pageTools != nil) {
        case .leading:
            content
                .toolbarTitleDisplayMode(.inline)
                .toolbarRole(.editor)
        case .standard:
            switch mode {
            case .automatic: content
            case .inline: content.toolbarTitleDisplayMode(.inline)
            case .large: content.toolbarTitleDisplayMode(.large)
            }
        }
        #else
        content
        #endif
    }
}
