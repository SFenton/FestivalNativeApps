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
///   included, folded or unfolded) keeps the system `TabView` plus the drawer; a
///   regular-width iPad window shows the selected section full width with its
///   destinations in the overlay flyout (operator 2026-10-04, `split-view.md`: no
///   persistent sidebar column); macOS keeps its persistent sidebar; a compact-width
///   iPad window (Slide Over, a narrow Split View or Stage Manager window) falls back
///   to the phone tabs and drawer (HIG Layout: "Choose layout from size classes, not
///   device type/idiom"). The size class is known on the first pass, so no geometry
///   round trip rebuilds the stacks.
/// - The regular section set (Leaderboards and Rivals instead of Compete) is used only
///   by the wide shell (iPad/macOS). Every phone tab bar, the iPhone Duo inner display
///   included (issue #337), shows the compact set fitted beside the Search tab, so a
///   fold or unfold never changes the tabs and large iPhones in landscape keep their
///   portrait tabs.
struct ShellPresentation: Sendable, Equatable {
    /// Root navigation container.
    enum Navigation: Sendable, Equatable {
        /// System `TabView` with the hamburger drawer (every phone).
        case tabs
        /// The selected section full width, its destinations in the overlay flyout
        /// (the drawer); a regular-width iPad window.
        case flyout
        /// `NavigationSplitView` persistent sidebar (macOS).
        case sidebar
    }

    /// Root navigation container.
    let navigation: Navigation
    /// Whether `FestivalTabPolicy` uses its regular-width section set.
    let usesRegularSectionSet: Bool

    /// True where the hamburger drawer (the overlay flyout) replaces a permanent sidebar.
    var usesDrawer: Bool { navigation != .sidebar }

    /// True for the wide shells (iPad flyout, Mac sidebar), whose section set is the web
    /// sidebar's (Item Shop and Settings included).
    var listsSidebarDestinations: Bool { navigation != .tabs }

    /// Whether the platform's wide shell keeps a persistent sidebar (macOS only).
    static var platformHasPersistentSidebar: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Whether the shell is the wide shell (iPad flyout or Mac sidebar) for a platform
    /// and width.
    ///
    /// - Parameters:
    ///   - supportsSidebar: True on iPad and macOS (the phone idiom never uses it).
    ///   - widthClass: The window's horizontal size class (macOS is always regular).
    /// - Returns: True for the wide shell.
    static func usesSidebarShell(supportsSidebar: Bool, widthClass: WidthClass) -> Bool {
        supportsSidebar && widthClass == .regular
    }

    /// Resolve the presentation for a window.
    ///
    /// - Parameters:
    ///   - layout: Layout published by `publishesDeviceLayout(usesSidebarShell:)`.
    ///   - usesSidebarShell: True for the wide shell (regular-width iPad, macOS).
    ///   - persistentSidebar: Whether the wide shell is the persistent sidebar (macOS)
    ///     rather than the flyout (iPad).
    /// - Returns: The shell presentation.
    static func resolve(
        layout: DeviceLayout, usesSidebarShell: Bool,
        persistentSidebar: Bool = ShellPresentation.platformHasPersistentSidebar
    ) -> ShellPresentation {
        ShellPresentation(
            navigation: usesSidebarShell ? (persistentSidebar ? .sidebar : .flyout) : .tabs,
            usesRegularSectionSet: usesSidebarShell || layout.usesRegularSectionSet
        )
    }

    /// Visible root sections for a profile under this presentation.
    ///
    /// The wide shells (flyout, sidebar) list the web sidebar's destinations
    /// (``SidebarMenu``, Item Shop included); tabs list the web `BottomNav` sections
    /// (``FestivalTabPolicy``). Phone tabs, iPhone Duo folded or unfolded, leave a slot
    /// for the Search tab (``FestivalTabPolicy/fittingSearchTab(_:limit:)``); with a
    /// player selected, Statistics opens from the Profile button and the drawer.
    ///
    /// - Parameters:
    ///   - profile: Selected profile kind.
    ///   - hideShop: Settings › Hide Item Shop (sidebar only).
    /// - Returns: Ordered sections to show as tabs or sidebar rows.
    func sections(profile: FestivalProfileKind, hideShop: Bool = false) -> [FestivalSection] {
        if listsSidebarDestinations {
            return SidebarMenu.sections(profile: profile, hideShop: hideShop)
        }
        let sections = FestivalTabPolicy.sections(profile: profile, regularWidth: usesRegularSectionSet)
        return usesRegularSectionSet ? sections : FestivalTabPolicy.fittingSearchTab(sections)
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
    /// True for the wide shell (regular-width iPad flyout, macOS sidebar).
    let usesSidebarShell: Bool
    /// Builds the shell for the resolved presentation and the published layout.
    @ViewBuilder let content: (ShellPresentation, DeviceLayout) -> Content

    @Environment(\.deviceLayout) private var layout
    /// The section set the tabs currently show; trails the resolved one by a run-loop turn.
    @State private var appliedRegularSet: Bool?

    var body: some View {
        let resolved = ShellPresentation.resolve(layout: layout, usesSidebarShell: usesSidebarShell)
        content(ShellPresentation.applying(resolved, regularSet: appliedRegularSet), layout)
            .onChange(of: resolved.usesRegularSectionSet, initial: true) { _, regular in
                guard appliedRegularSet != nil else {
                    appliedRegularSet = regular
                    return
                }
                // Folding iPhone Duo from inner portrait crashed UIKit
                // (`-[UITabBarController _tabs_rebuildTabBarItemsAnimated:]` inserting
                // out of bounds, 2026-10-04) when the tab set changed in the same update
                // that pushed the new size class into the tab bar controller. The Duo
                // keeps one tab set since #337, but an iPad window crossing size classes
                // can still publish a stale layout, so a change still lands one turn later.
                DispatchQueue.main.async { appliedRegularSet = regular }
            }
    }
}

extension ShellPresentation {
    /// The presentation with the section set the shell has applied so far.
    ///
    /// - Parameters:
    ///   - resolved: The presentation resolved for the current layout.
    ///   - regularSet: The applied section set, or nil before the first one is applied.
    /// - Returns: `resolved`, keeping the applied section set while a change is pending.
    static func applying(_ resolved: ShellPresentation, regularSet: Bool?) -> ShellPresentation {
        ShellPresentation(
            navigation: resolved.navigation,
            usesRegularSectionSet: resolved.listsSidebarDestinations
                ? resolved.usesRegularSectionSet : (regularSet ?? resolved.usesRegularSectionSet)
        )
    }
}
