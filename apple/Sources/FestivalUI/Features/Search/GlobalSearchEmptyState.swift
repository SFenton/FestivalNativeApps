import SwiftUI
import FestivalCore

// MARK: - Empty state

/// Global search's empty state (issue #99): a magnifier, a title and a subtitle, centred
/// horizontally and vertically below the scope bar through the shared
/// ``FestivalEmptyState`` (issue #377), like the web's centred search hint.
///
/// VoiceOver reads it as one static element, "title. subtitle". No Retry (issue #299,
/// web parity): the subtitle is the next step (HIG Writing: "Provide clear next steps on
/// any blank screens"), and the keyboard's Search key re-runs a possibly timed-out player
/// search. On a partially folded iPhone Duo it centres beside the fold, never on it.
struct GlobalSearchEmptyStateView: View {
    let state: GlobalSearch.EmptyState

    var body: some View {
        FestivalEmptyState(
            state.title, systemImage: "magnifyingglass", subtitle: state.subtitle,
            reading: .combined, accessibilityIdentifier: "fst.global-search.hint"
        )
    }
}
