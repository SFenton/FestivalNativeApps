import SwiftUI
import FestivalCore

// MARK: - Environment

/// Wiring the `.quickLinks` container hands to the `.quickLinkSection` views inside it.
struct QuickLinksContext {
    let controller: QuickLinksController
    let rotorNamespace: Namespace.ID
}

extension EnvironmentValues {
    /// The enclosing quick-links container, if any.
    @Entry var quickLinksContext: QuickLinksContext? = nil
}

/// Sections reported by `.quickLinkSection` views, in view-tree order.
struct QuickLinkSectionsKey: PreferenceKey {
    static let defaultValue: [QuickLinkSection] = []

    static func reduce(value: inout [QuickLinkSection], nextValue: () -> [QuickLinkSection]) {
        value.append(contentsOf: nextValue())
    }
}

/// Coordinate space of the quick-links scroll container.
private let quickLinksSpace = "fst.quick-links.space"

// MARK: - Public modifiers

public extension View {
    /// Make this scroll view (`ScrollView` or `List`) a quick-links container.
    ///
    /// Wraps it in a `ScrollViewReader`, tracks which section is active, performs
    /// jumps requested through `controller` (animated, or instant under Reduce
    /// Motion), plays a selection haptic and adds a VoiceOver "Sections" rotor.
    /// Pair with `QuickLinksToolbarItem(controller)` and `.quickLinkSection(…)`.
    ///
    /// - Parameters:
    ///   - controller: Page-owned controller shared with the toolbar item.
    ///   - title: Menu and rotor title (web `quickLinks.title`).
    ///   - sections: Display-ordered sections. Required for lazy containers
    ///     (`LazyVStack`, `List`) because off-screen sections are not built yet;
    ///     pass `nil` to discover sections from `.quickLinkSection` views instead.
    ///   - activationOffset: Distance below the visible top at which a section
    ///     becomes active.
    /// - Returns: The scroll view with quick-links behavior.
    func quickLinks(
        _ controller: QuickLinksController,
        title: String,
        sections: [QuickLinkSection]? = nil,
        activationOffset: Double = QuickLinks.defaultActivationOffset
    ) -> some View {
        modifier(QuickLinksContainerModifier(
            controller: controller, title: title,
            sections: sections, activationOffset: activationOffset
        ))
    }

    /// Mark this view as a quick-link anchor inside a `.quickLinks` container.
    ///
    /// Gives the view a scroll identity, reports its frame for active-section
    /// tracking, registers it for discovery and as a VoiceOver rotor entry.
    /// Outside a container it only sets `.id(section.id)`. Apply it to the element
    /// view a `ForEach` returns so lazy containers can scroll to unbuilt sections.
    ///
    /// - Parameter section: The section this view starts.
    /// - Returns: The tagged view.
    func quickLinkSection(_ section: QuickLinkSection) -> some View {
        // `.id` must be the outermost modifier so lazy stacks can resolve a
        // not-yet-built section from its ForEach element when asked to scroll to it.
        modifier(QuickLinkSectionModifier(section: section)).id(section.id)
    }

    /// Mark this view as a quick-link anchor with an SF Symbol glyph.
    ///
    /// - Parameters:
    ///   - id: Stable anchor id, unique within the page.
    ///   - title: Menu label and VoiceOver name.
    ///   - symbol: Optional SF Symbol name.
    /// - Returns: The tagged view.
    func quickLinkSection(id: String, title: String, symbol: String? = nil) -> some View {
        quickLinkSection(QuickLinkSection(id: id, title: title, icon: symbol.map(QuickLinkIcon.system)))
    }
}

// MARK: - Container

