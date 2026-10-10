import SwiftUI

// MARK: - Choreography

/// The one accordion motion every expand/collapse in the app shares (pattern `accordion`,
/// issue #561): opening grows the container first and then fades its content in; closing
/// fades the content out first and then collapses the container.
///
/// Timings are the web's `QUICK_FADE_MS` (150 ms) for each half, the same height duration
/// as the web `Accordion` and, together, the web `CollapseOnExit` 300 ms exit. Under Reduce
/// Motion the container opens and closes without animation and only the content fade
/// remains (HIG Accessibility: "replacing axis transitions with fades").
///
/// Every step is planned from the current phase, so a new tap mid-sequence reverses from
/// where the motion is instead of waiting for it to finish (HIG Motion: "let people cancel
/// animations rather than wait for completion").
enum AccordionChoreography {
    /// Container grow/shrink duration (web `QUICK_FADE_MS`).
    static let resizeDuration: TimeInterval = 0.15
    /// Content fade duration (web `QUICK_FADE_MS`).
    static let fadeDuration: TimeInterval = 0.15
    /// Under Reduce Motion, the pause between opening the container without animation and
    /// starting the fade, so the fade starts from transparent content already in place.
    static let reducedMotionSettle: TimeInterval = 0.02

    /// Where an accordion is: whether its container is open and whether its content shows.
    struct Phase: Equatable, Sendable {
        /// The container is open (rows inserted, disclosure expanded).
        var isOpen: Bool
        /// The content is opaque.
        var showsContent: Bool

        /// A settled phase.
        ///
        /// - Parameter expanded: Fully open with content shown, or fully closed.
        /// - Returns: The resting phase.
        static func settled(_ expanded: Bool) -> Phase {
            Phase(isOpen: expanded, showsContent: expanded)
        }

        /// The phase after one change.
        ///
        /// - Parameter change: The step being applied.
        /// - Returns: The new phase.
        func applying(_ change: Change) -> Phase {
            var next = self
            switch change {
            case .open: next.isOpen = true
            case .close: next.isOpen = false; next.showsContent = false
            case .showContent: next.showsContent = true
            case .hideContent: next.showsContent = false
            }
            return next
        }
    }

    /// One state change of the sequence.
    enum Change: Equatable, Sendable {
        case open, close, showContent, hideContent
    }

    /// A change and how long to wait after the previous one before applying it.
    struct Step: Equatable, Sendable {
        let delay: TimeInterval
        let change: Change
    }

    /// The steps that move an accordion from its current phase to open or closed.
    ///
    /// - Parameters:
    ///   - expanded: Whether the person asked for it open.
    ///   - phase: Where it is now (possibly mid-sequence).
    ///   - reduceMotion: System or in-app Reduce Motion.
    /// - Returns: Steps in order; empty when it is already there.
    static func plan(expanded: Bool, from phase: Phase, reduceMotion: Bool) -> [Step] {
        if expanded {
            if !phase.isOpen {
                return [
                    Step(delay: 0, change: .open),
                    Step(delay: reduceMotion ? reducedMotionSettle : resizeDuration, change: .showContent),
                ]
            }
            return phase.showsContent ? [] : [Step(delay: 0, change: .showContent)]
        }
        if phase.showsContent {
            return [Step(delay: 0, change: .hideContent), Step(delay: fadeDuration, change: .close)]
        }
        return phase.isOpen ? [Step(delay: 0, change: .close)] : []
    }

    /// The animation for one change.
    ///
    /// - Parameters:
    ///   - change: The step being applied.
    ///   - reduceMotion: System or in-app Reduce Motion.
    /// - Returns: An ease-in-out curve, or nil for the container under Reduce Motion.
    static func animation(for change: Change, reduceMotion: Bool) -> Animation? {
        switch change {
        case .open, .close: reduceMotion ? nil : .easeInOut(duration: resizeDuration)
        case .showContent, .hideContent: .easeInOut(duration: fadeDuration)
        }
    }

