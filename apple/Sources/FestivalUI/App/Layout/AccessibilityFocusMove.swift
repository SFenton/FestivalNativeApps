import SwiftUI
import Observation
#if os(iOS)
import UIKit
#endif

// MARK: - Focus requests

/// Where assistive-technology focus should go after a shell transition
/// (`.agents/testing/apple/voiceover.md`): the trailing pane's title when an on-demand
/// split opens, the flyout's title when it opens, the flyout button when it closes.
/// The selected row's return on close is SwiftUI focus (``SwiftUI/View/listDetailSelectable(_:)``).
///
/// HIG VoiceOver: "Inform VoiceOver of visible content or layout changes
/// (`AccessibilityNotification`)". Each move answers the person's own action (opening
/// or closing), never an unprompted change (HIG Focus and selection: "Avoid changing
/// focus without people's interaction").
enum AccessibilityFocusTarget: Equatable, Sendable {
    /// The top-most heading inside the anchor's own frame (a pane's or panel's title).
    case topHeading
    /// The element with this accessibility identifier, anywhere in the anchor's window;
    /// else the element with `fallbackLabel` (the iPhone Duo rail's overflow "More" button
    /// when the identified item moved into it).
    case identifier(String, fallbackLabel: String? = nil)
}

/// One request: a new `token` asks again for the same target.
struct AccessibilityFocusRequest: Equatable, Sendable {
    let target: AccessibilityFocusTarget
    /// Whether the change is a new "screen" (a pane or panel appeared) or a layout change.
    var screenChanged = true
    let token: Int
}

/// Pure choice of the element a request lands on, so the rule is unit-tested without
/// UIKit: the top-most heading (then leading-most) whose frame lies inside the region.
enum AccessibilityFocusChoice {
    /// A candidate element as the walker read it.
    struct Candidate: Equatable {
        let label: String
        let identifier: String
        let frame: CGRect
        let isHeading: Bool
    }

    /// The candidate a `.topHeading` request lands on.
    ///
    /// - Parameters:
    ///   - candidates: Elements of the window, in any order.
    ///   - region: The anchor's frame (screen coordinates).
    /// - Returns: The index of the top-most, then leading-most, heading whose centre lies
    ///   in `region` (a named heading of zero size never counts), or nil.
    static func topHeading(_ candidates: [Candidate], in region: CGRect) -> Int? {
        candidates.indices
            .filter { index in
                let item = candidates[index]
                return item.isHeading && !item.label.isEmpty && item.frame.width > 0 && item.frame.height > 0
                    && region.contains(CGPoint(x: item.frame.midX, y: item.frame.midY))
            }
            .min { lhs, rhs in
                let a = candidates[lhs].frame, b = candidates[rhs].frame
                return abs(a.minY - b.minY) > 1 ? a.minY < b.minY : a.minX < b.minX
            }
    }
}

// MARK: - Debug trace

/// Debug-only record of the last focus move (`FST_DEBUG_A11Y_FOCUS_TRACE=1`): an XCUITest
/// cannot read VoiceOver focus, so the shell shows the last target as a tiny element
/// (`fst.nav.a11y-focus`) the iPad journeys read ("heading: uwphe", "row: rivalDetail:…").
@MainActor @Observable
final class AccessibilityFocusTrace {
    static let shared = AccessibilityFocusTrace()

    /// Whether moves are traced (and the walker runs without assistive technology).
    static let isEnabled: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["FST_DEBUG_A11Y_FOCUS_TRACE"] == "1"
        #else
        false
        #endif
    }()

    /// The last move, `"<kind>: <label>"`.
    private(set) var last = ""

    /// Record a move when tracing.
    ///
    /// - Parameter entry: `"<kind>: <label>"`.
    func record(_ entry: String) {
        if Self.isEnabled { last = entry }
    }
}

/// The trace element itself (Debug, `FST_DEBUG_A11Y_FOCUS_TRACE=1`): 1 pt, nearly clear,
/// so it never changes a capture, but present in the element tree.
struct AccessibilityFocusTraceView: View {
    var body: some View {
        #if DEBUG
        if AccessibilityFocusTrace.isEnabled {
            Text(AccessibilityFocusTrace.shared.last.isEmpty ? "none" : AccessibilityFocusTrace.shared.last)
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.02)
                .allowsHitTesting(false)
                .accessibilityLabel(AccessibilityFocusTrace.shared.last.isEmpty ? "none" : AccessibilityFocusTrace.shared.last)
                .accessibilityIdentifier("fst.nav.a11y-focus")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        #endif
    }
}

// MARK: - Anchor

extension View {
    /// Move assistive-technology focus when `request` changes (iOS; a no-op on macOS).
    ///
    /// The anchor fills the modified view, so a `.topHeading` request searches exactly
    /// its frame. The move waits out the presentation (0.5 s) and runs only while an
    /// assistive technology is on, or when traced in Debug.
    ///
    /// - Parameter request: The latest request, or nil.
    /// - Returns: The view with its focus anchor.
    func accessibilityFocusMove(_ request: AccessibilityFocusRequest?) -> some View {
        #if os(iOS)
        background { AccessibilityFocusAnchor(request: request).accessibilityHidden(true) }
        #else
        self
        #endif
    }
}

