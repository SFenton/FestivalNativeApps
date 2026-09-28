import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Drawer destinations

/// Everything the drawer can ask the shell to do. The root owns tab selection,
/// paths and sheets, so the drawer only emits intents.
enum DrawerIntent: Equatable {
    /// Push a route onto the currently selected tab's stack.
    case push(AppRoute)
    /// Switch to a root section (popping it to its root).
    case select(FestivalSection)
    /// Present profile search/switching.
    case chooseProfile
    /// Deselect the current profile (already confirmed by the user).
    case deselectProfile
}

/// One drawer navigation row.
struct DrawerItem: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let intent: DrawerIntent
}

/// Pure drawer contents, ported from the web `Sidebar` (`components/shell/desktop/Sidebar.tsx`).
enum DrawerMenu {
    /// Rows for the "Browse" group.
    ///
    /// Leaderboards appears only when it is not already a tab (a selected player's
    /// compact tab bar shows Compete instead). Rivals requires a player. Item Shop
    /// honours Settings › Hide Item Shop.
    ///
    /// - Parameters:
    ///   - profile: Selected profile kind.
    ///   - visibleSections: Sections currently shown as tabs.
    ///   - hideShop: Persisted `fst.settings.hideShop` preference.
    /// - Returns: Ordered drawer rows.
    static func browse(
        profile: FestivalProfileKind, visibleSections: [FestivalSection], hideShop: Bool
    ) -> [DrawerItem] {
        var items: [DrawerItem] = []
        if !visibleSections.contains(.leaderboards) {
            items.append(DrawerItem(
                id: "leaderboards", title: "Leaderboards", symbol: "trophy",
                intent: .push(.leaderboards)
            ))
        }
        if profile == .player && !visibleSections.contains(.rivals) {
            items.append(DrawerItem(
                id: "rivals", title: "Rivals", symbol: "person.2", intent: .push(.rivals)
            ))
        }
        items.append(DrawerItem(
            id: "bands", title: "Bands", symbol: "person.3", intent: .push(.bands)
        ))
        if !hideShop {
            items.append(DrawerItem(
                id: "shop", title: "Item Shop", symbol: "bag", intent: .push(.shop)
            ))
        }
        return items
    }

    /// Rows for the "More" group (web sidebar footer).
    static let more: [DrawerItem] = [
        DrawerItem(id: "manual", title: "Manual", symbol: "safari", intent: .push(.manual)),
        DrawerItem(id: "settings", title: "Settings", symbol: "gearshape", intent: .select(.settings)),
        DrawerItem(id: "licenses", title: "Licenses", symbol: "doc.text", intent: .push(.licenses)),
    ]
}

// MARK: - Drawer view

/// Leading slide-over navigation panel on dark Liquid Glass (web hamburger `Sidebar`).
///
/// Dismisses on scrim tap, a leading swipe, the close button, or the VoiceOver
/// escape gesture (two-finger Z). The panel is announced as modal so VoiceOver
/// focus stays inside it.
struct FestivalDrawer: View {
    let session: FestivalSession
    let visibleSections: [FestivalSection]
    let hideShop: Bool
    let onIntent: (DrawerIntent) -> Void
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var deselectPending = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Gap between the floating panel and the screen edges.
    private static let margin: CGFloat = 8
    /// Roughly concentric with an iPhone's display corners at an 8 pt inset.
    private static let cornerRadius: CGFloat = 44

