import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - iPad sections sidebar

/// The iPad sections sidebar: the primary column of the root `NavigationSplitView`
/// in a regular-width window (`.agents/design/apple/ipados.md`).
///
/// Rows are a native selectable sidebar `List`, so the system draws the persistent
/// selected-row highlight, the pointer highlight and hardware-keyboard arrow
/// navigation (HIG Split views: "Persistently highlight the current selection in each
/// pane"; HIG Keyboards: "iPadOS navigates ... sidebars"). The footer mirrors the web
/// sidebar footer: the selected player (name opens their profile, Deselect beside it)
/// or Select Profile, then Settings.
///
/// A Search row heads the list: global search in the detail column (issue #92; HIG
/// Search fields: "Use a sidebar/tab-bar search item for a dedicated discovery area ...
/// keeping search available across sections").
///
/// Compiles on macOS only so hosted snapshot tests can render it; the Mac app has its
/// own sidebar (`Mac/MacRootView.swift`).
struct FestivalSidebar: View {
    let session: FestivalSession
    /// Browse rows (``SidebarMenu/browse(profile:hideShop:)``).
    let browse: [FestivalSection]
    /// Selected root destination (underneath Search while it shows).
    let selected: FestivalSection
    /// The Search row is selected.
    var searchSelected = false
    /// Select a destination (re-selecting pops it to its root; choosing the destination
    /// Search was opened from returns to it).
    let onSelect: (FestivalSection) -> Void
    /// Show global search in the detail column; nil hides the Search row.
    var onSearch: (() -> Void)?
    /// Push the selected player's page on the current destination.
    let onOpenPlayer: (AppRoute) -> Void
    /// Present profile selection.
    let onChooseProfile: () -> Void
    /// Reports the sidebar's trailing edge in window coordinates (0 while hidden), so
    /// the shell knows how much width its sections get.
    var onExtentChange: (CGFloat) -> Void = { _ in }

    @State private var deselectPending = false

    var body: some View {
        List(selection: selection) {
            if onSearch != nil {
                Label("Search", systemImage: "magnifyingglass")
                    .accessibilityElement(children: .combine)
                    .tag(RootTab.search)
                    .accessibilityIdentifier("fst.nav.sidebar.search")
            }
            ForEach(browse) { section in
                Label(section.title, systemImage: section.symbol)
                    // One element per row, so the identifier names the row, not its icon.
                    .accessibilityElement(children: .combine)
                    .tag(RootTab.section(section))
                    .accessibilityIdentifier("fst.nav.\(section.rawValue)")
            }
        }
        .listStyle(.sidebar)
        // On the list only: applied after the footer inset it would rename every
        // footer button too.
        .accessibilityIdentifier("fst.nav.sidebar")
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxX }) { maxX in
            onExtentChange(max(0, maxX))
        }
        .onDisappear { onExtentChange(0) }
        // No title: HIG Toolbars, "Never use the app name"; the rows are the context.
        .navigationTitle("")
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .confirmationDialog(
            "Deselect \(session.selectedPlayer?.displayName ?? "Profile")?",
            isPresented: $deselectPending, titleVisibility: .visible
        ) {
            Button("Deselect Profile", role: .destructive) { session.deselectPlayer() }
        } message: {
            Text("Scores and profile tabs will be hidden until you select a profile again.")
        }
    }

    /// List selection: Search and the browse rows; Settings (footer) leaves the list
    /// unselected.
    private var selection: Binding<RootTab?> {
        Binding {
            if searchSelected { return .search }
            return browse.contains(selected) ? .section(selected) : nil
        } set: { next in
            switch next {
            case .search:
                if !searchSelected { onSearch?() }
            case let .section(section):
                if section != selected || searchSelected { onSelect(section) }
            case nil:
                break
            }
        }
    }

    // MARK: Footer

    /// Selected player (or Select Profile), then Settings, pinned below the rows.
    private var footer: some View {
        VStack(spacing: 4) {
            profileRow
            SidebarFooterRow(
                title: FestivalSection.settings.title, symbol: FestivalSection.settings.symbol,
                isSelected: selected == .settings && !searchSelected
            ) {
                onSelect(.settings)
            }
            .accessibilityIdentifier("fst.nav.settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var profileRow: some View {
        if let player = session.selectedPlayer {
            HStack(spacing: 8) {
                Button {
                    onOpenPlayer(.player(accountId: player.accountId, displayName: player.displayName))
                } label: {
                    HStack(spacing: 10) {
                        ProfileAvatar(name: player.displayName, size: 28)
                        MarqueeText(player.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(BrandTokens.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .sidebarHover()
                .accessibilityLabel(DrawerMenu.selectedPlayerAccessibilityLabel(player.displayName))
                .accessibilityHint("Opens your profile")
                .accessibilityIdentifier("fst.profile.sidebar")
                Button("Deselect") { deselectPending = true }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Deselect Profile")
                    .accessibilityIdentifier("fst.nav.sidebar.deselect-profile")
            }
            .padding(.horizontal, 10)
            .background(BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            SidebarFooterRow(
                title: "Select Profile", symbol: "person.crop.circle.badge.plus", isSelected: false,
                action: onChooseProfile
            )
            .accessibilityIdentifier("fst.profile.sidebar")
        }
    }
}

/// A footer row drawn like a sidebar row (symbol + label, accent fill when selected).
private struct SidebarFooterRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(BrandTokens.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 10)
                .background(
                    isSelected ? AnyShapeStyle(BrandTokens.accentBlue.opacity(0.85)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sidebarHover()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    /// Pointer highlight on iPad (HIG Pointing devices: "highlight for small elements
    /// with transparent backgrounds"); nothing on macOS.
    @ViewBuilder fileprivate func sidebarHover() -> some View {
        #if os(iOS)
        hoverEffect(.highlight)
        #else
        self
        #endif
    }
}