#if os(iOS)
/// UIKit side of ``SwiftUI/View/accessibilityFocusMove(_:)``: walks the window's
/// accessibility elements (SwiftUI's nodes and UIKit's bar titles alike) and posts
/// `screenChanged`/`layoutChanged` with the chosen element.
private struct AccessibilityFocusAnchor: UIViewRepresentable {
    let request: AccessibilityFocusRequest?

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        guard let request, request != view.handled else { return }
        view.handled = request
        view.schedule(request, attempt: 0)
    }

    @MainActor
    final class AnchorView: UIView {
        var handled: AccessibilityFocusRequest?

        /// Try now (after the presentation), then twice more while the target is missing.
        func schedule(_ request: AccessibilityFocusRequest, attempt: Int) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 500 : 400))
                guard let self, self.handled == request else { return }
                guard UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
                    || AccessibilityFocusTrace.isEnabled else { return }
                if !self.move(request) {
                    if attempt < 2 {
                        self.schedule(request, attempt: attempt + 1)
                    } else if let window = self.window {
                        // Debug trace: what the walker saw, to locate a missing target.
                        let names = Self.elements(in: window).compactMap { element -> String? in
                            let id = Self.identifier(of: element)
                            let label = element.accessibilityLabel ?? ""
                            return id.isEmpty ? nil : "\(id)=\(label.prefix(20))"
                        }
                        AccessibilityFocusTrace.shared.record("missing: \(names.prefix(40).joined(separator: "; "))")
                    }
                }
            }
        }

        /// Post the notification for the request's element.
        ///
        /// - Returns: False when no element matched yet.
        @discardableResult
        func move(_ request: AccessibilityFocusRequest) -> Bool {
            guard let window else { return false }
            let elements = Self.elements(in: window)
            let chosen: NSObject?
            switch request.target {
            case .topHeading:
                let region = UIAccessibility.convertToScreenCoordinates(bounds, in: self)
                let candidates = elements.map { element in
                    AccessibilityFocusChoice.Candidate(
                        label: element.accessibilityLabel ?? "",
                        identifier: Self.identifier(of: element),
                        frame: element.accessibilityFrame,
                        isHeading: element.accessibilityTraits.contains(.header)
                    )
                }
                chosen = AccessibilityFocusChoice.topHeading(candidates, in: region).map { elements[$0] }
            case .identifier(let id, let fallbackLabel):
                chosen = elements.first { Self.identifier(of: $0) == id }
                    ?? fallbackLabel.flatMap { label in
                        elements.first { $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.button) }
                    }
            }
            guard let chosen else { return false }
            UIAccessibility.post(notification: request.screenChanged ? .screenChanged : .layoutChanged, argument: chosen)
            let kind: String
            switch request.target {
            case .topHeading: kind = request.screenChanged ? "heading" : "heading-layout"
            case .identifier(let id, _): kind = id
            }
            AccessibilityFocusTrace.shared.record("\(kind): \(chosen.accessibilityLabel ?? "")")
            return true
        }

        /// An element's accessibility identifier. SwiftUI's nodes answer the selector
        /// without declaring `UIAccessibilityIdentification`, so a Swift cast misses them.
        static func identifier(of element: NSObject) -> String {
            if let identified = element as? UIAccessibilityIdentification {
                return identified.accessibilityIdentifier ?? ""
            }
            let selector = NSSelectorFromString("accessibilityIdentifier")
            guard element.responds(to: selector) else { return "" }
            return (element.value(forKey: "accessibilityIdentifier") as? String) ?? ""
        }

        /// Every accessibility element under `root`, depth first: views that are
        /// elements, and the elements containers vend (SwiftUI hosting views, bars).
        static func elements(in root: UIView) -> [NSObject] {
            var out: [NSObject] = []
            var seen = Set<ObjectIdentifier>()
            func visit(_ object: NSObject, depth: Int) {
                guard depth < 80, seen.insert(ObjectIdentifier(object)).inserted else { return }
                if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
                if object.accessibilityElementsHidden { return }
                if object.isAccessibilityElement { out.append(object) }
                if let vended = object.accessibilityElements as? [NSObject] {
                    for child in vended { visit(child, depth: depth + 1) }
                } else {
                    // The indexed container protocol (UIKit bars and lists vend this way).
                    let count = object.accessibilityElementCount()
                    if count > 0, count != NSNotFound {
                        for index in 0..<min(count, 500) {
                            if let child = object.accessibilityElement(at: index) as? NSObject {
                                visit(child, depth: depth + 1)
                            }
                        }
                    }
                }
                // Also the subviews: a SwiftUI hosting view vends its own nodes but not the
                // UIKit views it hosts (navigation bars, toolbar buttons).
                if let view = object as? UIView, !object.isAccessibilityElement {
                    for child in view.subviews { visit(child, depth: depth + 1) }
                }
            }
            visit(root, depth: 0)
            return out
        }
    }
}
#endif

// MARK: - Trace names

extension AppRoute {
    /// A short, stable name for the focus trace (the route's case and its key id).
    var focusTraceName: String {
        switch self {
        case .player(let accountId, _): "player:\(accountId)"
        case .rivalDetail(let rivalId, _, _): "rivalDetail:\(rivalId)"
        case .band(let bandId, _, _, _): "band:\(bandId)"
        case .songLeaderboard(let song, let instrument, _, _): "songLeaderboard:\(song.songId):\(instrument.rawValue)"
        case .playerHistory(let song, let instrument): "playerHistory:\(song.songId):\(instrument.rawValue)"
        case .licenses: "licenses"
        case .settingsTopic(let topic): "settingsTopic:\(topic.rawValue)"
        default: String(describing: self).prefix(40).description
        }
    }
}