    private var profile: FestivalProfileKind {
        session.selectedPlayer == nil ? .none : .player
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(340, geometry.size.width * 0.84)
            let insets = geometry.safeAreaInsets
            ZStack(alignment: .leading) {
                Color.black.opacity(0.45 * progress(width: width))
                    // Leave the content under the panel undimmed so its glass refracts
                    // real colour rather than the scrim.
                    .mask {
                        Rectangle().overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .frame(width: width)
                                .padding(Self.margin)
                                .offset(x: min(0, dragOffset))
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                panel(topInset: insets.top, bottomInset: insets.bottom)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .modifier(FestivalGlassModifier(
                        role: .overlay,
                        shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous),
                        interactive: false
                    ))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 4)
                    .padding(Self.margin)
                    .offset(x: min(0, dragOffset))
                    .gesture(dismissDrag(width: width))
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape, onClose)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Deselect \(session.selectedPlayer?.displayName ?? "Profile")?",
            isPresented: $deselectPending, titleVisibility: .visible
        ) {
            Button("Deselect Profile", role: .destructive) { onIntent(.deselectProfile) }
        } message: {
            Text("Scores and profile tabs will be hidden until you select a profile again.")
        }
    }

    /// Fraction of the panel still on screen while dragging (drives scrim opacity).
    private func progress(width: CGFloat) -> CGFloat {
        max(0, min(1, 1 + dragOffset / width))
    }

    /// Follow a leading swipe and dismiss past a third of the width or on a fling.
    private func dismissDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                if value.translation.width < -width / 3 || value.predictedEndTranslation.width < -width / 2 {
                    onClose()
                } else {
                    withAnimation(reduceMotion ? nil : .snappy) { dragOffset = 0 }
                }
            }
    }

    // MARK: Content

    /// Scrollable drawer body, padded clear of the status bar and home indicator.
    ///
    /// - Parameters:
    ///   - topInset: Top safe-area inset of the full-screen host.
    ///   - bottomInset: Bottom safe-area inset of the full-screen host.
    /// - Returns: The drawer contents.
    private func panel(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                profileSection
                group("Browse", items: DrawerMenu.browse(
                    profile: profile, visibleSections: visibleSections, hideShop: hideShop
                ))
                group("More", items: DrawerMenu.more)
            }
            .padding(.horizontal, 12)
            .padding(.top, max(16, topInset - Self.margin + 4))
            .padding(.bottom, max(16, bottomInset))
        }
        .scrollBounceBehavior(.basedOnSize)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityIdentifier("fst.shell.drawer")
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Festival Score Tracker")
                .font(.title3.bold())
                .foregroundStyle(BrandTokens.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(BrandTokens.textSecondary)
            .accessibilityLabel("Close Navigation")
            .accessibilityIdentifier("fst.shell.drawer.close")
        }
        .padding(.leading, 8)
    }

    @ViewBuilder private var profileSection: some View {
        if let player = session.selectedPlayer {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    ProfileAvatar(name: player.displayName, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.displayName)
                            .font(.headline)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .lineLimit(2)
                        Text("Selected Player")
                            .font(.subheadline)
                            .foregroundStyle(BrandTokens.textMuted)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                DrawerRow(title: "View Profile", symbol: "person.text.rectangle") {
                    onIntent(.push(.player(
                        accountId: player.accountId, displayName: player.displayName
                    )))
                }
                .accessibilityIdentifier("fst.shell.drawer.view-profile")
                DrawerRow(title: "Switch Profile", symbol: "arrow.left.arrow.right") {
                    onIntent(.chooseProfile)
                }
                .accessibilityIdentifier("fst.shell.drawer.switch-profile")
                DrawerRow(
                    title: "Deselect Profile", symbol: "person.crop.circle.badge.minus",
                    tint: .red
                ) {
                    deselectPending = true
                }
                .accessibilityIdentifier("fst.shell.drawer.deselect-profile")
            }
        } else {
            DrawerRow(title: "Select Profile", symbol: "person.crop.circle.badge.plus",
                      tint: BrandTokens.accentBlue) {
                onIntent(.chooseProfile)
            }
            .accessibilityIdentifier("fst.shell.drawer.select-profile")
        }
    }

    private func group(_ title: String, items: [DrawerItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BrandTokens.textMuted)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(items) { item in
                DrawerRow(title: item.title, symbol: item.symbol) { onIntent(item.intent) }
                    .accessibilityIdentifier("fst.shell.drawer.\(item.id)")
            }
        }
    }
}

// MARK: - Row

/// Full-width drawer row with an SF Symbol, ≥ 48 pt tall, highlighted while pressed.
struct DrawerRow: View {
    let title: String
    let symbol: String
    var tint: Color = BrandTokens.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .frame(width: 26)
                    .foregroundStyle(tint == BrandTokens.textPrimary ? BrandTokens.textSecondary : tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .foregroundStyle(tint == .red ? tint : BrandTokens.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DrawerRowStyle())
    }
}

/// Rounded press highlight matching iOS 26 sidebar rows.
struct DrawerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.white.opacity(configuration.isPressed ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}
