import SwiftUI

// MARK: - Timing

/// Timing for the app-wide "new content fades in as it loads" rule, ported from the web.
///
/// The web wraps freshly loaded page content in a `fadeInUp` CSS animation
/// (`styles/animations.css`: opacity 0 → 1 while rising 12 px, `FADE_DURATION` 400 ms,
/// `ease-out`), and staggers list items by `STAGGER_INTERVAL` (125 ms) as
/// `staggerDelay(index) = (index + 1) × 125 ms` (`packages/ui-utils/src/stagger.ts`,
/// `packages/theme/src/animation.ts`); the same values are used on Android and Windows.
/// Items past the first screenful (`estimateVisibleCount`) do not stagger: inside a
/// page's ``FestivalFadeInScope`` they fade in together with the last staggered item
/// (web `PaginatedLeaderboard` `staggerDelay(...) ?? 0`), and without one they appear
/// immediately. Scrolling during the first load rushes every fade that has not started
/// (web `useStaggerRush`); see ``FestivalFadeInScope``.
public enum FestivalFadeIn {
    /// Length of one fade (web `FADE_DURATION`, 400 ms).
    public static let duration: TimeInterval = 0.4

    /// Delay between consecutive staggered items (web `STAGGER_INTERVAL`, 125 ms).
    public static let staggerInterval: TimeInterval = 0.125

    /// Distance content rises while fading (web `fadeInUp` `translateY(12px)`).
    public static let riseDistance: CGFloat = 12

    /// Items at or beyond this index do not stagger (web `estimateVisibleCount`, roughly
    /// one iPhone screen of cards or rows).
    public static let maxStaggeredItems = 8

    /// CSS `ease-out` is `cubic-bezier(0, 0, 0.58, 1)`.
    public static let animation: Animation = .timingCurve(0, 0, 0.58, 1, duration: duration)

    /// Start delay for the item at `index` in a staggered list.
    ///
    /// - Parameters:
    ///   - index: Zero-based position in render order.
    ///   - maxStaggered: Items at or beyond this index do not stagger.
    /// - Returns: Seconds to wait before this item fades (`(index + 1) × 125 ms`, web
    ///   `staggerDelay`), or `nil` when it does not stagger (a negative index, or past
    ///   the first screenful).
    public static func delay(forIndex index: Int, maxStaggered: Int = maxStaggeredItems) -> TimeInterval? {
        guard index >= 0, index < maxStaggered else { return nil }
        return Double(index + 1) * staggerInterval
    }