    /// Apply a plan: zero-delay leading steps at once (so the tap answers in the same
    /// frame), the rest after their delays. Cancel the returned task to interrupt.
    ///
    /// - Parameters:
    ///   - steps: From ``plan(expanded:from:reduceMotion:)``.
    ///   - reduceMotion: System or in-app Reduce Motion.
    ///   - apply: Applies one change to the view's state.
    /// - Returns: The task running the delayed steps, or nil when none remain.
    @MainActor
    static func run(
        _ steps: [Step], reduceMotion: Bool, apply: @escaping @MainActor (Change) -> Void
    ) -> Task<Void, Never>? {
        var remaining = steps[...]
        while let step = remaining.first, step.delay == 0 {
            withAnimation(animation(for: step.change, reduceMotion: reduceMotion)) { apply(step.change) }
            remaining = remaining.dropFirst()
        }
        guard !remaining.isEmpty else { return nil }
        let delayed = Array(remaining)
        return Task { @MainActor in
            for step in delayed {
                try? await Task.sleep(for: .seconds(step.delay))
                guard !Task.isCancelled else { return }
                withAnimation(animation(for: step.change, reduceMotion: reduceMotion)) { apply(step.change) }
            }
        }
    }
}

// MARK: - State

/// One accordion's state, owned by the screen (`@State`) so the revealed content, a
/// header shown while open and the driver all read the same phase.
///
/// `target` is what the person asked for; `shown` is the value whose content is laid out
/// (nil while the container is closed) and `showsContent` whether that content is opaque.
/// For a plain open/closed accordion use `Value == Bool` (``init(expanded:)``).
struct FestivalAccordionState<Value: Equatable>: Equatable {
    /// The value the person asked for; nil means closed.
    private(set) var target: Value?
    /// The value whose content is laid out; nil while the container is closed.
    private(set) var shown: Value?
    /// Whether the laid-out content is opaque.
    private(set) var showsContent: Bool

    /// A settled state.
    ///
    /// - Parameter value: Open on this value, or closed when nil.
    init(_ value: Value?) {
        target = value
        shown = value
        showsContent = value != nil
    }

    /// Where the container and content are now.
    var phase: AccordionChoreography.Phase {
        AccordionChoreography.Phase(isOpen: shown != nil, showsContent: showsContent)
    }

    /// Ask for a new value. Swapping between two values while open changes the content in
    /// place; opening or closing is left to the planned steps.
    ///
    /// - Parameter value: The new target.
    mutating func request(_ value: Value?) {
        target = value
        if let value, shown != nil { shown = value }
    }

    /// Apply one planned change.
    ///
    /// - Parameter change: The step.
    mutating func apply(_ change: AccordionChoreography.Change) {
        switch change {
        case .open: shown = target
        case .close: shown = nil; showsContent = false
        case .showContent: showsContent = true
        case .hideContent: showsContent = false
        }
    }

    /// Ask for a value and start the shared sequence.
    ///
    /// - Parameters:
    ///   - state: The screen's accordion state.
    ///   - value: The new target (nil closes).
    ///   - reduceMotion: System or in-app Reduce Motion.
    ///   - sequence: The running sequence; cancelled and replaced.
    @MainActor
    static func move(
        _ state: Binding<FestivalAccordionState>, to value: Value?, reduceMotion: Bool,
        sequence: Binding<Task<Void, Never>?>
    ) {
        sequence.wrappedValue?.cancel()
        state.wrappedValue.request(value)
        let steps = AccordionChoreography.plan(
            expanded: value != nil, from: state.wrappedValue.phase, reduceMotion: reduceMotion
        )
        sequence.wrappedValue = AccordionChoreography.run(steps, reduceMotion: reduceMotion) { change in
            state.wrappedValue.apply(change)
        }
    }
}

extension FestivalAccordionState where Value == Bool {
    /// A settled open/closed accordion.
    ///
    /// - Parameter expanded: Starts open.
    init(expanded: Bool) {
        self.init(expanded ? true : nil)
    }

    /// Whether the person asked for it open (the disclosure state VoiceOver reports).
    var isExpanded: Bool { target != nil }
}

// MARK: - Driver

/// Follows a value with the shared accordion sequence (``View/festivalAccordion(_:follows:)``).
private struct FestivalAccordionDriver<Value: Equatable>: ViewModifier {
    @Binding var state: FestivalAccordionState<Value>
    let value: Value?
    @State private var sequence: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                // A value read from storage after the state was created settles without motion.
                if state.target != value { state = FestivalAccordionState(value) }
            }
            .onChange(of: value) { _, target in
                FestivalAccordionState.move(
                    $state, to: target, reduceMotion: systemReduceMotion || appReduceMotion,
                    sequence: $sequence
                )
            }
            .onDisappear {
                sequence?.cancel()
                state = FestivalAccordionState(value)
            }
    }
}

