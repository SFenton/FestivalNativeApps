import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Stage

/// What the feedback form's sending status says (issue #634): the upload, then the
/// service filing the issue on GitHub.
enum FeedbackSendingStage: Hashable, Sendable {
    /// The form's media are uploading (``FeedbackFormModel/Phase/submitting(_:)`` with
    /// attachments).
    case uploading
    /// The service has the report and is filing it (``FeedbackFormModel/Phase/filing``).
    case filing

    /// The status headline.
    ///
    /// - Parameter kind: Bug report or feature request.
    /// - Returns: "Uploading Media" or "Filing Issue"/"Filing Request".
    func title(for kind: FeedbackKind) -> String {
        switch self {
        case .uploading: "Uploading Media"
        case .filing: "Filing \(Self.noun(kind).capitalized)"
        }
    }

    /// The sentence under the headline; the upload shows its progress bar instead.
    ///
    /// - Parameter kind: Bug report or feature request.
    /// - Returns: The filing sentence, or nil while uploading.
    func subtitle(for kind: FeedbackKind) -> String? {
        switch self {
        case .uploading: nil
        case .filing:
            "We\u{2019}re filing your \(Self.noun(kind)). Please wait while we upload it."
        }
    }

    /// The spinner's spoken name, the same through both stages so assistive technology
    /// meets one busy indicator that never changes (pattern `load-transition` R2).
    ///
    /// - Parameter kind: Bug report or feature request.
    /// - Returns: "Sending your issue" or "Sending your request".
    static func busyLabel(for kind: FeedbackKind) -> String {
        "Sending your \(noun(kind))"
    }

    /// The stage a form phase shows. A report without media reads as filing from Submit
    /// (`modal-shell` R16, the agent decision Android and Windows share): nothing is
    /// uploading, so "Uploading Media" would be inaccurate and flash for a moment.
    ///
    /// - Parameters:
    ///   - phase: The form's phase.
    ///   - hasMedia: Whether the report carries attachments.
    /// - Returns: The target presentation: the form while editing or after a failure,
    ///   the stage while busy, or nil once filed (the sheet is closing, so it holds).
    static func target(
        for phase: FeedbackFormModel.Phase, hasMedia: Bool
    ) -> FeedbackSendingChoreography.Target? {
        switch phase {
        case .editing, .failed: .form
        case .submitting: .status(hasMedia ? .uploading : .filing)
        case .filing: .status(.filing)
        case .finished: nil
        }
    }

    private static func noun(_ kind: FeedbackKind) -> String {
        kind == .bug ? "issue" : "request"
    }
}

// MARK: - Choreography

/// The fades between the form and its sending status (issue #634, owner-approved variant
/// of `load-transition`; `.agents/controls/feedback-form/spec.md`).
///
/// Submit fades the form out (300 ms, R3 content-out), then the spinner, title and
/// subtitle in (150 ms, R3 spinner-in). A new stage fades only the title and subtitle out
/// and the new ones in (150 ms each, web `QUICK_FADE_MS`, as accordions swap content);
/// the spinner stays. Returning to the form reverses the first sequence. Under Reduce
/// Motion every change applies at once (R6). A new target replans from wherever the
/// sequence is, like ``AccordionChoreography``.
enum FeedbackSendingChoreography {
    /// The form's fade out (`load-transition` R3 content-out).
    static let contentOutDuration: TimeInterval = 0.3
    /// The status's fade in (`load-transition` R3 spinner-in).
    static let statusInDuration: TimeInterval = 0.15
    /// Each half of a title and subtitle swap (web `QUICK_FADE_MS`).
    static let textFadeDuration: TimeInterval = 0.15
    /// The status's fade out when the form comes back.
    static let statusOutDuration: TimeInterval = 0.15
    /// The form's fade back in.
    static let contentInDuration: TimeInterval = 0.3

    /// What the sheet should end up showing.
    enum Target: Equatable, Sendable {
        /// The editable form.
        case form
        /// The sending status at a stage.
        case status(FeedbackSendingStage)
    }