    /// When the item at `index` of a staggered list starts fading.
    ///
    /// - Parameters:
    ///   - index: Zero-based position in render order; negative means "no fade" (a row
    ///     rebuilt after the first reveal, `FadeStagger.index(_:settled:)`).
    ///   - maxStaggered: Items at or beyond this index do not stagger.
    /// - Returns: ``FestivalFadeInStart/after(_:)`` with the web stagger delay,
    ///   ``FestivalFadeInStart/pastFirstScreen`` beyond the first screenful, or
    ///   ``FestivalFadeInStart/never``.
    public static func start(forIndex index: Int, maxStaggered: Int = maxStaggeredItems) -> FestivalFadeInStart {
        guard index >= 0 else { return .never }
        if let delay = delay(forIndex: index, maxStaggered: maxStaggered) { return .after(delay) }
        return .pastFirstScreen
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

    /// Time from the reveal until the item at `index` has finished its entrance: what the
    /// selected-row scroll waits for (web `navToPlayer` waits for the player's row).
    ///
    /// - Parameter index: Zero-based stagger position, or nil for a block fade (the whole
    ///   page fades at once).
    /// - Returns: Seconds until that item is fully shown; past the first screenful the
    ///   item ends with the last staggered one.
    public static func entranceEnd(forIndex index: Int?) -> TimeInterval {
        guard let index else { return duration }
        let position = min(max(index, 0), maxStaggeredItems - 1)
        return Double(position + 1) * staggerInterval + duration
    }
}

/// When one fading item starts, before a page scope adjusts it for scrolling.
public enum FestivalFadeInStart: Equatable, Sendable {
    /// Fade after this many seconds (0 for a block fade).
    case after(TimeInterval)
    /// A staggered item past the first screenful: inside an open page scope it fades with
    /// the last staggered item (or at once during a rush); without a scope it appears
    /// immediately.
    case pastFirstScreen
    /// No fade: the content is shown immediately.
    case never
}

// MARK: - Page scope

/// A page's first-load fade window and its scroll rush (web `useStaggerRush`; issues #30,
/// #323).
///
/// Lazy containers (`List`, `LazyVStack`, `LazyVGrid`) build a row only when it scrolls
/// near the viewport and rebuild it after it scrolls away and back, so a per-view fade
/// alone replays as the user scrolls, and rows past the first screen would appear
/// already opaque. A page installs one scope (``SwiftUICore/View/festivalFadeInScope(resetKey:)``
/// on its scroll content, or ``SwiftUICore/View/festivalScrollFadeInScope(_:resetKey:)``
/// on a `List` / `ScrollView`). While the first load is still fading, the first movement
/// of the content (a user drag, a Quick Links or section jump, the selected-row scroll)
/// **rushes** it: every fade that has not started yet, and every row built during the
/// next ``FestivalFadeIn/duration``, fades in at once, together. After that, or after a
/// scroll once every fade has finished, the scope closes and later rows appear without a
/// fade, so scrolling never replays an entrance (load-transition R5). A reset key re-arms
/// the scope for a new set of rows (a leaderboard page, a Songs reload, a new
/// Suggestions batch: web `resetRush`).
///
/// Deliberately not `@Observable`: rushing or closing must not re-render the page; each
/// fade reads the scope when it is built and waits on it.
@MainActor
public final class FestivalFadeInScope {
    /// Content movement (points) that counts as a scroll; absorbs sub-point layout jitter.
    public static let scrollThreshold: CGFloat = 4

    /// The clock, in seconds; injectable for tests.
    private let now: () -> TimeInterval

    /// The content's resting position, captured from the first report after (re)arming.
    private var restingOffset: CGFloat?
    /// The latest reported position, which becomes the resting one on a reset.
    private var lastOffset: CGFloat?
    /// When the first fade of this arm was scheduled: the stagger's time zero.
    private var openedAt: TimeInterval?
    /// When the last scheduled fade ends.
    private var activeUntil: TimeInterval = 0
    /// When a scroll rushed the pending fades.
    private var rushedAt: TimeInterval?
    /// Closed: later fades show content immediately until a reset.
    private var closed = false
    /// The reset key currently armed.
    private var armedKey: AnyHashable?
    /// Fades waiting for their stagger delay, released early by a rush.
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Whether the content has moved since the scope was (re)armed: a reader who scrolls
    /// before the selected-row scroll starts cancels it (web `userScrolledRef`).
    public private(set) var hasScrolled = false

    /// Creates an open scope.
    ///
    /// - Parameter now: The clock in seconds (defaults to the system uptime).
    public init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    /// Whether fades on this page may still animate: not closed, and not past a rush.
    public var isOpen: Bool {
        guard !closed else { return false }
        if let rushedAt { return now() < rushedAt + FestivalFadeIn.duration }
        return true
    }

    /// Whether a scroll has rushed this arm's pending fades.
    public var isRushed: Bool { rushedAt != nil }

    /// Record the scroll content's current position; the first movement rushes the
    /// pending fades (or closes the scope once they have all finished).
    ///
    /// - Parameter offset: The content's position along the scroll axis (`minY` in the
    ///   scroll view's space, or the scroll view's content offset).
    public func noteContentOffset(_ offset: CGFloat) {
        guard offset.isFinite else { return }
        lastOffset = offset
        guard let restingOffset else {
            restingOffset = offset
            return
        }
        guard !hasScrolled, abs(offset - restingOffset) > Self.scrollThreshold else { return }
        hasScrolled = true
        rush()
    }

    /// Rush every pending fade (web `useStaggerRush`): fades waiting for their stagger
    /// start now, and rows built during the next ``FestivalFadeIn/duration`` fade with
    /// them. With nothing left to fade, the scope closes instead.
    public func rush() {
        guard !closed, rushedAt == nil else { return }
        let time = now()
        if waiters.isEmpty, time >= activeUntil {
            closed = true
        } else {
            rushedAt = time
        }
        releaseWaiters()
    }

