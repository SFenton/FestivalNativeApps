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
    /// Outside a container it only sets `.id(section.id)`.
    ///
    /// - Parameter section: The section this view starts.
    /// - Returns: The tagged view.
    func quickLinkSection(_ section: QuickLinkSection) -> some View {
        modifier(QuickLinkSectionModifier(section: section))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        AccessibilityRotorEntry(Text(section.title), id: section.id, in: rotorNamespace)
                    }
                }
        }
        .onAppear { configure() }
        .onChange(of: title) { configure() }
        .onChange(of: sections) { configure() }
    }

    private func configure() {
        controller.activationOffset = activationOffset
        controller.configure(title: title, explicit: sections)
    }

    /// Scroll to the latest jump target, then report arrival.
    ///
    /// - Parameter proxy: Reader proxy for the wrapped scroll view.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let target = controller.jumpTarget else { return }
        if reduceMotion {
            proxy.scrollTo(target, anchor: .top)
            // Let layout publish the new frames before settling.
            Task { @MainActor in controller.jumpDidSettle() }
        } else {
            withAnimation(.smooth(duration: 0.45), completionCriteria: .logicallyComplete) {
                proxy.scrollTo(target, anchor: .top)
            } completion: {
                controller.jumpDidSettle()
            }
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
                .id(section.id)
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
            content.id(section.id)
        }
    }
}
