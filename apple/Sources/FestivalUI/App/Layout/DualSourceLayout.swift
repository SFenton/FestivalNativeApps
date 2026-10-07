import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Region environment

/// Which dual-source region a view renders in.
enum DualSourceRegion: Sendable, Equatable {
    /// The top region: the page's own content.
    case primary
    /// The bottom region: the related second source.
    case secondary
}

extension EnvironmentValues {
    /// The dual-source region this view sits in, or nil while the page shows its
    /// primary content alone (every pose except the iPhone Duo inner display in portrait).
    @Entry var dualSourceRegion: DualSourceRegion?

    /// Width of the dual-source regions in points (both span the layout's full width),
    /// or nil while the page shows its primary content alone or before the layout first
    /// measured itself. The secondary region only appears once measured, so it reads the
    /// width on its first build: content whose first-load stagger order depends on what
    /// fits on screen (Compete's Rivals pane header after the leaderboard cards) derives
    /// it synchronously instead of correcting it after layout (load-transition R5).
    @Entry var dualSourceRegionWidth: CGFloat?
}

// MARK: - Layout

/// A page body with an optional second, related source below it.
///
/// On the iPhone Duo inner display in portrait the body divides into two stacked
/// regions (``DualSourcePolicy``): partially open, exactly at the horizontal fold;
/// flat, proportionally. The primary content stays on top and keeps its identity and
/// state across poses; only the secondary appears or disappears. Every other window
/// shows the primary alone, laid out exactly as without this wrapper.
///
/// ```swift
/// DualSourceLayout {
///     songsList
/// } secondary: {
///     SongsSuggestionsPane(session: session)
/// }
/// ```
///
/// Keep the secondary self-contained (its own loading, empty and error states) and
/// never put navigation containers in it; its links push onto the page's own stack.
struct DualSourceLayout<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary

    @Environment(\.deviceLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @State private var container: CGRect = .zero

    /// Create a dual-source body.
    ///
    /// - Parameters:
    ///   - primary: The page's usual content (top region).
    ///   - secondary: The related second source (bottom region).
    init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.primary = primary()
        self.secondary = secondary()
    }

    private var regions: DualSourcePolicy.Regions? {
        DualSourcePolicy.regions(mode: DualSourcePolicy.mode(layout), container: container)
    }

    var body: some View {
        let regions = regions
        let split = split
        let regionWidth = regions == nil ? nil : container.width
        VStack(spacing: 0) {
            primary
                .frame(height: regions?.primary)
                .environment(\.dualSourceRegion, regions == nil ? nil : .primary)
                .environment(\.dualSourceRegionWidth, regionWidth)
            if let regions {
                // The fold (or the flat gutter): never interactive.
                Color.clear
                    .frame(height: regions.gap)
                    .accessibilityHidden(true)
                secondary
                    .frame(maxWidth: .infinity)
                    .frame(height: regions.secondary)
                    .environment(\.dualSourceRegion, .secondary)
                    .environment(\.dualSourceRegionWidth, regionWidth)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("fst.dual.secondary")
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        // While split, claim the whole proposed area so the regions can be measured
        // (a short primary would otherwise size the container to itself); single, stay
        // exactly as tall as the primary.
        .frame(maxWidth: split ? .infinity : nil, maxHeight: split ? .infinity : nil, alignment: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: regions)
        // Only the vertical extent and the width matter, and only while split: horizontal
        // motion (push transitions) and every other pose never re-render the page.
        .onGeometryChange(for: CGRect.self, of: { [split] proxy in
            guard split else { return .zero }
            let frame = proxy.frame(in: .global)
            return CGRect(
                x: 0, y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded()
            )
        }) { measured in
            // The first measurement of a split page places the regions without
            // animation; later changes (fold ↔ flat) animate the divider.
            if container == .zero {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { container = measured }
            } else {
                container = measured
            }
        }
    }

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }
    private var split: Bool { DualSourcePolicy.isActive(layout) }
}

// MARK: - Secondary pane chrome

/// The standard frame for a secondary region: a Title Case header with an optional
/// "View All" push, over content that fills the rest of the region.
struct DualSourcePane<Content: View>: View {
    private let title: String
    private let systemImage: String
    private let seeAll: AppRoute?
    private let identifier: String
    private let entranceIndex: Int?
    private let content: Content

    /// Create a pane.
    ///
    /// - Parameters:
    ///   - title: Title Case header naming the second source.
    ///   - systemImage: SF Symbol shown before the title.
    ///   - seeAll: Route pushed by the header's "View All" link, if the source has a page.
    ///   - identifier: Accessibility identifier suffix (`fst.dual.<identifier>`).
    ///   - entranceIndex: The header's position in the page's first-load stagger (inside
    ///     a page fade scope, load-transition R5), or nil for a header that shows at once.
    ///   - content: The source's content, usually a ``HorizontalCarousel``.
    init(
        _ title: String, systemImage: String, seeAll: AppRoute? = nil, identifier: String,
        entranceIndex: Int? = nil, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.seeAll = seeAll
        self.identifier = identifier
        self.entranceIndex = entranceIndex
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(BrandTokens.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let seeAll {
                    SectionViewAllLink(route: seeAll, identifier: "fst.dual.\(identifier).view-all", listName: title)
                }
            }
            .padding(.horizontal, 16)
            .festivalFadeIn(staggerIndex: entranceIndex)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 8)
        // `.contain` keeps the header link's own identifier reachable under the pane's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.dual.\(identifier)")
    }
}

/// A compact message filling a secondary region: loading, empty, paused or error.
struct DualSourceMessage<Actions: View>: View {
    private let title: String
    private let systemImage: String
    private let message: String
    private let actions: Actions

    /// Create a message.
    ///
    /// - Parameters:
    ///   - title: Short Title Case headline.
    ///   - systemImage: SF Symbol.
    ///   - message: One explanatory sentence.
    ///   - actions: Optional buttons (Choose Profile, Retry).
    init(
        _ title: String, systemImage: String, message: String,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(BrandTokens.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(BrandTokens.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(BrandTokens.textSecondary)
                .multilineTextAlignment(.center)
            actions
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .festivalCard(cornerRadius: 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Selection inside a dual page

extension View {
    /// Let ``ListDetailLink`` rows in a dual page's primary region select into its
    /// secondary region instead of pushing (the list/detail rule "rows select, they
    /// don't push", applied to stacked regions). A no-op while the page shows one
    /// region, so iPhone and every other pose keep their plain links.
    ///
    /// - Parameters:
    ///   - selection: The selected detail route, shown by the secondary region.
    ///   - section: Section whose path the page belongs to (select-action identity).
    /// - Returns: The primary content with dual selection environment.
    func dualSourceSelection(_ selection: Binding<AppRoute?>, section: FestivalSection) -> some View {
        modifier(DualSourceSelectionModifier(selection: selection, section: section))
    }
}

/// Installs the list/detail selection environment only while the page is split.
private struct DualSourceSelectionModifier: ViewModifier {
    @Binding var selection: AppRoute?
    let section: FestivalSection
    @Environment(\.deviceLayout) private var layout

    func body(content: Content) -> some View {
        // Transform, not set: inactive, a list/detail split's own selection environment
        // (landscape inner display) must pass through untouched.
        let active = DualSourcePolicy.isActive(layout)
        let selected = selection
        let binding = $selection
        content
            .transformEnvironment(\.listDetailSelection) { value in
                if active { value = selected }
            }
            .transformEnvironment(\.listDetailSelect) { value in
                if active {
                    value = ListDetailSelectAction(section: section) { route in binding.wrappedValue = route }
                }
            }
    }
}
