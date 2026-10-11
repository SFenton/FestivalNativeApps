import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// One compact, named toolbar action for a tab root that has not adopted
/// `festivalRootChrome`/`RootProfileButton` (`App/Shell/RootChrome.swift`) yet.
///
/// Kept only for `Features/Songs/SongsScreen.swift`, which still presents its own
/// profile sheet; new call sites should use the shared root chrome instead.
struct ProfileActionButton: View {
    let session: FestivalSession
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            Label(
                session.selectedPlayer?.displayName ?? "Choose Profile",
                systemImage: "person.crop.circle"
            )
        }
        .accessibilityLabel(session.selectedPlayer.map {
            "Profile: \($0.displayName)"
        } ?? "Choose Profile")
        .accessibilityIdentifier("fst.profile.open")
    }
}

/// Native profile-discovery sheet: the web's Select Profile search (`SearchModal` with
/// targets `players|bands`), built from global search's own model and results view
/// (``GlobalSearchModel`` with ``GlobalSearchTargets/profiles``, ``GlobalSearchResults``;
/// pattern `search-scopes`, issue #600). An All · Players · Bands scope bar starts on All;
/// players and bands are searched together and the scope only filters what shows. It has
/// no selected-profile summary: the selected player is reached from the header profile
/// button and deselected from their own page (operator, 2026-09-28: no "Public Profile"
/// container).
///
/// Presented by the root shell inside `.festivalSheet()` (dark Liquid Glass per
/// `.agents/design/apple/liquid-glass.md`); this file supplies only the content.
///
/// **Navigation choice — dismiss the sheet, then push onto the presenting tab:**
/// a result dismisses this sheet and pushes its route (player profile, the selected
/// player's Statistics, or a band page) onto whichever tab presented it, via the
/// `openRoute` closure parameter `FestivalRootView` passes in. The pushed player screen
/// offers Select/Switch/Deselect actions that change app-wide state, so they must not
/// live one level inside a still-presented sheet. Native apps cannot select a band as the
/// profile yet, so a band result opens its page, like global search.
///
/// **Search field:** iOS uses the system `.searchable` field in the navigation-bar
/// drawer (no custom fill), with `.searchPresentationToolbarBehavior(.avoidHidingContent)`
/// so the title and Close stay while the field is focused. macOS uses the shared
/// ``GlobalSearchField`` (`fst.profile.search`, a concrete `NSTextField` that the hosted
/// snapshot tests introspect off-window, where `.searchable`'s window-placed chrome
/// never renders).
struct ProfileSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = GlobalSearchModel(targets: .profiles)

    let session: FestivalSession
    /// Dismiss-then-push hook, called after `dismiss()` with the route to push onto
    /// the presenting tab. A plain closure parameter, **not** `\.openRoute`: a custom
    /// `@Entry` environment value set by the presenting view never fires once read from
    /// inside this sheet's own content. Defaults to a no-op for hosted tests.
    var openRoute: (AppRoute) -> Void = { _ in }

    var body: some View {
        FestivalModal("Profiles", closeIdentifier: "fst.profile.close") {
            #if os(macOS)
            GlobalSearchResults(model: model, session: session, open: open)
            #else
            GlobalSearchResults(model: model, session: session, open: open, showsField: false)
                .searchable(
                    text: $model.query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(GlobalSearch.prompt(for: model.scope, targets: model.targets))
                )
                // No Retry button (issue #299, like global search): Search re-runs a
                // failed or empty search.
                .onSubmit(of: .search) { model.submit() }
                .modifier(KeepSheetChromeWhileSearching())
            #endif
        }
        .task(id: model.runKey) { await model.search(session: session) }
    }

    /// Dismiss this sheet, then push the result's route on the presenting tab, so a
    /// player's Select/Switch/Deselect actions land back on that tab, not inside a sheet
    /// the user still has to close afterward.
    ///
    /// - Parameter route: The chosen player, the selected player's Statistics, or a band.
    ///
    /// The page is placed on the stack without a push animation, under the sheet, and
    /// the sheet's own dismissal reveals it: one system transition. Pushing while the
    /// sheet slid away ran both at once, and the pushed page's navigation bar (Back,
    /// actions) only appeared after both finished.
    private func open(_ route: AppRoute) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { openRoute(route) }
        dismiss()
    }
}

// MARK: - Search chrome

#if os(iOS)
/// Keeps the sheet's title and Close visible while the search field is focused.
///
/// `.searchable` hides the navigation bar on activation by default, which removed the
/// only way to close this sheet mid-search (the same bug the global search sheet had).
private struct KeepSheetChromeWhileSearching: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.1, *) {
            content.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            content
        }
    }
}
#endif