extension View {
    /// Drive an accordion from a value (an instrument chosen, a switch on): when it changes,
    /// the space opens and then the content fades in, or the content fades out and then
    /// the space closes (pattern `accordion`). Attach it to a view that is always present
    /// (the switch, the selector or the enclosing `Form`), never to the revealed content,
    /// and show that content with ``FestivalAccordionContent``.
    ///
    /// - Parameters:
    ///   - state: The screen's accordion state.
    ///   - value: The value to follow; nil closes.
    /// - Returns: The view, driving `state`.
    func festivalAccordion<Value: Equatable>(
        _ state: Binding<FestivalAccordionState<Value>>, follows value: Value?
    ) -> some View {
        modifier(FestivalAccordionDriver(state: state, value: value))
    }
}

// MARK: - Content

/// The content an accordion reveals: laid out while its container is open, transparent
/// (and hidden from VoiceOver) until it fades in. Works in a `Form`/`List` (each row of
/// the content becomes a list row), a ``FestivalGlassSection`` and stacks.
struct FestivalAccordionContent<Value: Equatable, Content: View>: View {
    private let state: FestivalAccordionState<Value>
    private let content: (Value) -> Content

    /// Show content for the shown value.
    ///
    /// - Parameters:
    ///   - state: The accordion's state.
    ///   - content: The content for the shown value.
    init(_ state: FestivalAccordionState<Value>, @ViewBuilder content: @escaping (Value) -> Content) {
        self.state = state
        self.content = content
    }

    var body: some View {
        if let shown = state.shown {
            content(shown)
                .opacity(state.showsContent ? 1 : 0)
                .accessibilityHidden(while: !state.showsContent)
        }
    }
}

extension FestivalAccordionContent where Value == Bool {
    /// Show content while an open/closed accordion is open.
    ///
    /// - Parameters:
    ///   - state: The accordion's state.
    ///   - content: The content.
    init(_ state: FestivalAccordionState<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(state) { _ in content() }
    }
}

// MARK: - Disclosure group

/// The system `DisclosureGroup` with the shared accordion motion (pattern `accordion`).
///
/// HIG Disclosure controls: iOS and iPadOS "provide disclosure controls through SwiftUI
/// `DisclosureGroup`", so this keeps the system control, its chevron and its expanded or
/// collapsed accessibility state, and only sequences the change: the group expands with
/// its rows transparent, then they fade in; closing fades them out, then the group
/// collapses. A tap mid-sequence reverses from where the motion is.
struct FestivalDisclosureGroup<Label: View, Content: View>: View {
    private let external: Binding<FestivalAccordionState<Bool>>?
    private let content: () -> Content
    private let label: () -> Label
    @State private var local: FestivalAccordionState<Bool>
    @State private var sequence: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    /// A disclosure group whose state the screen owns, e.g. to show header actions with
    /// ``FestivalAccordionContent`` while it is open.
    ///
    /// - Parameters:
    ///   - state: The screen's accordion state.
    ///   - content: Rows shown while open.
    ///   - label: The always-visible header.
    init(
        state: Binding<FestivalAccordionState<Bool>>, @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        external = state
        self.content = content
        self.label = label
        _local = State(initialValue: state.wrappedValue)
    }

    /// A disclosure group that keeps its own state.
    ///
    /// - Parameters:
    ///   - initiallyExpanded: Starting state (tests and snapshots).
    ///   - content: Rows shown while open.
    ///   - label: The always-visible header.
    init(
        initiallyExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        external = nil
        self.content = content
        self.label = label
        _local = State(initialValue: FestivalAccordionState(expanded: initiallyExpanded))
    }

    private var state: Binding<FestivalAccordionState<Bool>> { external ?? $local }

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { state.wrappedValue.shown != nil },
                // A tap always flips what the person last asked for, so tapping while a
                // close is still fading reopens it.
                set: { _ in
                    FestivalAccordionState.move(
                        state, to: state.wrappedValue.isExpanded ? nil : true,
                        reduceMotion: systemReduceMotion || appReduceMotion, sequence: $sequence
                    )
                }
            )
        ) {
            FestivalAccordionContent(state.wrappedValue) { content() }
        } label: {
            label()
        }
        .onDisappear {
            sequence?.cancel()
            state.wrappedValue = FestivalAccordionState(expanded: state.wrappedValue.isExpanded)
        }
    }
}
