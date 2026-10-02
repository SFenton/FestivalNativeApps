#if os(iOS)
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
struct FestivalSidebar: View {
    let session: FestivalSession
    /// Browse rows (``SidebarMenu/browse(profile:hideShop:)``).
    let browse: [FestivalSection]
    /// Selected root destination.
    let selected: FestivalSection
    /// Select a destination (re-selecting pops it to its root).
    let onSelect: (FestivalSection) -> Void
    /// Push the selected player's page on the current destination.
    let onOpenPlayer: (AppRoute) -> Void
    /// Present profile selection.
    let onChooseProfile: () -> Void

    @State private var deselectPending = false

    var body: some View {
        List(selection: selection) {
            ForEach(browse) { section in
                Label(section.title, systemImage: section.symbol)
                    // One element per row, so the identifier names the row, not its icon.
                    .accessibilityElement(children: .combine)
                    .tag(section)
                    .accessibilityIdentifier("fst.nav.\(section.rawValue)")
            }
        }
        .listStyle(.sidebar)
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
        .accessibilityIdentifier("fst.nav.sidebar")
    }

    /// List selection: only browse rows; Settings (footer) leaves the list unselected.
    private var selection: Binding<FestivalSection?> {
        Binding {
            browse.contains(selected) ? selected : nil
        } set: { next in
            if let next, next != selected { onSelect(next) }
        }
    }

    // MARK: Footer

    /// Selected player (or Select Profile), then Settings, pinned below the rows.
    private var footer: some View {
        VStack(spacing: 4) {
            profileRow
            SidebarFooterRow(
                title: FestivalSection.settings.title, symbol: FestivalSection.settings.symbol,
                isSelected: selected == .settings
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
                .hoverEffect(.highlight)
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
        .hoverEffect(.highlight)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
