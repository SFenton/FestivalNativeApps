import SwiftUI

// MARK: - Timing

/// Timing for the app-wide "new content fades in as it loads" rule, ported from the web.
///
/// The web wraps freshly loaded page content in a `fadeInUp` CSS animation
/// (`styles/animations.css`: opacity 0 → 1 while rising 12 px, `FADE_DURATION` 400 ms,
/// `ease-out`), and staggers list items by `STAGGER_INTERVAL` (125 ms) as
/// `staggerDelay(index) = (index + 1) × 125 ms` (`packages/ui-utils/src/stagger.ts`,
/// `packages/theme/src/animation.ts`); the same values are used on Android and Windows.
/// Items past the first screenful (`estimateVisibleCount`) appear without animation so a
/// long list never makes the user wait for off-screen rows. Only content visible when a
/// page opens fades; see ``FestivalFadeInScope`` for lazily built sections.
public enum FestivalFadeIn {
    /// Length of one fade (web `FADE_DURATION`, 400 ms).
    public static let duration: TimeInterval = 0.4

    /// Delay between consecutive staggered items (web `STAGGER_INTERVAL`, 125 ms).
    public static let staggerInterval: TimeInterval = 0.125

    /// Distance content rises while fading (web `fadeInUp` `translateY(12px)`).
    public static let riseDistance: CGFloat = 12

    /// Staggered items beyond this index appear instantly (web `estimateVisibleCount`,
    /// roughly one iPhone screen of cards or rows).
    public static let maxStaggeredItems = 8

    /// CSS `ease-out` is `cubic-bezier(0, 0, 0.58, 1)`.
    public static let animation: Animation = .timingCurve(0, 0, 0.58, 1, duration: duration)

    /// Start delay for the item at `index` in a staggered list.
    ///
    /// - Parameters:
    ///   - index: Zero-based position in render order.
    ///   - maxStaggered: Items at or beyond this index skip the animation.
    /// - Returns: Seconds to wait before this item fades (`(index + 1) × 125 ms`, web
    ///   `staggerDelay`), or `nil` when it should appear immediately (a negative index, or
    ///   past the first screenful).
    public static func delay(forIndex index: Int, maxStaggered: Int = maxStaggeredItems) -> TimeInterval? {
        guard index >= 0, index < maxStaggered else { return nil }
        return Double(index + 1) * staggerInterval
    }

    /// Time until the last of `itemCount` staggered items has finished fading.
    ///
    /// - Parameters:
    ///   - itemCount: Number of items revealed together.
    ///   - maxStaggered: Same cap passed to ``delay(forIndex:maxStaggered:)``.
    /// - Returns: Seconds from the reveal until the page is fully settled; 0 for no items.
    public static func completionDelay(itemCount: Int, maxStaggered: Int = maxStaggeredItems) -> TimeInterval {
        guard itemCount > 0 else { return 0 }
        let animated = min(itemCount, maxStaggered)
        return Double(animated) * staggerInterval + duration
    }
}

// MARK: - Page scope

/// A page's "only content visible at page load fades in" window (issue #30).
///
/// Lazy containers (`LazyVStack`, `LazyVGrid`) build a row only when it scrolls near the
/// viewport and rebuild it after it scrolls away and back, so a per-view fade alone
/// replays as the user scrolls. A page installs one scope on its scroll content
/// (``SwiftUICore/View/festivalFadeInScope()``); the scope stays open until the content
/// first moves (a user drag, deceleration, a Quick Links jump or a deep-link scroll), and
/// any fade that has not started by then shows its content immediately. Content already
/// revealing when the scope closes finishes its fade.
///
/// Deliberately not `@Observable`: closing must not re-render the page; each fade reads
/// the flag when it is built or revealed.
@MainActor
public final class FestivalFadeInScope {
    /// Content movement (points) that counts as a scroll; absorbs sub-point layout jitter.
    public static let scrollThreshold: CGFloat = 4

    /// Whether fades on this page may still animate.
    public private(set) var isOpen = true

    /// The content's resting position, captured from the first geometry report.
    private var restingOffset: CGFloat?

    /// Creates an open scope.
    public init() {}

    /// Record the scroll content's current position and close once it has moved.
    ///
    /// - Parameter offset: The content's `minY` in its scroll view's coordinate space.
    public func noteContentOffset(_ offset: CGFloat) {
        guard isOpen, offset.isFinite else { return }
        guard let restingOffset else {
            restingOffset = offset
            return
        }
        if abs(offset - restingOffset) > Self.scrollThreshold { isOpen = false }
    }

    /// Close the window explicitly: later fades on this page show content immediately.
    public func close() {
        isOpen = false
    }
}

