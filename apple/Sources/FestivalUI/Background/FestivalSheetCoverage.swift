import Observation
import SwiftUI

// MARK: - Sheet coverage

/// Counts the app's presented sheets so the shared backdrop can pause beneath them.
///
/// A sheet covers most of the page, and on iOS 26 its Liquid Glass re-blurs
/// whatever moves behind it every frame. Pausing the decorative zoom/pan and
/// crossfades while any sheet is up removes that work (issue #28); the carousel
/// resumes from where it stopped when the last sheet closes.
///
/// Process-wide rather than per session because sheet content cannot reliably
/// read custom environment values set by its presenter.
@MainActor
@Observable
final class FestivalSheetCoverage {
    /// The app's one counter.
    static let shared = FestivalSheetCoverage()

    /// Sheets currently on screen.
    private(set) var count = 0

    /// True while at least one sheet is presented.
    var isCovered: Bool { count > 0 }

    /// Record a sheet appearing.
    func begin() {
        count += 1
    }

    /// Record a sheet disappearing (never below zero).
    func end() {
        count = max(0, count - 1)
    }
}

/// Registers its content as a presented sheet while it is on screen.
private struct FestivalSheetCoverageModifier: ViewModifier {
    @State private var registered = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !registered else { return }
                registered = true
                FestivalSheetCoverage.shared.begin()
            }
            .onDisappear {
                guard registered else { return }
                registered = false
                FestivalSheetCoverage.shared.end()
            }
    }
}

extension View {
    /// Pause the shared album-art backdrop while this sheet content is on screen.
    ///
    /// Apply once to the root of a sheet's content (`festivalSheet` and the
    /// first-run sheet already do).
    ///
    /// - Returns: The content, registered with `FestivalSheetCoverage`.
    func pausesFestivalBackdrop() -> some View {
        modifier(FestivalSheetCoverageModifier())
    }
}
