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
    /// Show global search (the iPad flyout's Search row).
    case openSearch
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
    /// The navigation list, in web `Sidebar` order: Songs, Suggestions*, Statistics*,
    /// Rivals*, Leaderboards, Item Shop (*with a selected player). Bands and Licenses
    /// are not listed (operator, 2026-09-28): Bands open from search and leaderboard
    /// links, Licenses from Settings.
    ///
    /// A destination that is a visible tab switches to it; otherwise it is pushed on the
    /// current stack. Item Shop honours Settings › Hide Item Shop; it is pushed, except in
    /// the iPad flyout, where it is a destination of its own.
    ///
    /// - Parameters:
    ///   - profile: Selected profile kind.
    ///   - visibleSections: Sections currently shown as tabs.
    ///   - hideShop: Persisted `fst.settings.hideShop` preference.
    /// - Returns: Ordered drawer rows.
    static func browse(
        profile: FestivalProfileKind, visibleSections: [FestivalSection], hideShop: Bool
    ) -> [DrawerItem] {
        func destination(_ section: FestivalSection, route: AppRoute?) -> DrawerItem {
            let intent: DrawerIntent = if let route, !visibleSections.contains(section) {
                .push(route)
            } else {
                .select(section)
            }
            return DrawerItem(
                id: section.rawValue, title: section.title, symbol: section.symbol, intent: intent
            )
        }
        var items = [destination(.songs, route: nil)]
        if profile != .none {
            items.append(destination(.suggestions, route: .suggestions))
            items.append(destination(.statistics, route: .statistics))
        }
        if profile == .player {
            items.append(destination(.rivals, route: .rivals))
        }
        items.append(destination(.leaderboards, route: .leaderboards))
        if !hideShop {
            items.append(DrawerItem(
                id: "shop", title: "Item Shop", symbol: "bag",
                intent: visibleSections.contains(.shop) ? .select(.shop) : .push(.shop)
            ))
        }
        return items
    }

    /// The iPad flyout's Search row, above the destinations (it replaces the persistent
    /// sidebar's Search row; HIG Search fields: "keep search available across sections").
    static let search = DrawerItem(id: "search", title: "Search", symbol: "magnifyingglass", intent: .openSearch)

    /// Rows pinned at the bottom of the drawer after the profile row (web sidebar footer).
    static let more: [DrawerItem] = [
        DrawerItem(id: "settings", title: "Settings", symbol: "gearshape", intent: .select(.settings)),
    ]

    /// VoiceOver label for the footer's selected-player row.
    ///
    /// The row shows only the name (like every other drawer row), so the "Selected
    /// Player" role is spoken rather than drawn.
    ///
    /// - Parameter displayName: Selected player's display name.
    /// - Returns: The name followed by the row's role.
    static func selectedPlayerAccessibilityLabel(_ displayName: String) -> String {
        "\(displayName), Selected Player"
    }

    /// Whether a row names the page on screen, for the current-destination highlight.
    ///
    /// - Parameters:
    ///   - item: Drawer row.
    ///   - selected: Selected root section.
    ///   - topRoute: Route on top of the selected section's stack, if any.
    /// - Returns: True for the section root being shown, or the pushed page it opens.
    static func isCurrent(_ item: DrawerItem, selected: FestivalSection, topRoute: AppRoute?) -> Bool {
        switch item.intent {
        case let .select(section): section == selected && topRoute == nil
        case let .push(route): route == topRoute
        case .chooseProfile, .deselectProfile, .openSearch: false
        }
    }
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

    /// Padding that places the scrim's cut-out over the panel, in the scrim's coordinates.
    ///
    /// The scrim is itself inset by ``scrimInsets``, so the cut-out is laid out at the
    /// panel's real window position (rather than offset there), which keeps any
    /// position-dependent (concentric) corners identical to the panel's.
    var cutoutPadding: EdgeInsets {
        EdgeInsets(
            top: panelPadding.top - scrimInsets.top,
            leading: panelPadding.leading - scrimInsets.leading,
            bottom: panelPadding.bottom - scrimInsets.bottom,
            // The cut-out is leading-aligned at a fixed width, so its trailing edge is free.
            trailing: 0
        )
    }
}

