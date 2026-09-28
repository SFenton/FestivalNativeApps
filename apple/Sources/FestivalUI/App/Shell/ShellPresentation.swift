import SwiftUI

// MARK: - Shell presentation policy

/// How the root shell presents its sections for one window: which navigation
/// container it uses and which section set it shows.
///
/// Pure, so the per-layout decisions are unit-tested without a device
/// (`ShellPresentationTests`). Decisions (`.agents/design/apple/duo.md`, operator
/// 2026-09-28):
/// - Navigation follows the platform idiom, never the asynchronously published
///   ``DeviceLayout``: the iPad/macOS shell is a sidebar, every phone (iPhone Duo
///   included, folded or unfolded) keeps the system `TabView` plus the drawer. Switching
///   container on the first geometry pass would rebuild every stack.
/// - The regular section set (Leaderboards and Rivals instead of Compete) is used only
///   by the sidebar shell (iPad/macOS) and by an iPhone Duo inner display (unfolded or
///   partially folded). Large iPhones in landscape keep their portrait tabs.
struct ShellPresentation: Sendable, Equatable {
    /// Root navigation container.
    enum Navigation: Sendable, Equatable {
        /// System `TabView` with the hamburger drawer (every phone).
        case tabs
        /// `NavigationSplitView` sidebar (iPad and macOS).
        case sidebar
    }

    /// Root navigation container.
    let navigation: Navigation
    /// Whether `FestivalTabPolicy` uses its regular-width section set.
    let usesRegularSectionSet: Bool

    /// True where the hamburger drawer replaces a permanent sidebar.
    var usesDrawer: Bool { navigation == .tabs }

    /// Resolve the presentation for a window.
    ///
    /// - Parameters:
    ///   - layout: Layout published by `publishesDeviceLayout(usesSidebarShell:)`.
    ///   - usesSidebarShell: True for the iPad/macOS split-view shell (platform idiom).
    /// - Returns: The shell presentation.
    static func resolve(layout: DeviceLayout, usesSidebarShell: Bool) -> ShellPresentation {
        ShellPresentation(
            navigation: usesSidebarShell ? .sidebar : .tabs,
            usesRegularSectionSet: usesSidebarShell || layout.usesRegularSectionSet
        )
    }

    /// Visible root sections for a profile under this presentation.
    ///
    /// - Parameter profile: Selected profile kind.
    /// - Returns: Ordered sections to show as tabs or sidebar rows.
    func sections(profile: FestivalProfileKind) -> [FestivalSection] {
        FestivalTabPolicy.sections(profile: profile, regularWidth: usesRegularSectionSet)
    }
}

// MARK: - Shell content

/// Reads the published ``DeviceLayout`` and hands the resolved ``ShellPresentation``
/// to the root shell's content.
///
/// `FestivalRootView` owns the navigation state and applies
/// `publishesDeviceLayout(usesSidebarShell:)` *outside* this view, so the layout is
/// visible here but not in the root view itself.
struct FestivalShellContent<Content: View>: View {
    /// True for the iPad/macOS split-view shell.
    let usesSidebarShell: Bool
    /// Builds the shell for the resolved presentation.
    @ViewBuilder let content: (ShellPresentation) -> Content

    @Environment(\.deviceLayout) private var layout

    var body: some View {
        content(ShellPresentation.resolve(layout: layout, usesSidebarShell: usesSidebarShell))
    }
}
