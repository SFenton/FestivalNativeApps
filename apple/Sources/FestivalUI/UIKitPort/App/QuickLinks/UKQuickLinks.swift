#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Registry

/// The Quick Links of the page on screen, for the menu bar's Next / Previous Section.
@MainActor
final class UKQuickLinksRegistry {
    /// The window-wide registry.
    static let shared = UKQuickLinksRegistry()
    /// The front page's controller.
    weak var front: QuickLinksController?
}

// MARK: - Quick Links binding

/// Wires a page's ``QuickLinksController`` to its scroll view and bar: the UIKit
/// counterpart of the `.quickLinks(_:title:sections:)` container, `.quickLinkSection(…)`
/// anchors and ``QuickLinksToolbarItem``.
///
/// A page creates one with its controller, calls ``attach(to:rect:element:)``, forwards
/// `scrollViewDidScroll` to ``scrollViewDidScroll()``, calls ``didAppear()`` and
/// ``willDisappear()``, and lists ``tool`` among its ``UKPageToolsProviding/ukPageTools``.
/// Frames are measured against the scroll view's visible region below its bars, as the
/// SwiftUI container does, so the active section and landing line match.
@MainActor
final class UKQuickLinks {
    /// The page's controller.
    let controller: QuickLinksController
    private let title: String
    private let explicit: [QuickLinkSection]?
    private let activationOffset: Double
    private weak var scrollView: UIScrollView?
    private var rect: ((String) -> CGRect?)?
    private var element: ((String) -> NSObject?)?
    private let observations = UKObservationBag()
    private var lastJump = 0
    private let feedback = UISelectionFeedbackGenerator()
    private var item: UIBarButtonItem?
    /// Called when the tool appears, disappears or changes (the page then refreshes its bar).
    var onToolChange: (() -> Void)?

    /// Creates the binding.
    ///
    /// - Parameters:
    ///   - controller: Page-owned controller.
    ///   - title: Menu and rotor title.
    ///   - sections: Display-ordered sections (required for lazy lists), or nil to call
    ///     ``discover(_:)`` as anchors appear.
    ///   - activationOffset: Distance below the visible top where a section becomes active.
    init(
        controller: QuickLinksController, title: String, sections: [QuickLinkSection]? = nil,
        activationOffset: Double = QuickLinks.defaultActivationOffset
    ) {
        self.controller = controller
        self.title = title
        self.explicit = sections
        self.activationOffset = activationOffset
        controller.activationOffset = activationOffset
        controller.configure(title: title, explicit: sections)
        lastJump = controller.jumpSerial
        observations.observe { [weak self] in self?.jumpRequested() }
        observations.observe { [weak self] in self?.rebuildItem() }
    }

    /// Attaches the page's scroll view.
    ///
    /// - Parameters:
    ///   - scrollView: The scrolling surface.
    ///   - rect: A section's frame in the scroll view's content coordinates, or nil while
    ///     it is not laid out.
    ///   - element: A section's accessibility element for the VoiceOver rotor.
    func attach(to scrollView: UIScrollView, rect: @escaping (String) -> CGRect?, element: ((String) -> NSObject?)? = nil) {
        self.scrollView = scrollView
        self.rect = rect
        self.element = element
        scrollView.accessibilityCustomRotors = [rotor()]
        scrollViewDidScroll()
    }

    /// Replaces the sections discovered from the anchors on screen.
    ///
    /// - Parameter sections: Sections in page order.
    func discover(_ sections: [QuickLinkSection]) {
        controller.discover(sections)
    }

    /// The page's scroll view moved or resized: reports the viewport and each frame.
    func scrollViewDidScroll() {
        guard let scrollView, let rect else { return }
        let top = scrollView.adjustedContentInset.top
        let viewport = scrollView.bounds.height - top - scrollView.adjustedContentInset.bottom
        controller.reportViewport(height: Double(viewport))
        for section in controller.sections {
            if let frame = rect(section.id) {
                let minY = frame.minY - scrollView.contentOffset.y - top
                controller.report(section.id, frame: QuickLinkFrame(minY: Double(minY), maxY: Double(minY + frame.height)))
            } else {
                controller.report(section.id, frame: nil)
            }
        }
    }

    /// The page appeared: it becomes the menu bar's Quick Links.
    func didAppear() {
        UKQuickLinksRegistry.shared.front = controller
        scrollViewDidScroll()
    }

