import SwiftUI
import FestivalCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - PublicationFocusProbe

/// Tells a ``PublicationRefreshBoundary`` whether VoiceOver focus is inside its page
/// (issue #304, load-transition R9), so a refresh moves focus to the page anchor only when
/// the focused element is about to be hidden, never from the tab bar, navigation bar, a
/// sheet or another column.
///
/// iOS/iPadOS: an invisible, inert `UIView` behind the page reports the page's screen
/// frame, its view controller and whether anything is presented over it; the focused
/// element comes from `UIAccessibility.focusedElement(using: .notificationVoiceOver)`.
/// ``PublicationRefreshFocus/Location`` (FestivalCore) makes the decision.
///
/// macOS exposes no VoiceOver cursor to apps, so the probe never reports focus inside
/// the page there: the Mac announces the refresh without moving focus (HIG Focus and
/// selection: "Don't change focus without user interaction").
@MainActor
final class PublicationFocusProbe {
    #if canImport(UIKit)
    /// The probe view behind the page.
    fileprivate weak var view: UIView?
    #endif

    /// Whether VoiceOver focus is inside the page right now.
    ///
    /// - Parameter pageOnScreen: Whether the page is on screen (appeared, not covered by a
    ///   pushed page or another tab).
    /// - Returns: True only when the focused element is established to belong to the page.
    func voiceOverFocusIsInsidePage(pageOnScreen: Bool) -> Bool {
        #if canImport(UIKit)
        guard let view, view.window != nil,
              let element = UIAccessibility.focusedElement(using: .notificationVoiceOver) as? NSObject
        else { return false }
        let controller = Self.owningController(of: view)
        let host = Self.hostView(of: element)
        let location = PublicationRefreshFocus.Location(
            pageOnScreen: pageOnScreen,
            pageCovered: controller.map(Self.isCovered) ?? false,
            pageFrame: UIAccessibility.convertToScreenCoordinates(view.bounds, in: view),
            focusedFrame: element.accessibilityFrame,
            focusedInPageHierarchy: host.flatMap { host in
                controller.map { host.isDescendant(of: $0.view) }
            }
        )
        return location.isInsidePage
        #else
        return false
        #endif
    }

    #if canImport(UIKit)
    /// The page's view controller (the hosting controller whose view contains the probe).
    ///
    /// - Parameter view: The probe view.
    /// - Returns: The nearest view controller in the responder chain.
    private static func owningController(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    /// The view that hosts an accessibility element (the element itself for UIKit views,
    /// the hosting view for SwiftUI elements).
    ///
    /// - Parameter element: The focused element.
    /// - Returns: The nearest `UIView` up its accessibility containers, if any.
    private static func hostView(of element: NSObject) -> UIView? {
        // `accessibilityContainer` is not exposed on NSObject in Swift; SwiftUI's
        // elements and UIAccessibilityElement implement it.
        let containerSelector = NSSelectorFromString("accessibilityContainer")
        var current: Any? = element
        for _ in 0..<64 {
            if let view = current as? UIView { return view }
            guard let object = current as? NSObject, object.responds(to: containerSelector) else { return nil }
            current = object.perform(containerSelector)?.takeUnretainedValue()
        }
        return nil
    }

    /// Whether a sheet, popover or alert is presented over the page's view controller.
    ///
    /// - Parameter controller: The page's view controller.
    /// - Returns: True when the topmost presented controller is not one of its ancestors.
    private static func isCovered(_ controller: UIViewController) -> Bool {
        guard let root = controller.viewIfLoaded?.window?.rootViewController else { return false }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        guard top !== root else { return false }
        var ancestor: UIViewController? = controller
        while let current = ancestor {
            if current === top { return false }
            ancestor = current.parent
        }
        return true
    }
    #endif
}

// MARK: - Probe view

/// The probe's view behind a page: draws nothing, takes no touches, hidden from VoiceOver.
struct PublicationFocusProbeView: View {
    let probe: PublicationFocusProbe

    var body: some View {
        #if canImport(UIKit)
        PublicationFocusProbeRepresentable(probe: probe)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #else
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #endif
    }
}

#if canImport(UIKit)
/// Hands the probe its `UIView`.
private struct PublicationFocusProbeRepresentable: UIViewRepresentable {
    let probe: PublicationFocusProbe

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.backgroundColor = .clear
        probe.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        probe.view = view
    }
}
#endif