/// Implementation of `.quickLinks(_:title:sections:activationOffset:)`.
struct QuickLinksContainerModifier: ViewModifier {
    let controller: QuickLinksController
    let title: String
    let sections: [QuickLinkSection]?
    let activationOffset: Double
    @Namespace private var rotorNamespace

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .coordinateSpace(.named(quickLinksSpace))
                .environment(\.quickLinksContext, QuickLinksContext(
                    controller: controller, rotorNamespace: rotorNamespace
                ))
                .onPreferenceChange(QuickLinkSectionsKey.self) { discovered in
                    MainActor.assumeIsolated { controller.discover(discovered) }
                }
                .onGeometryChange(for: Double.self) { geometry in
                    // Visible height below the bars the content scrolls under.
                    geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom
                } action: { height in
                    controller.reportViewport(height: height)
                }
                .onChange(of: controller.jumpSerial) {
                    scroll(proxy)
                }
                .sensoryFeedback(.selection, trigger: controller.jumpSerial)
                .accessibilityRotor(Text(controller.title)) {
                    ForEach(controller.sections) { section in
                        AccessibilityRotorEntry(Text(section.accessibilityTitle), id: section.id, in: rotorNamespace)
                    }
                }
        }
        .onAppear { configure() }
        .onChange(of: title) { configure() }
        .onChange(of: sections) { configure() }
        // iPhone: the Quick Links menu lives in the bottom dock (operator, 2026-09-28);
        // `QuickLinksToolbarItem` steps aside there (`.agents/design/apple/nav-accessories.md`).
        .festivalTabAccessory(
            token: controller.isAvailable, order: DockOrder.quickLinks,
            accessibilityID: "fst.quick-links.open", isEnabled: controller.isAvailable
        ) {
            QuickLinksMenu(controller: controller)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    private func configure() {
        controller.activationOffset = activationOffset
        controller.configure(title: title, explicit: sections)
    }

    /// Scroll to the latest jump target, then report arrival.
    ///
    /// Two distinct sources of lag can make `jumpDidSettle()` read stale
    /// geometry if called straight from the animation's completion handler:
    /// `withAnimation(...completionCriteria: .logicallyComplete)` can fire once
    /// SwiftUI's transaction commits, which is not guaranteed to be after the
    /// scroll has visually finished moving — under device/simulator load, the
    /// real motion can keep going well past the declared duration while the
    /// completion handler fires on schedule. Separately, a target inside a
    /// `LazyVStack`/`List` that has never been built yet is first scrolled to
    /// using an *estimated* position; once the real view is realized, its true
    /// frame can differ, and the scroll settles short of it. Both show up the
    /// same way: `QuickLinkTracker.settle` reads a frame that hasn't reached its
    /// final position yet and falls back to `QuickLinks.naturalActive` one
    /// section short of the real target. `correctAndSettle` re-targets the
    /// scroll once, then *polls* the target's reported frame until it stops
    /// moving (rather than guessing a fixed delay) before calling
    /// `jumpDidSettle()`, so it is correct at any device speed.
    ///
    /// - Parameter proxy: Reader proxy for the wrapped scroll view.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let target = controller.jumpTarget else { return }
        // Jumps are instant ("teleport", operator batch 7), with or without Reduce
        // Motion; the corrective pass then lands a lazily built target exactly.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            proxy.scrollTo(target, anchor: .top)
        }
        Task { @MainActor in await correctAndSettle(proxy, target: target, initialFloor: .zero) }
    }

    /// Re-target the scroll once past `initialFloor`, then poll until the
    /// target's real, now-realized frame stops changing before handing off to
    /// `jumpDidSettle()`.
    ///
    /// - Parameters:
    ///   - proxy: Reader proxy for the wrapped scroll view.
    ///   - target: The jump's target section id.
    ///   - initialFloor: Time to wait out before the corrective re-scroll — the
    ///     declared animation duration (its completion can otherwise fire before
    ///     the real motion finishes), or zero when the caller already scrolled
    ///     synchronously (Reduce Motion).
    private func correctAndSettle(
        _ proxy: ScrollViewProxy, target: String, initialFloor: Duration
    ) async {
        if initialFloor > .zero {
            try? await Task.sleep(for: initialFloor)
        }
        proxy.scrollTo(target, anchor: .top)
        var lastFrame = controller.currentFrame(for: target)
        var stableStreak = 0
        // Bounded so a target that can never stabilize (e.g. removed mid-poll)
        // can't stall the UI indefinitely.
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            let frame = controller.currentFrame(for: target)
            if frame == lastFrame {
                stableStreak += 1
                if stableStreak >= 2 { break }
            } else {
                stableStreak = 0
                lastFrame = frame
            }
        }
        controller.jumpDidSettle()
    }
}

// MARK: - Section

/// Implementation of `.quickLinkSection(_:)`.
struct QuickLinkSectionModifier: ViewModifier {
    let section: QuickLinkSection
    @Environment(\.quickLinksContext) private var context

    func body(content: Content) -> some View {
        if let context {
            content
                .preference(key: QuickLinkSectionsKey.self, value: [section])
                .accessibilityRotorEntry(id: section.id, in: context.rotorNamespace)
                .onGeometryChange(for: QuickLinkFrame.self) { geometry in
                    let frame = geometry.frame(in: .named(quickLinksSpace))
                    return QuickLinkFrame(minY: Double(frame.minY), maxY: Double(frame.maxY))
                } action: { frame in
                    context.controller.report(section.id, frame: frame)
                }
                .onDisappear { context.controller.report(section.id, frame: nil) }
        } else {
            content
        }
    }
}
