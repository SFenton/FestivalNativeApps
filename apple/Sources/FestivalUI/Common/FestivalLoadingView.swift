import SwiftUI
import FestivalDesign

// MARK: - FestivalLoadingView

/// The app's one loading spinner (operator, 2026-09-28: "Any loading spinner should be
/// white, with no subtitle"). A plain circular `ProgressView`, tinted pure white, with no
/// visible title or subtitle text — only an accessibility label so VoiceOver still
/// announces what is loading.
///
/// Use this in place of every `ProgressView("…")`/`ProgressView()` across `Features/**`
/// (see `.agents/design/apple/liquid-glass.md` — spinners are content, not glass, so they
/// need no container of their own). Callers keep their own `.frame(...)` sizing: this view
/// does not force full-screen layout so it can sit inside a row, card or footer unchanged.
struct FestivalLoadingView: View {
    /// Spoken-only context for VoiceOver; never rendered as visible text.
    var accessibilityLabel: String = "Loading"

    var body: some View {
        ProgressView()
            .tint(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }
}