    /// Close the window explicitly: later fades on this page show content immediately.
    public func close() {
        closed = true
        releaseWaiters()
    }

    /// Re-arm the scope for a new set of rows when `key` differs from the armed one.
    ///
    /// - Parameter key: The rows' identity (nil keeps a scope that is never reset).
    public func arm(for key: AnyHashable?) {
        guard key != armedKey else { return }
        armedKey = key
        reset()
    }

    /// Re-arm: the current position becomes the resting one and the window reopens.
    public func reset() {
        restingOffset = lastOffset
        openedAt = nil
        activeUntil = 0
        rushedAt = nil
        closed = false
        hasScrolled = false
        releaseWaiters()
    }

    /// Schedule one fade and return its start delay.
    ///
    /// - Parameter start: The item's unscoped start.
    /// - Returns: Seconds until the item fades (0 during a rush), or nil to show it
    ///   immediately (closed, past a rush, or ``FestivalFadeInStart/never``).
    public func scheduleFade(_ start: FestivalFadeInStart) -> TimeInterval? {
        guard start != .never, isOpen else { return nil }
        let time = now()
        let delay: TimeInterval
        if rushedAt != nil {
            delay = 0
        } else {
            let opened = openedAt ?? time
            openedAt = opened
            switch start {
            case let .after(seconds):
                delay = max(0, seconds)
            case .pastFirstScreen:
                let lastStaggered = Double(FestivalFadeIn.maxStaggeredItems) * FestivalFadeIn.staggerInterval
                delay = max(0, opened + lastStaggered - time)
            case .never:
                return nil
            }
        }
        activeUntil = max(activeUntil, time + delay + FestivalFadeIn.duration)
        return delay
    }

    /// Wait until a fade scheduled `delay` seconds out may start: the delay elapses, a
    /// scroll rushes the page, the scope resets or the waiting task is cancelled.
    ///
    /// - Parameter delay: The delay ``scheduleFade(_:)`` returned.
    public func waitToStart(after delay: TimeInterval) async {
        guard delay > 0, rushedAt == nil, !closed, !Task.isCancelled else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters[id] = continuation
                // Strong capture: the continuation must be resumed even if the page goes.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    self.release(id)
                }
            }
        } onCancel: {
            Task { @MainActor in self.release(id) }
        }
    }

    /// Resume one waiting fade, if it is still waiting.
    private func release(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }

    /// Resume every waiting fade.
    private func releaseWaiters() {
        let pending = waiters
        waiters = [:]
        for continuation in pending.values { continuation.resume() }
    }
}

/// Installs a ``FestivalFadeInScope`` on a page's scroll content and feeds it the content's
/// position in its scroll view.
struct FestivalFadeInScopeModifier: ViewModifier {
    /// A page-owned scope (the page reads `hasScrolled`), else nil for an own one.
    let provided: FestivalFadeInScope?
    /// The rows' identity; a change re-arms the scope.
    let resetKey: AnyHashable?
    @State private var owned = FestivalFadeInScope()

    func body(content: Content) -> some View {
        let scope = provided ?? owned
        // Re-armed while the body is built, before new rows' `onAppear` schedule fades.
        let _ = scope.arm(for: resetKey)
        content
            .environment(\.festivalFadeInScope, scope)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .scrollView).minY
            } action: { offset in
                scope.noteContentOffset(offset)
            }
    }
}

/// Installs a ``FestivalFadeInScope`` on a `List` or `ScrollView` itself, fed from the
/// scroll view's offset (``SwiftUI/View/onScrollEdgeReading(legacy:_:action:)``), for
/// pages whose rows have no single content view to measure.
struct FestivalScrollFadeInScopeModifier: ViewModifier {
    let provided: FestivalFadeInScope?
    let resetKey: AnyHashable?
    @State private var owned = FestivalFadeInScope()