    /// The page disappeared.
    func willDisappear() {
        if UKQuickLinksRegistry.shared.front === controller { UKQuickLinksRegistry.shared.front = nil }
    }

    // MARK: Jumping

    private func jumpRequested() {
        let serial = controller.jumpSerial
        guard serial != lastJump else { return }
        lastJump = serial
        guard let target = controller.jumpTarget else { return }
        feedback.selectionChanged()
        Task { @MainActor in await self.land(on: target, serial: serial) }
    }

    /// Scrolls the target onto the landing line, re-landing a lazily built target until its
    /// frame stops moving, then reports arrival (`correctAndSettle`).
    private func land(on target: String, serial: Int) async {
        var relandings = 0
        var last: QuickLinkFrame?
        var stable = 0
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            guard controller.jumpSerial == serial, let scrollView else { return }
            scrollViewDidScroll()
            let frame = controller.currentFrame(for: target)
            if frame == last, frame != nil { stable += 1 } else { stable = 0 }
            last = frame
            if let frame {
                let delta = frame.minY - controller.activationOffset
                if abs(delta) > 1, relandings < 4 {
                    relandings += 1
                    let minOffset = -scrollView.adjustedContentInset.top
                    let maxOffset = max(minOffset, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
                    let y = min(max(scrollView.contentOffset.y + CGFloat(delta), minOffset), maxOffset)
                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
                    stable = 0
                } else if stable >= 2 {
                    break
                }
            } else if let rect = rect?(target) {
                // Not measured yet: jump near it so a lazy list builds it.
                let y = max(-scrollView.adjustedContentInset.top, rect.minY - scrollView.adjustedContentInset.top - CGFloat(controller.activationOffset))
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard controller.jumpSerial == serial else { return }
        controller.jumpDidSettle()
    }

    // MARK: Tool

    /// The page tool while the page offers Quick Links (two or more sections), else nil.
    var tool: UKPageTool? {
        guard controller.isAvailable, let item else { return nil }
        return UKPageTool(order: PageToolOrder.quickLinks, item: item)
    }

    private func rebuildItem() {
        let available = controller.isAvailable
        let active = controller.activeID
        let sections = controller.sections
        let menuTitle = controller.title
        let value = controller.activeSection?.title ?? ""
        guard available else {
            if item != nil { item = nil; onToolChange?() }
            return
        }
        let actions: [UIMenuElement] = sections.map { section in
            let indent = String(repeating: "\u{2007}\u{2007}", count: section.depth)
            let action = UIAction(
                title: indent + section.title,
                image: { if case let .system(name)? = section.icon { UIImage(systemName: name) } else { nil } }(),
                identifier: nil, state: section.id == active ? .on : .off
            ) { [weak self] _ in self?.controller.jump(to: section.id) }
            action.accessibilityLabel = section.accessibilityTitle
            action.accessibilityIdentifier = "fst.quick-links.item.\(section.id)"
            return action
        }
        let menu = UIMenu(title: menuTitle, options: [.displayInline, .singleSelection], children: actions)
        let created = item == nil
        let bar = item ?? UIBarButtonItem(title: "Quick Links", image: UIImage(systemName: "list.bullet.indent"), target: nil, action: nil)
        bar.menu = UIMenu(children: [menu])
        bar.preferredMenuElementOrder = .fixed
        bar.tintColor = BrandUIColors.textPrimary
        bar.accessibilityLabel = "Quick Links"
        bar.accessibilityValue = value
        bar.accessibilityHint = "Jumps to a section of this page"
        bar.accessibilityIdentifier = "fst.quick-links.open"
        item = bar
        if created { onToolChange?() }
    }

    // MARK: Rotor

    private func rotor() -> UIAccessibilityCustomRotor {
        UIAccessibilityCustomRotor(name: controller.title) { [weak self] predicate in
            guard let self, let element = self.element else { return nil }
            let ids = self.controller.sections.map(\.id)
            guard !ids.isEmpty else { return nil }
            let forward = predicate.searchDirection == .next
            var index: Int?
            if let current = predicate.currentItem.targetElement as? NSObject,
               let known = ids.firstIndex(where: { element($0) === current }) {
                index = known + (forward ? 1 : -1)
            } else {
                index = forward ? 0 : ids.count - 1
            }
            guard let index, ids.indices.contains(index), let target = element(ids[index]) else { return nil }
            return UIAccessibilityCustomRotorItemResult(targetElement: target, targetRange: nil)
        }
    }
}
#endif