// MARK: - Drawer corners

/// Corner geometry of the floating drawer panel.
///
/// iOS/macOS 26+ resolve every panel corner with `ConcentricRectangle` against the
/// window's container shape, which the system derives from the display's own corners:
/// each iPhone model, each iPhone Duo display, and the Duo's hinge-side versus outer
/// corners as it rotates. A corner nested in a display corner gets that radius minus its
/// inset; a corner that is not (beside the Duo's vertical bar or below its status bar),
/// or whose display corner is too tight, gets ``minimumRadius``. Only public API is used;
/// the display corner radius itself is never read (`_displayCornerRadius` is private).
enum DrawerCorners {
    /// Horizontal padding between the panel edge and its rows.
    static let contentInset: CGFloat = 12
    /// Corner radius of a row's current-page and pressed highlight.
    static let rowRadius: CGFloat = 14
    /// Smallest panel radius: concentric with the rows inside it (row radius plus the
    /// inset), so the panel still nests its own content where no display corner applies.
    static let minimumRadius: CGFloat = rowRadius + contentInset
    /// Fixed radius before iOS 26, which has no public container-concentric shape. It
    /// approximates an iPhone display corner at the 8 pt margin.
    static let legacyRadius: CGFloat = 44

    /// Per-corner style for the panel (iOS/macOS 26+): concentric with the display
    /// wherever it can be, never tighter than ``minimumRadius``.
    @available(iOS 26.0, macOS 26.0, *)
    static var panelCornerStyle: Edge.Corner.Style {
        .concentric(minimum: .fixed(minimumRadius))
    }

    /// The panel shape (iOS/macOS 26+). Corners resolve independently (not uniform), so
    /// a Duo panel can sit in an outer-side and a hinge-side corner at once.
    @available(iOS 26.0, macOS 26.0, *)
    static var panelShape: ConcentricRectangle {
        ConcentricRectangle(corners: panelCornerStyle, isUniform: false)
    }
}

/// Clip, mask or back a drawer view with the panel's corner shape.
private struct DrawerPanelShapeModifier: ViewModifier {
    enum Use {
        /// Liquid Glass (or its accessible fallback) behind the panel.
        case glass
        /// Clip to the shape (the panel's contents, and the scrim's cut-out under it).
        case clip
    }

    let use: Use

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            apply(DrawerCorners.panelShape, to: content)
        } else {
            apply(
                RoundedRectangle(cornerRadius: DrawerCorners.legacyRadius, style: .continuous),
                to: content
            )
        }
    }

    @ViewBuilder private func apply(_ shape: some Shape, to content: Content) -> some View {
        switch use {
        case .glass:
            content.modifier(FestivalGlassModifier(role: .overlay, shape: shape, interactive: false))
        case .clip:
            content.clipShape(shape)
        }
    }
}

private extension View {
    func drawerPanelShape(_ use: DrawerPanelShapeModifier.Use) -> some View {
        modifier(DrawerPanelShapeModifier(use: use))
    }
}

// MARK: - Drawer view