    /// What the sheet shows now (possibly mid-sequence).
    struct Presentation: Equatable, Sendable {
        /// The form (and any photo pane beside it) is opaque.
        var showsForm: Bool
        /// The status (spinner and text) is opaque.
        var showsStatus: Bool
        /// The stage whose text is laid out; nil while the status isn't mounted.
        var stage: FeedbackSendingStage?
        /// The stage's title and subtitle are opaque.
        var showsText: Bool

        /// The form stays mounted while it shows or fades, and leaves once the opaque status
        /// covers it: iOS keeps a transparent `Form`'s rows in the accessibility tree even
        /// under `accessibilityHidden`. Its input lives in the model, so a failure that
        /// brings the form back loses nothing.
        var mountsForm: Bool { showsForm || !showsStatus }

        /// The form, with no status mounted.
        static let editing = Presentation(
            showsForm: true, showsStatus: false, stage: nil, showsText: false
        )

        /// The settled status at a stage.
        ///
        /// - Parameter stage: The stage shown.
        /// - Returns: The resting presentation.
        static func status(_ stage: FeedbackSendingStage) -> Presentation {
            Presentation(showsForm: false, showsStatus: true, stage: stage, showsText: true)
        }
    }

    /// One change and how long to wait after the previous one before applying it.
    struct Step: Equatable, Sendable {
        /// Wait after the previous step (its fade's length).
        let delay: TimeInterval
        /// The fade's length, or nil to apply at once.
        let fade: TimeInterval?
        /// The presentation after this step.
        let presentation: Presentation
        /// Whether this step reveals a stage's title, which is then announced.
        let announces: Bool
    }

    /// The steps from where the sheet is to a target.
    ///
    /// - Parameters:
    ///   - presentation: What the sheet shows now.
    ///   - target: What it should show.
    ///   - reduceMotion: System or in-app Reduce Motion: one immediate step.
    /// - Returns: Steps in order; empty when it is already there.
    static func plan(
        from presentation: Presentation, to target: Target, reduceMotion: Bool
    ) -> [Step] {
        var steps: [Step] = []
        var current = presentation
        var delay: TimeInterval = 0
        func add(_ fade: TimeInterval, announces: Bool = false, _ change: (inout Presentation) -> Void) {
            var next = current
            change(&next)
            guard next != current else { return }
            steps.append(Step(delay: delay, fade: fade, presentation: next, announces: announces))
            current = next
            delay = fade
        }
        switch target {
        case .form:
            if current.showsStatus { add(statusOutDuration) { $0.showsStatus = false } }
            add(contentInDuration) { $0 = .editing }
        case let .status(stage):
            if current.showsForm {
                add(contentOutDuration) {
                    $0.showsForm = false
                    // Mount the new stage while the status is still transparent.
                    if !$0.showsStatus { $0.stage = stage; $0.showsText = true }
                }
            }
            if !current.showsStatus {
                add(statusInDuration, announces: true) { $0 = .status(stage) }
            } else if current.stage != stage || !current.showsText {
                if current.showsText { add(textFadeDuration) { $0.showsText = false } }
                add(textFadeDuration, announces: true) { $0.stage = stage; $0.showsText = true }
            }
        }
        guard reduceMotion, let last = steps.last else { return steps }
        return [Step(
            delay: 0, fade: nil, presentation: last.presentation,
            announces: steps.contains(where: \.announces)
        )]
    }

    /// Apply a plan: zero-delay leading steps at once, the rest after their delays.
    /// Cancel the returned task to interrupt.
    ///
    /// - Parameters:
    ///   - steps: From ``plan(from:to:reduceMotion:)``.
    ///   - apply: Applies one step's presentation (inside its animation) and announces it.
    /// - Returns: The task running the delayed steps, or nil when none remain.
    @MainActor
    static func run(
        _ steps: [Step], apply: @escaping @MainActor (Step) -> Void
    ) -> Task<Void, Never>? {
        var remaining = steps[...]
        while let step = remaining.first, step.delay == 0 {
            withAnimation(animation(step.fade)) { apply(step) }
            remaining = remaining.dropFirst()
        }
        guard !remaining.isEmpty else { return nil }
        let delayed = Array(remaining)
        return Task { @MainActor in
            for step in delayed {
                try? await Task.sleep(for: .seconds(step.delay))
                guard !Task.isCancelled else { return }
                withAnimation(animation(step.fade)) { apply(step) }
            }
        }
    }

