import SwiftUI

// MARK: - Shell presentation policy

/// How the root shell presents its sections for one window: which navigation
/// container it uses and which section set it shows.
///
/// Pure, so the per-layout decisions are unit-tested without a device
/// (`ShellPresentationTests`). Decisions (`.agents/design/apple/duo.md`, operator
/// 2026-09-28):
/// - Navigation follows the platform idiom and the window's horizontal size class,
///   never the asynchronously published ``DeviceLayout``: every phone (iPhone Duo
///   included, folded or unfolded) keeps the system `TabView` plus the drawer; macOS
///   and a regular-width iPad window use the sidebar; a compact-width iPad window
///   (Slide Over, a narrow Split View or Stage Manager window) falls back to the phone
///   tabs and drawer (HIG Layout: "Choose layout from size classes, not device
///   type/idiom"; "Larger spaces may ... switch a tab bar to a sidebar"). The size
///   class is known on the first pass, so no geometry round trip rebuilds the stacks.
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

    /// Whether the shell is the sidebar for a platform and width.
    ///
    /// - Parameters:
    ///   - supportsSidebar: True on iPad and macOS (the phone idiom never uses it).
    ///   - widthClass: The window's horizontal size class (macOS is always regular).
    /// - Returns: True for the `NavigationSplitView` sidebar shell.
    static func usesSidebarShell(supportsSidebar: Bool, widthClass: WidthClass) -> Bool {
        supportsSidebar && widthClass == .regular
    }

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
    /// The sidebar lists the web sidebar's destinations (``SidebarMenu``, Item Shop
    /// included); tabs list the web `BottomNav` sections (``FestivalTabPolicy``).
    ///
    /// - Parameters:
    ///   - profile: Selected profile kind.
    ///   - hideShop: Settings › Hide Item Shop (sidebar only).
    /// - Returns: Ordered sections to show as tabs or sidebar rows.
    func sections(profile: FestivalProfileKind, hideShop: Bool = false) -> [FestivalSection] {
        if navigation == .sidebar {
            return SidebarMenu.sections(profile: profile, hideShop: hideShop)
        }
        return FestivalTabPolicy.sections(profile: profile, regularWidth: usesRegularSectionSet)
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
    /// Builds the shell for the resolved presentation and the published layout.
    @ViewBuilder let content: (ShellPresentation, DeviceLayout) -> Content

    @Environment(\.deviceLayout) private var layout

    var body: some View {
        content(ShellPresentation.resolve(layout: layout, usesSidebarShell: usesSidebarShell), layout)
    }
}