/// Leading slide-over navigation panel on dark Liquid Glass (web hamburger `Sidebar`).
///
/// Dismisses on scrim tap, a leading swipe, the close button, or the VoiceOver
/// escape gesture (two-finger Z); the iPad and iPhone Duo flyout also on Escape. The
/// panel is announced as modal so VoiceOver focus stays inside it. It always slides
/// over the content and never resizes it (`.agents/design/apple/split-view.md`).
struct FestivalDrawer: View {
    let session: FestivalSession
    let visibleSections: [FestivalSection]
    let hideShop: Bool
    /// Selected root section, for the current-destination highlight.
    var selected: FestivalSection = .songs
    /// Route on top of the selected section's stack, if any.
    var topRoute: AppRoute?
    /// The iPad flyout: a Search row heads the list (Search is not a tab there).
    var showsSearch = false
    /// Global search is showing (the Search row's current highlight).
    var searchActive = false
    /// Escape closes the panel (iPad and iPhone Duo hardware keyboards).
    var closesOnEscape = false
    let onIntent: (DrawerIntent) -> Void
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var deselectPending = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.deviceLayout) private var layout

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
                            // Laid out at the panel's own window position (the scrim is
                            // inset by `scrimInsets`), so its concentric corners resolve
                            // exactly like the panel's.
                            Color.black
                                .frame(width: width)
                                .drawerPanelShape(.clip)
                                .padding(placement.cutoutPadding)
                                .offset(x: min(0, dragOffset))
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
                    .drawerPanelShape(.glass)
                    #if DEBUG && os(iOS)
                    .overlay { DrawerCornerReadout(subject: "panel") }
                    #endif
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 4)
                    .padding(placement.panelPadding)
                    .offset(x: min(0, dragOffset))
                    .gesture(dismissDrag(width: width))
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape, onClose)
                if closesOnEscape {
                    // Hardware Escape (HIG Keyboards): an invisible cancel button.
                    Button("Close Navigation", action: onClose)
                        .keyboardShortcut(.escape, modifiers: [])
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
            #if DEBUG && os(iOS)
            // Full-window radii: the display's own corners, for comparison.
            .overlay(alignment: .bottom) { DrawerCornerReadout(subject: "display") }
            #endif
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
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.top, topInset)
            ScrollView {
                group((showsSearch ? [DrawerMenu.search] : []) + DrawerMenu.browse(
                    profile: profile, visibleSections: visibleSections, hideShop: hideShop
                ))
            }
            .scrollBounceBehavior(.basedOnSize)
            // Web sidebar footer: the profile row (or Select Profile), then Settings.
            VStack(alignment: .leading, spacing: 2) {
                profileSection
                group(DrawerMenu.more)
            }
            .padding(.bottom, bottomInset)
        }
        .padding(.horizontal, DrawerCorners.contentInset)
        .drawerPanelShape(.clip)
        // A container element, so the identifier does not replace the rows' own.
        .accessibilityElement(children: .contain)
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
            // Web: the player's name links to their profile, with Deselect beside it.
            // Same metrics as `DrawerRow` (avatar in the symbol column, body text) so the
            // name lines up with the other rows; the "Selected Player" role is spoken only.
            // Accessibility sizes stack Deselect under the name (HIG Typography: "consider
            // stacking text above secondary items").
            let footerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
            footerLayout {
                Button {
                    onIntent(.push(.player(
                        accountId: player.accountId, displayName: player.displayName
                    )))
                } label: {
                    HStack(spacing: DrawerRow.iconSpacing) {
                        ProfileAvatarImage(name: player.displayName, size: DrawerRow.iconWidth)
                        MarqueeText(player.displayName)
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DrawerRowStyle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(DrawerMenu.selectedPlayerAccessibilityLabel(player.displayName))
                .accessibilityHint("Opens your profile")
                .accessibilityIdentifier("fst.shell.drawer.view-profile")
                Button("Deselect") { deselectPending = true }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityLabel("Deselect Profile")
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

    private func group(_ items: [DrawerItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                let current = item.intent == .openSearch
                    ? searchActive
                    : !searchActive && DrawerMenu.isCurrent(item, selected: selected, topRoute: topRoute)
                DrawerRow(title: item.title, symbol: item.symbol, isCurrent: current) {
                    onIntent(item.intent)
                }
                .accessibilityIdentifier("fst.shell.drawer.\(item.id)")
            }
        }
    }
}

#if DEBUG && os(iOS)
// MARK: - Debug corner readout

/// `FST_DEBUG_DRAWER_RADII=1` (Debug, iOS 27+): prints the system-resolved concentric
/// radii (before ``DrawerCorners/minimumRadius``) of the view it overlays, so simulator
/// captures can verify concentricity per device, Duo display and rotation. Over the
/// full window it reports the display's own corner radii. Hidden from VoiceOver.
private struct DrawerCornerReadout: View {
    private static let enabled = ProcessInfo.processInfo.environment["FST_DEBUG_DRAWER_RADII"] == "1"

    /// Label for the first line (`panel` or `display`).
    let subject: String

    var body: some View {
        if Self.enabled {
            GeometryReader { geometry in
                Text(Self.describe(geometry, subject: subject))
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.yellow)
                    .padding(6)
                    .background(.black.opacity(0.7), in: .rect(cornerRadius: 6))
                    .padding(.bottom, subject == "display" ? 180 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: subject == "display" ? .bottom : .center)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private static func describe(_ geometry: GeometryProxy, subject: String) -> String {
        let frame = geometry.frame(in: .global)
        var lines = [String(format: "%@ x%.0f y%.0f w%.0f h%.0f", subject,
                            frame.minX, frame.minY, frame.width, frame.height)]
        if #available(iOS 27.0, *) {
            if let radii = geometry.concentricCornerRadii {
                lines.append(String(format: "TL %.1f  TR %.1f", radii.topLeading, radii.topTrailing))
                lines.append(String(format: "BL %.1f  BR %.1f", radii.bottomLeading, radii.bottomTrailing))
            } else {
                lines.append("no container shape")
            }
        } else {
            lines.append("radii need iOS 27")
        }
        lines.append(String(format: "minimum %.0f", DrawerCorners.minimumRadius))
        return lines.joined(separator: "\n")
    }
}
#endif

// MARK: - Row

/// Full-width drawer row with an SF Symbol, ≥ 48 pt tall, highlighted while pressed.
struct DrawerRow: View {
    let title: String
    let symbol: String
    var tint: Color = BrandTokens.textPrimary
    /// Highlights the page on screen (web `sidebarLinkActive`).
    var isCurrent = false
    let action: () -> Void

    /// Width of the leading symbol column (the selected-player avatar uses it too).
    static let iconWidth: CGFloat = 26
    /// Gap between the leading symbol column and the title.
    static let iconSpacing: CGFloat = 14

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.iconSpacing) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .frame(width: Self.iconWidth)
                    .foregroundStyle(tint == BrandTokens.textPrimary ? BrandTokens.textSecondary : tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .foregroundStyle(tint == .red ? tint : BrandTokens.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(
                isCurrent ? BrandTokens.accentBlue.opacity(0.28) : .clear,
                in: RoundedRectangle(cornerRadius: DrawerCorners.rowRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DrawerRowStyle())
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Rounded press highlight matching iOS 26 sidebar rows.
struct DrawerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.white.opacity(configuration.isPressed ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: DrawerCorners.rowRadius, style: .continuous)
            )
    }
}

// MARK: - Edge swipe

/// Opens the iPad / iPhone Duo flyout with a swipe in from the leading edge, like the
/// iPhone drawer it matches (`.agents/design/apple/split-view.md`). Enabled only at a
/// section root, where the system's own edge swipe (Back) has nothing to pop.
struct FlyoutEdgeSwipe: ViewModifier {
    let isEnabled: Bool
    let open: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    /// How far from the leading edge a swipe must start.
    static let edgeWidth: CGFloat = 24
    /// How far it must travel towards the trailing edge.
    static let minimumTravel: CGFloat = 60

    /// Whether a drag is a leading-edge swipe that opens the flyout.
    ///
    /// - Parameters:
    ///   - start: The drag's start x from the leading edge.
    ///   - translation: Its translation (positive = towards the trailing edge).
    /// - Returns: True when it started at the edge and travelled mostly sideways.
    static func opens(startFromLeading start: CGFloat, translation: CGSize) -> Bool {
        start <= edgeWidth && translation.width >= minimumTravel
            && abs(translation.height) < translation.width
    }

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    guard isEnabled else { return }
                    let rtl = layoutDirection == .rightToLeft
                    // `.local` x is already measured from the leading edge in SwiftUI.
                    let translation = CGSize(
                        width: rtl ? -value.translation.width : value.translation.width,
                        height: value.translation.height
                    )
                    if Self.opens(startFromLeading: value.startLocation.x, translation: translation) { open() }
                },
            isEnabled: isEnabled
        )
    }
}