/// Installs a ``FestivalFadeInScope`` and feeds it the scroll content's position.
struct FestivalFadeInScopeModifier: ViewModifier {
    @State private var scope = FestivalFadeInScope()

    func body(content: Content) -> some View {
        content
            .environment(\.festivalFadeInScope, scope)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .scrollView).minY
            } action: { offset in
                scope.noteContentOffset(offset)
            }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// Whether ``SwiftUICore/View/festivalFadeIn(isLoaded:)`` animates. Defaults to `true`.
    ///
    /// Hosted snapshot tests set this to `false` so a capture never lands mid-fade.
    @Entry public var festivalFadeInEnabled: Bool = true

    /// The enclosing page's fade window, or nil outside a scoped page (fades always play).
    @Entry public var festivalFadeInScope: FestivalFadeInScope? = nil
}

// MARK: - Modifier

/// Hides content until it is loaded, then fades it in with the web's `fadeInUp` motion.
struct FestivalFadeInModifier: ViewModifier {
    /// Whether the content's data is ready.
    let isLoaded: Bool
    /// Start delay; `nil` reveals instantly (a staggered item past the first screen).
    let delay: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.festivalFadeInEnabled) private var fadeEnabled
    @Environment(\.festivalFadeInScope) private var scope
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @State private var revealed = false

    func body(content: Content) -> some View {
        let visible = revealed || (isLoaded && !animates)
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : FestivalFadeIn.riseDistance)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            .onAppear(perform: reveal)
            .onChange(of: isLoaded) { _, _ in reveal() }
    }

    /// Reduce Motion (system or in-app), the test override and a closed page scope (the
    /// page has scrolled since it loaded) show content immediately.
    private var animates: Bool {
        fadeEnabled && !systemReduceMotion && !appReduceMotion && delay != nil
            && scope?.isOpen != false
    }

    /// Reveal once per view lifetime; later reloads keep the content visible.
    private func reveal() {
        guard isLoaded, !revealed else { return }
        if animates, let delay {
            withAnimation(FestivalFadeIn.animation.delay(delay)) { revealed = true }
        } else {
            revealed = true
        }
    }
}

// MARK: - Public API

extension View {
    /// Fade this content in once it has loaded ("new content fades in as it loads").
    ///
    /// Apply it to the loaded content itself, not to a container that also shows the
    /// spinner: while `isLoaded` is false the content is invisible. The fade plays once per
    /// view lifetime (a revisit that keeps the view alive does not replay it) and is
    /// instant under Reduce Motion, the in-app Reduce Motion toggle, or
    /// `festivalFadeInEnabled == false`.
    ///
    /// - Parameter isLoaded: Whether the data this content shows is ready. Pass `true` for
    ///   content that only exists once loaded.
    /// - Returns: The content with the web's 400 ms `fadeInUp` reveal.
    public func festivalFadeIn(isLoaded: Bool) -> some View {
        modifier(FestivalFadeInModifier(isLoaded: isLoaded, delay: 0))
    }

    /// Staggered variant for lists and card stacks: item `index` starts
    /// `(index + 1) × 125 ms` after the reveal, and items past the first screenful appear
    /// immediately.
    ///
    /// - Parameters:
    ///   - isLoaded: Whether the data this item shows is ready.
    ///   - index: Zero-based position in render order.
    /// - Returns: The content with a staggered `fadeInUp` reveal.
    public func festivalFadeIn(isLoaded: Bool, index: Int) -> some View {
        modifier(FestivalFadeInModifier(isLoaded: isLoaded, delay: FestivalFadeIn.delay(forIndex: index)))
    }

    /// ``festivalFadeIn(isLoaded:)`` for content that is only built once its data exists
    /// (a `switch` over a load phase): it fades in on first appearance. Same as
    /// `festivalFadeIn(isLoaded: true)`; kept for Lane W4's Duo call sites.
    ///
    /// - Returns: The view, fading in when it first appears.
    public func festivalFadeInOnAppear() -> some View {
        festivalFadeIn(isLoaded: true)
    }

    /// Limit every `festivalFadeIn` inside this content to what is on screen at page
    /// load: once the content scrolls, later-built content appears without a fade.
    ///
    /// Apply it to the content directly inside a page's `ScrollView` (it measures its own
    /// frame in the `.scrollView` coordinate space). An appending feed that should fade
    /// each newly loaded batch (Suggestions) must not use it.
    ///
    /// - Returns: The content with a page-level fade window.
    public func festivalFadeInScope() -> some View {
        modifier(FestivalFadeInScopeModifier())
    }
}
