import SwiftUI
import FestivalCore

// MARK: - Shared tab-root chrome

/// Environment action that opens the profile selection sheet from anywhere
/// (e.g. an in-page "Choose Profile" empty-state button).
struct OpenProfileAction {
    let handler: @MainActor () -> Void

    /// Present profile selection.
    @MainActor func callAsFunction() { handler() }
}

extension EnvironmentValues {
    /// Opens the profile selection sheet owned by the tab-root chrome.
    @Entry var openProfile = OpenProfileAction(handler: {})
}

extension View {
    /// Standard chrome for every tab root: drawer button (leading) and profile
    /// button (trailing, top-right like the web header).
    ///
    /// Page-specific toolbar items (search, sort, filter) are added by the page
    /// itself with its own `.toolbar { … }`; this modifier owns only the shared
    /// items and the profile sheet. Owned by Lane A (Shell).
    ///
    /// - Parameter session: Shared app session.
    /// - Returns: The page with shared chrome attached.
    func festivalRootChrome(session: FestivalSession) -> some View {
        modifier(FestivalRootChrome(session: session))
    }
}

/// Implementation of `festivalRootChrome(session:)`.
struct FestivalRootChrome: ViewModifier {
    let session: FestivalSession
    @State private var profilePresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileActionButton(session: session) { profilePresented = true }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    ProfileActionButton(session: session) { profilePresented = true }
                }
                #endif
            }
            .sheet(isPresented: $profilePresented) {
                ProfileSelectionSheet(session: session)
            }
            .environment(\.openProfile, OpenProfileAction { profilePresented = true })
    }
}
