import SwiftUI

// MARK: - Form and library panes

/// The feedback form alone, or the form and its photo library side by side (issue #373,
/// pattern `modal-shell` R11).
///
/// The pair is one canonical ``HingeRow`` (pattern `hinge-columns`) with the fold policy
/// and full-height cells, never a page-local stack: on a partially folded iPhone Duo the
/// form ends at the fold's clearance and the library starts after it (R1); fully open, on
/// iPad and everywhere else the panes divide the sheet's own free width at its midpoint
/// (R7). Folding and unfolding reflow the same panes in place (R5), so ticks, typed text
/// and the picker's scroll position survive. A hairline separates the library from the
/// form.
struct FeedbackFormPanes<Form: View, Library: View>: View {
    private let showsLibrary: Bool
    private let form: Form
    private let library: Library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Create the panes.
    ///
    /// - Parameters:
    ///   - showsLibrary: Whether the library pane is open beside the form.
    ///   - form: The form (always shown, leading).
    ///   - library: The photo library pane (trailing, while `showsLibrary`).
    init(showsLibrary: Bool, @ViewBuilder form: () -> Form, @ViewBuilder library: () -> Library) {
        self.showsLibrary = showsLibrary
        self.form = form()
        self.library = library()
    }

    var body: some View {
        HingeRow(spacing: 0, fillsHeight: true) {
            form
            if showsLibrary {
                library
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1)
                            .ignoresSafeArea(edges: .bottom)
                            .accessibilityHidden(true)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: showsLibrary)
    }
}
