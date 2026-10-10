import FestivalCore

// MARK: - Sent notice

/// The "Report Sent" / "Request Sent" alert's content for a delivered report.
///
/// Fixed client text, never server text (`.agents/controls/feedback-form/spec.md`).
struct FeedbackSentNotice: Equatable, Sendable {
    /// Bug report or feature request.
    let kind: FeedbackKind
    /// How the report ended.
    let outcome: FeedbackFormModel.Outcome

    /// "Report Sent" or "Request Sent".
    var title: String {
        kind == .bug ? "Report Sent" : "Request Sent"
    }

    /// The issue number (or the "received" text) plus any attachments the service skipped.
    var message: String {
        switch outcome {
        case let .filed(number, skipped):
            var text = number.map { "Thank you! It was filed as issue #\($0)." }
                ?? "Thank you! It has been filed."
            if skipped > 0 {
                text += skipped == 1
                    ? " 1 attachment couldn't be included."
                    : " \(skipped) attachments couldn't be included."
            }
            return text
        case .received:
            return "Thank you! It was received and will be filed shortly."
        }
    }
}

// MARK: - Presentation order

/// Settings' side of a filed form: the sheet hands over its notice and closes itself,
/// and the alert appears only once the sheet has gone (issue #565).
///
/// One presentation at a time (pattern `modal-shell` R7). HIG Sheets: a sheet is "a
/// scoped, context-related task people complete before returning to the parent view";
/// HIG Modality: "Let people dismiss a modal before presenting another."
struct FeedbackSentPresentation: Equatable, Sendable {
    /// Handed over by a closing form; not shown until its sheet's `onDismiss`.
    private(set) var pending: FeedbackSentNotice?
    /// The alert on screen over Settings.
    private(set) var shown: FeedbackSentNotice?

    /// The form reached its sent state and is closing.
    ///
    /// - Parameter notice: What the alert will say.
    mutating func formFinished(_ notice: FeedbackSentNotice) {
        pending = notice
    }

    /// The form's sheet has gone: show the alert it handed over, if any. A form closed
    /// without sending (Cancel, Discard, a swipe while filing) shows nothing.
    mutating func formDismissed() {
        guard let pending else { return }
        shown = pending
        self.pending = nil
    }

    /// Done on the alert.
    ///
    /// - Returns: The kind whose Settings row takes accessibility focus back, or nil when
    ///   no alert was showing.
    mutating func acknowledge() -> FeedbackKind? {
        defer { shown = nil }
        return shown?.kind
    }
}