    func body(content: Content) -> some View {
        let scope = provided ?? owned
        let _ = scope.arm(for: resetKey)
        content
            .environment(\.festivalFadeInScope, scope)
            .onScrollEdgeReading(\.offset) { offset in
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

    /// The enclosing page's fade window, or nil outside a scoped page (fades always play
    /// on their own schedule).
    @Entry public var festivalFadeInScope: FestivalFadeInScope? = nil
}

// MARK: - Modifier

/// Hides content until it is loaded, then fades it in with the web's `fadeInUp` motion.
struct FestivalFadeInModifier: ViewModifier {
    /// Whether the content's data is ready.
    let isLoaded: Bool
    /// When the fade starts, before the page scope adjusts it.
    let start: FestivalFadeInStart

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.festivalFadeInEnabled) private var fadeEnabled
    @Environment(\.festivalFadeInScope) private var scope
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @State private var revealed = false
    /// A staggered fade waiting on its page scope (a scroll can start it early).
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        let visible = revealed || (isLoaded && !motionAllowed)
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : FestivalFadeIn.riseDistance)
            .allowsHitTesting(visible)
            .accessibilityHidden(while: !visible)
            .onAppear(perform: reveal)
            .onChange(of: isLoaded) { _, _ in reveal() }
            .onDisappear {
                pending?.cancel()
                pending = nil
            }
    }

    /// Reduce Motion (system or in-app) and the test override show content immediately.
    private var motionAllowed: Bool {
        fadeEnabled && !systemReduceMotion && !appReduceMotion
    }

    /// The start delay, or nil to show the content now: from the page scope when there is
    /// one, else the plain schedule (an item past the first screen shows at once).
    private func startDelay() -> TimeInterval? {
        guard motionAllowed else { return nil }
        if let scope { return scope.scheduleFade(start) }
        if case let .after(delay) = start { return delay }
        return nil
    }

    /// Reveal once per view lifetime; later reloads keep the content visible.
    private func reveal() {
        guard isLoaded, !revealed, pending == nil else { return }
        guard let delay = startDelay() else {
            revealed = true
            return
        }
        if delay > 0, let scope {
            // Wait on the scope rather than delaying the animation, so a scroll can start
            // this fade together with the rest (web `useStaggerRush`).
            pending = Task { @MainActor in
                await scope.waitToStart(after: delay)
                guard !Task.isCancelled else { return }
                pending = nil
                withAnimation(FestivalFadeIn.animation) { revealed = true }
            }
        } else {
            withAnimation(FestivalFadeIn.animation.delay(delay)) { revealed = true }
        }
    }
}

/// Hides content from assistive technologies while `hidden`, and otherwise leaves its
/// accessibility untouched.
///
/// `.accessibilityHidden(false)` is not neutral: on an ancestor it **un-hides** every
/// descendant marked `.accessibilityHidden(true)` (measured on macOS 26 hosting: a
/// Leaderboards card's decorative instrument icon read "Lead, image" before its
/// "Lead" heading). `accessibilityHidden(_:isEnabled:)` applies nothing when disabled.
/// Before iOS 18 / macOS 15 nothing is hidden: briefly exposing content that is still
/// fading in is milder than exposing every decorative image for good.
struct AccessibilityHiddenWhile: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.accessibilityHidden(true, isEnabled: hidden)
        } else {
            content
        }
    }
}

extension View {
    /// Hide from assistive technologies only while `hidden` is true; never un-hides
    /// descendants (``AccessibilityHiddenWhile``). Use instead of
    /// `.accessibilityHidden(someBool)`.
    ///
    /// - Parameter hidden: Whether to hide the content now.
    /// - Returns: The content, hidden while `hidden`.
    func accessibilityHidden(while hidden: Bool) -> some View {
        modifier(AccessibilityHiddenWhile(hidden: hidden))
    }
}

/// ``SwiftUI/View/festivalFadeIn(staggerIndex:)``: the full fade only for a row that
/// animates; any other row passes through untouched.
struct FestivalStaggeredRowFade: ViewModifier {
    let start: FestivalFadeInStart

    @Environment(\.festivalFadeInScope) private var scope

    func body(content: Content) -> some View {
        if animates {
            content.modifier(FestivalFadeInModifier(isLoaded: true, start: start))
        } else {
            content
        }
    }

