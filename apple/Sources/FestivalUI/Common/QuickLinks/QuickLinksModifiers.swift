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
    ///     becomes active and where a jump lands it.
    ///   - listNudger: For a `List`, which centres any scroll anchor but `.top`: jumps
    ///     land flush and the nudger moves the List onto the activation line. Its
    ///     ``ListScrollViewLocator`` must sit in one of the List's rows.
    /// - Returns: The scroll view with quick-links behavior.
    func quickLinks(
        _ controller: QuickLinksController,
        title: String,
        sections: [QuickLinkSection]? = nil,
        activationOffset: Double = QuickLinks.defaultActivationOffset,
        listNudger: ListScrollNudger? = nil
    ) -> some View {
        modifier(QuickLinksContainerModifier(
            controller: controller, title: title,
            sections: sections, activationOffset: activationOffset, listNudger: listNudger
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

// MARK: - Accessory tool

/// Offers the page's Quick Links menu to the iPhone tab-bar accessory while it has
/// sections (``PageToolsRegistry``); a no-op where Quick Links is a toolbar item.
struct QuickLinksPageTool: ViewModifier {
    let controller: QuickLinksController

    func body(content: Content) -> some View {
        let available = controller.isAvailable
        content.festivalPageTool(
            token: available, order: PageToolOrder.quickLinks, isEnabled: available
        ) {
            QuickLinksMenu(controller: controller)
        }
    }
}

// MARK: - Container

/// Implementation of `.quickLinks(_:title:sections:activationOffset:listNudger:)`.
struct QuickLinksContainerModifier: ViewModifier {
    let controller: QuickLinksController
    let title: String
    let sections: [QuickLinkSection]?
    let activationOffset: Double
    /// Set for a `List`, which centres any scroll anchor but `.top`: jumps land flush,
    /// then this moves the List onto the landing line (issue #286).
    let listNudger: ListScrollNudger?
    /// A `List`'s top content inset: its section frames are measured from the top of the
    /// List under the bars, not from the visible top, so the activation line moves down
    /// by it. 0 for a `ScrollView` and before iOS 18 / macOS 15.
    @State private var listTopInset: Double = 0
    @Namespace private var rotorNamespace

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .modifier(ListTopInsetReader(enabled: listNudger != nil) { listTopInset = $0 })
                .coordinateSpace(.named(quickLinksSpace))
                .environment(\.quickLinksContext, QuickLinksContext(
                    controller: controller, rotorNamespace: rotorNamespace
                ))
                .onPreferenceChange(QuickLinkSectionsKey.self) { discovered in
                    MainActor.assumeIsolated { controller.discover(discovered) }
                }
                .onGeometryChange(for: Double.self) { geometry in
                    // Visible height below the bars the content scrolls under. The
                    // proxy's size already excludes the safe-area insets it reports
                    // (measured: 617 = 874 − 116 − 141 on iPhone 17 Pro); subtracting
                    // them again under-measured it and mis-aimed jumps (#12).
                    geometry.size.height
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
        .onChange(of: activationOffset) { configure() }
        .onChange(of: listTopInset) { configure() }
        // iPhone tab-bar accessory (issue #92): Quick Links after the page's actions.
        .modifier(QuickLinksPageTool(controller: controller))
        // Go › Quick Links / Next Section / Previous Section (HIG Toolbars › macOS:
        // "Every toolbar item must also be a menu-bar command"; iPadOS menu bar too).
        .modifier(MacQuickLinksPublisher(controller: controller))
    }

    private func configure() {
        controller.activationOffset = QuickLinks.activationLine(
            offset: activationOffset, listTopInset: listNudger == nil ? 0 : listTopInset
        )
        controller.configure(title: title, explicit: sections)
    }

    /// The scroll anchor for a jump: `.top` in a `List` (``listNudger`` corrects the
    /// rest), otherwise one that lands on the activation line.
    ///
    /// - Parameter target: The jump's target section id.
    /// - Returns: The anchor for `ScrollViewProxy.scrollTo(_:anchor:)`.
    private func anchor(for target: String) -> UnitPoint {
        listNudger == nil ? controller.landingAnchor(for: target) : .top
    }

    /// Scroll to the latest jump target, then report arrival.
    ///
    /// The target lands `activationOffset` points below the visible top, like the
    /// web, rather than flush with it: on iOS 26 the navigation bar's scroll-edge
    /// effect blurs and dims the first ~30 pt of content, which hid the section
    /// title (#12). `ScrollViewProxy` has no offset, so the anchor is computed from
    /// the target's measured height (`QuickLinksController.landingAnchor(for:)`);
    /// an unmeasured target uses `.top` until it is built.
    ///
    /// Two distinct sources of lag can make `jumpDidSettle()` read stale
    /// geometry if called straight after the scroll: under device/simulator load
    /// the real motion can lag the request, and a target inside a
    /// `LazyVStack`/`List` that has never been built yet is first scrolled to
    /// using an *estimated* position, so the scroll settles short of it once the
    /// real view is realized. Both show up the same way: `QuickLinkTracker.settle`
    /// reads a frame that hasn't reached its final position yet and falls back to
    /// `QuickLinks.naturalActive` one section short of the real target.
    /// `correctAndSettle` re-targets the scroll, then *polls* the target's
    /// reported frame until it stops moving (rather than guessing a fixed delay)
    /// before calling `jumpDidSettle()`, so it is correct at any device speed.
    ///
    /// A newer jump supersedes this one's corrective pass (#393): a held ⌥⌘↓ Next
    /// Section or a quick rotor flick jumps again within the poll window, and the
    /// stale pass re-landed its old target, scrolling the page back and settling the
    /// newer jump on that geometry, so Quick Links named the wrong section.
    ///
    /// - Parameter proxy: Reader proxy for the wrapped scroll view.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let target = controller.jumpTarget else { return }
        let serial = controller.jumpSerial
        // Jumps are instant ("teleport", operator batch 7), with or without Reduce
        // Motion; the corrective pass then lands a lazily built target exactly.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            proxy.scrollTo(target, anchor: anchor(for: target))
        }
        Task { @MainActor in await correctAndSettle(proxy, target: target, serial: serial) }
    }

    /// Re-target the scroll, poll until the target's real, now-realized frame
    /// stops changing, and re-land it (at most twice) if it settled off its
    /// landing line, before handing off to `jumpDidSettle()`.
    ///
    /// A target near either end of the content cannot reach the line; the bounded
    /// retries then leave it where the scroll view clamps it. The pass ends without
    /// scrolling or settling as soon as a newer jump starts; that jump owns both.
    ///
    /// - Parameters:
    ///   - proxy: Reader proxy for the wrapped scroll view.
    ///   - target: The jump's target section id.
    ///   - serial: The jump's `QuickLinksController.jumpSerial`.
    private func correctAndSettle(_ proxy: ScrollViewProxy, target: String, serial: Int) async {
        guard controller.jumpSerial == serial else { return }
        proxy.scrollTo(target, anchor: anchor(for: target))
        var lastFrame = controller.currentFrame(for: target)
        var stableStreak = 0
        var relandings = 0
        // Bounded so a target that can never stabilize (e.g. removed mid-poll)
        // can't stall the UI indefinitely.
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            guard controller.jumpSerial == serial else { return }
            let frame = controller.currentFrame(for: target)
            guard frame == lastFrame else {
                stableStreak = 0
                lastFrame = frame
                continue
            }
            stableStreak += 1
            guard stableStreak >= 2 else { continue }
            // A lazily built target was measured only after the first anchor was
            // chosen; land it again now that its height is known.
            if relandings < 2, let frame, !controller.isLanded(target) {
                relandings += 1
                stableStreak = 0
                if let listNudger {
                    let distance = controller.activationOffset - frame.minY
                    guard listNudger.moveContent(by: CGFloat(distance)) else { break }
                } else {
                    proxy.scrollTo(target, anchor: anchor(for: target))
                }
                continue
            }
            break
        }
        guard controller.jumpSerial == serial else { return }
        controller.jumpDidSettle()
    }
}

/// Reports a `List`'s top content inset in whole points (iOS 18 / macOS 15 and later;
/// nothing before, or when disabled).
private struct ListTopInsetReader: ViewModifier {
    let enabled: Bool
    let changed: (Double) -> Void

    func body(content: Content) -> some View {
        if enabled, #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: Double.self) { geometry in
                Double(geometry.contentInsets.top.rounded())
            } action: { _, inset in
                changed(inset)
            }
        } else {
            content
        }
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
                // `transformPreference`, not `preference`: the latter replaces what
                // nested sections report, which dropped them from the menu.
                .transformPreference(QuickLinkSectionsKey.self) { nested in
                    nested = QuickLinks.nesting(section, descendants: nested)
                }
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
