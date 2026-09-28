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
        DrawerItem(id: "settings", title: "Settings", symbol: "gearshape", intent: .select(.settings)),
        DrawerItem(id: "licenses", title: "Licenses", symbol: "doc.text", intent: .push(.licenses)),
    ]
}

// MARK: - Drawer placement

/// Pure geometry of the floating drawer panel and its scrim for one window.
///
/// An ordinary phone (``DeviceLayout/Pose/standard``) keeps the original iPhone
/// placement exactly: an 8 pt margin all round, a full-screen scrim, and content padded
/// below the status bar and above the home indicator. iPhone Duo instead insets the
/// panel by ``DeviceLayout/overlayInsets`` (the system vertical bar plus the camera
/// occlusion) and keeps the scrim off the vertical bar, so the drawer never covers a
/// leading bar or the camera in any outer rotation (`.agents/design/apple/duo.md`, B5).
struct DrawerPlacement: Equatable {
    /// Gap between the floating panel and the window (or reserved-region) edges.
    static let margin: CGFloat = 8
    /// Widest panel, in points.
    static let maximumWidth: CGFloat = 340
    /// Share of the available width the panel may take.
    static let widthFraction: CGFloat = 0.84

    /// Panel width.
    let width: CGFloat
    /// Padding from the window edges to the panel's glass shape (leading/top/bottom used).
    let panelPadding: EdgeInsets
    /// Content padding above the first row, inside the panel.
    let contentTop: CGFloat
    /// Content padding below the last row, inside the panel.
    let contentBottom: CGFloat
    /// Window edges the dimming scrim leaves uncovered (the system vertical bar).
    let scrimInsets: EdgeInsets

    /// Resolve the placement.
    ///
    /// - Parameters:
    ///   - size: The drawer `GeometryReader`'s size, i.e. the window inside its safe area.
    ///   - safeArea: Window safe-area insets.
    ///   - layout: Published device layout.
    /// - Returns: Panel and scrim geometry.
    static func resolve(size: CGSize, safeArea: EdgeInsets, layout: DeviceLayout) -> DrawerPlacement {
        guard layout.pose != .standard else {
            return DrawerPlacement(
                width: min(maximumWidth, size.width * widthFraction),
                panelPadding: EdgeInsets(top: margin, leading: margin, bottom: margin, trailing: margin),
                contentTop: max(16, safeArea.top - margin + 4),
                contentBottom: max(16, safeArea.bottom),
                scrimInsets: EdgeInsets()
            )
        }
        // Never less than the drawer's own safe area, whatever the probe reported.
        let overlay = layout.overlayInsets
        let reserved = EdgeInsets(
            top: max(overlay.top, safeArea.top), leading: max(overlay.leading, safeArea.leading),
            bottom: max(overlay.bottom, safeArea.bottom), trailing: max(overlay.trailing, safeArea.trailing)
        )
        let windowWidth = size.width + safeArea.leading + safeArea.trailing
        let available = max(0, windowWidth - reserved.leading - reserved.trailing)
        var scrim = EdgeInsets()
        if case let .verticalBar(edge) = layout.sectionChrome {
            // The bar's safe-area inset is at least the bar's width on its edge.
            switch edge {
            case .leading: scrim.leading = reserved.leading
            case .trailing: scrim.trailing = reserved.trailing
            }
        }
        return DrawerPlacement(
            width: min(maximumWidth, available * widthFraction),
            panelPadding: EdgeInsets(
                top: margin + reserved.top, leading: margin + reserved.leading,
                bottom: margin + reserved.bottom, trailing: margin
            ),
            contentTop: 16,
            contentBottom: 16,
            scrimInsets: scrim
        )
    }

    /// The panel's frame in window coordinates (leading-edge x), before any drag.
    ///
    /// - Parameter size: Full window size.
    /// - Returns: Where the glass panel is drawn.
    func panelFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: panelPadding.leading, y: panelPadding.top, width: width,
            height: max(0, size.height - panelPadding.top - panelPadding.bottom)
        )
    }
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
    @Environment(\.deviceLayout) private var layout

    /// Roughly concentric with an iPhone's display corners at an 8 pt inset.
    private static let cornerRadius: CGFloat = 44

    private var profile: FestivalProfileKind {
        session.selectedPlayer == nil ? .none : .player
    }

    var body: some View {
        GeometryReader { geometry in
            let placement = DrawerPlacement.resolve(
                size: geometry.size, safeArea: geometry.safeAreaInsets, layout: layout
            )
            let width = placement.width
            ZStack(alignment: .leading) {
                Color.black.opacity(0.45 * progress(width: width))
                    // Leave the content under the panel undimmed so its glass refracts
                    // real colour rather than the scrim.
                    .mask {
                        Rectangle().overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .frame(width: width)
                                .padding(placement.panelPadding)
                                .offset(x: min(0, dragOffset) - placement.scrimInsets.leading)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                    // Never dim or intercept taps on the system vertical bar (iPhone Duo).
                    .padding(placement.scrimInsets)
                panel(topInset: placement.contentTop, bottomInset: placement.contentBottom)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .modifier(FestivalGlassModifier(
                        role: .overlay,
                        shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous),
                        interactive: false
                    ))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 4)
                    .padding(placement.panelPadding)
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
    ///   - topInset: Content padding above the first row (``DrawerPlacement/contentTop``).
    ///   - bottomInset: Content padding below the last row (``DrawerPlacement/contentBottom``).
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
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
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