    /// A staggered row always fades; a row past the first screen only while its page's
    /// scope is still open (it fades with the stagger tail or a rush), so rows built by
    /// scrolling later keep the plain path.
    private var animates: Bool {
        switch start {
        case .after: true
        case .pastFirstScreen: scope?.isOpen == true
        case .never: false
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
        modifier(FestivalFadeInModifier(isLoaded: isLoaded, start: .after(0)))
    }

    /// Staggered variant for lists and card stacks: item `index` starts
    /// `(index + 1) × 125 ms` after the reveal. Items past the first screenful fade with
    /// the last staggered item inside a page scope and appear immediately without one; a
    /// negative index never fades. A scroll inside a page scope rushes the pending items
    /// so they fade in together (``FestivalFadeInScope``).
    ///
    /// - Parameters:
    ///   - isLoaded: Whether the data this item shows is ready.
    ///   - index: Zero-based position in render order.
    /// - Returns: The content with a staggered `fadeInUp` reveal.
    public func festivalFadeIn(isLoaded: Bool, index: Int) -> some View {
        modifier(FestivalFadeInModifier(isLoaded: isLoaded, start: FestivalFadeIn.start(forIndex: index)))
    }

    /// Staggered fade for list rows that only exist once loaded: `staggerIndex` (zero-based
    /// render order) fades in like ``festivalFadeIn(isLoaded:index:)``; nil, a negative
    /// index, or an index past the first screenful once the page scope has closed, is the
    /// plain row with no fade machinery at all.
    ///
    /// The general modifier keeps per-row state, an `@AppStorage` observer and an
    /// `onAppear` state write that re-renders every row once more, even when it never
    /// animates. In the Songs `List` that was about a quarter of each row's build cost
    /// during fast scrolling (iPad scroll stress, Lane IPAD2), so rows built by
    /// scrolling take this path.
    ///
    /// - Parameter staggerIndex: The row's stagger position while the first load
    ///   settles (`FadeStagger.index(_:settled:)`), else nil.
    /// - Returns: The row, fading in only while the first load is still revealing.
    public func festivalFadeIn(staggerIndex: Int?) -> some View {
        modifier(FestivalStaggeredRowFade(start: staggerIndex.map { FestivalFadeIn.start(forIndex: $0) } ?? .never))
    }

    /// ``festivalFadeIn(isLoaded:)`` for content that is only built once its data exists
    /// (a `switch` over a load phase): it fades in on first appearance. Same as
    /// `festivalFadeIn(isLoaded: true)`; kept for Lane W4's Duo call sites.
    ///
    /// - Returns: The view, fading in when it first appears.
    public func festivalFadeInOnAppear() -> some View {
        festivalFadeIn(isLoaded: true)
    }

    /// Give every `festivalFadeIn` inside this content the page's first-load window: the
    /// first scroll while it is still fading rushes the pending fades so they finish
    /// together (web `useStaggerRush`), and once they are done later-built content
    /// appears without a fade (``FestivalFadeInScope``).
    ///
    /// Apply it to the content directly inside a page's `ScrollView` (it measures its own
    /// frame in the `.scrollView` coordinate space). For a `List`, or a page that reads
    /// the scope, use ``festivalScrollFadeInScope(_:resetKey:)``.
    ///
    /// - Parameter resetKey: The rows' identity; a change re-arms the window for a new set
    ///   of rows (web `resetRush`). Nil for content that loads once.
    /// - Returns: The content with a page-level fade window.
    public func festivalFadeInScope(resetKey: AnyHashable? = nil) -> some View {
        modifier(FestivalFadeInScopeModifier(provided: nil, resetKey: resetKey))
    }

    /// ``festivalFadeInScope(resetKey:)`` for a `List` or `ScrollView` itself, fed from
    /// its scroll offset: apply it to the scroll view, not to its content.
    ///
    /// - Parameters:
    ///   - scope: A page-owned scope (so the page can read ``FestivalFadeInScope/hasScrolled``),
    ///     or nil for one owned by the modifier.
    ///   - resetKey: The rows' identity; a change re-arms the window for a new set of rows.
    /// - Returns: The scroll view with a page-level fade window.
    public func festivalScrollFadeInScope(_ scope: FestivalFadeInScope? = nil, resetKey: AnyHashable? = nil) -> some View {
        modifier(FestivalScrollFadeInScopeModifier(provided: scope, resetKey: resetKey))
    }
}