    /// The web CSS `ease` curve the load transitions use (`load-transition` R3).
    ///
    /// - Parameter fade: The fade's length, or nil.
    /// - Returns: The curve, or nil for an immediate change.
    static func animation(_ fade: TimeInterval?) -> Animation? {
        fade.map { .timingCurve(0.25, 0.1, 0.25, 1, duration: $0) }
    }
}

// MARK: - Status view

/// The sending status centred in the feedback sheet (issue #634): the app's spinner, then
/// the stage's title over the upload's progress bar and Stop Sending, or over the filing
/// sentence. Owner-chosen: HIG Progress indicators' "Avoid labeling a spinner" (should)
/// yields to the owner's title and subtitle; the bar follows "When possible, use a
/// determinate indicator" and Stop Sending "When it's feasible, let people halt processing".
///
/// Every stage's text is laid out at once and only the shown one is opaque, so the spinner
/// above them never moves or restarts when the text swaps.
struct FeedbackSendingStatusView: View {
    let kind: FeedbackKind
    let presentation: FeedbackSendingChoreography.Presentation
    /// Upload progress, 0...1.
    let progress: Double
    let onStop: () -> Void

    /// Space between the spinner and the stage text.
    static let spinnerSpacing: CGFloat = 20
    /// Widest the progress bar grows on a wide sheet.
    static let barMaxWidth: CGFloat = 320

    var body: some View {
        FestivalCentredFill(padding: FestivalEmptyState<EmptyView>.fillPadding) {
            VStack(spacing: Self.spinnerSpacing) {
                FestivalLoadingView(
                    accessibilityLabel: FeedbackSendingStage.busyLabel(for: kind)
                )
                .controlSize(.large)
                .accessibilityIdentifier("fst.settings.feedback.busy")
                ZStack(alignment: .top) {
                    stageSlot(.uploading)
                    stageSlot(.filing)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fst.settings.feedback.status")
        }
    }

    /// One stage's text. The other stage keeps its layout space with `.hidden()`, which
    /// (unlike `accessibilityHidden` under zero opacity, which iOS still exposed) takes it
    /// out of the accessibility tree, so the spinner never moves between stages.
    @ViewBuilder
    private func stageSlot(_ stage: FeedbackSendingStage) -> some View {
        if presentation.stage == stage {
            stageText(stage)
        } else {
            stageText(stage).hidden()
        }
    }

    private func stageText(_ stage: FeedbackSendingStage) -> some View {
        let visible = presentation.showsText && presentation.stage == stage
        return VStack(spacing: FestivalEmptyState<EmptyView>.spacing) {
            FestivalStateTitle(stage.title(for: kind))
                .accessibilityIdentifier("fst.settings.feedback.status.title")
            if let subtitle = stage.subtitle(for: kind) {
                FestivalStateSubtitle(subtitle)
                    .accessibilityIdentifier("fst.settings.feedback.status.subtitle")
            } else {
                ProgressView(value: min(max(progress, 0), 1))
                    .frame(maxWidth: Self.barMaxWidth)
                    .accessibilityLabel("Upload progress")
                    .accessibilityIdentifier("fst.settings.feedback.progress")
                stopButton
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
    }

    /// Stop Sending at the platform's default control size (HIG Accessibility: "Strive for
    /// the platform's recommended minimum control size", 44×44 pt on iOS and iPadOS,
    /// 28×28 pt on macOS), as `ServiceStatusView`'s Retry.
    @ViewBuilder
    private var stopButton: some View {
        #if os(macOS)
        // A large push button: the regular one is 24 pt tall, under the 28 pt default.
        Button("Stop Sending", role: .destructive, action: onStop)
            .controlSize(.large)
            .accessibilityIdentifier("fst.settings.feedback.stop")
        #else
        Button(role: .destructive, action: onStop) {
            Text("Stop Sending")
                .foregroundStyle(FestivalSheetActionColor.destructive)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("fst.settings.feedback.stop")
        #endif
    }
}
