import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Available native search scopes; band reads remain blocked by the service contract
/// (`.agents/controls/profile-selection.md`): the band-search GET's missing-projection
/// fallback deletes/rebuilds membership state, so this scope never issues a request.
private enum ProfileSearchScope: String, CaseIterable, Identifiable {
    case players
    case bands

    var id: Self { self }
    var label: String { rawValue.capitalized }

    /// Search-pill placeholder text, matching the requested copy per scope.
    var searchPrompt: String {
        switch self {
        case .players: "Find Player"
        case .bands: "Find Band"
        }
    }
}

private enum PlayerSearchPhase {
    case enterQuery
    case loading
    case results([PlayerSearchResult])
    case failed(String)
}

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

/// Native profile-discovery sheet: a Players/Bands search scope over the results, and an
/// honest Bands gate. It mirrors the web's Select Profile search modal, which has no
/// selected-profile summary: the selected player is reached from the header profile
/// button and deselected from their own page (operator, 2026-09-28: no "Public
/// Profile" container).
///
/// Presented by the root shell inside `.festivalSheet()` (dark Liquid Glass per
/// `.agents/design/apple/liquid-glass.md`); this file supplies only the content.
///
/// **Navigation choice — dismiss the sheet, then push onto the presenting tab:**
/// a result row dismisses this sheet and pushes the *real* `AppRoute.player` route onto
/// whichever tab presented it, via the `openRoute` closure parameter `FestivalRootView`
/// passes in. The pushed player screen offers Select/Switch/Deselect actions that change
/// app-wide state, so they must not live one level inside a still-presented sheet.
///
/// **Search field:** iOS uses the system `.searchable` field in the navigation-bar
/// drawer (no custom fill), with `.searchPresentationToolbarBehavior(.avoidHidingContent)`
/// so the title and Close stay while the field is focused. macOS keeps a plain rounded
/// `TextField` because its hosted snapshot tests introspect a concrete `NSTextField`
/// off-window, where `.searchable`'s window-placed chrome never renders.
struct ProfileSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scope = ProfileSearchScope.players
    @State private var query = ""
    @State private var searchPhase = PlayerSearchPhase.enterQuery
    @State private var searchRetry = 0
    @FocusState private var searchFocused: Bool

    let session: FestivalSession
    /// Dismiss-then-push hook, called after `dismiss()` with the route to push onto
    /// the presenting tab. A plain closure parameter, **not** `\.openRoute`: a custom
    /// `@Entry` environment value set by the presenting view never fires once read from
    /// inside this sheet's own content. Defaults to a no-op for hosted tests.
    var openRoute: (AppRoute) -> Void = { _ in }

    private struct SearchKey: Hashable {
        let query: String
        let scope: ProfileSearchScope
        let retry: Int
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    #if os(macOS)
                    searchField
                    #endif
                    scopePicker
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                scopeResultsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Profiles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(scope.searchPrompt)
            )
            .modifier(KeepSheetChromeWhileSearching())
            #endif
            .toolbar {
                // Dismiss-only modal: trailing, matching the app's modal-standard
                // placement (operator, 2026-09-28) — not leading like a paired Cancel.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("fst.profile.close")
                }
            }
        }
        .onChange(of: query) { _, _ in searchPhase = .enterQuery }
        .onChange(of: scope) { _, _ in searchPhase = .enterQuery }
        .task(id: SearchKey(query: query, scope: scope, retry: searchRetry)) {
            await search()
        }
    }

    /// Native segmented Players/Bands scope (`fst.profile.scope`, an `NSSegmentedControl`
    /// under macOS hosting).
    private var scopePicker: some View {
        Picker("Search profiles", selection: $scope) {
            ForEach(ProfileSearchScope.allCases) { target in
                Text(target.label).tag(target)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("fst.profile.scope")
    }

    #if os(macOS)
    /// macOS-only system rounded field (see the type doc); disabled in Bands scope.
    private var searchField: some View {
        TextField(scope.searchPrompt, text: $query)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .onSubmit { searchFocused = false }
            .disabled(scope == .bands)
            .accessibilityLabel(scope.searchPrompt)
            .accessibilityIdentifier("fst.profile.search")
    }
    #endif

    /// A message centred in the space between the scope control and the bottom safe area.
    ///
    /// - Parameters:
    ///   - text: White status or hint text.
    ///   - identifier: Accessibility identifier for journey tests.
    private func centredMessage(_ text: String, identifier: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.body)
                .foregroundStyle(FestivalText.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .accessibilityIdentifier(identifier)
            Spacer(minLength: 0)
        }
    }

    /// Bands gate, the enter-query hint, loading, results and error states.
    @ViewBuilder private var scopeResultsContent: some View {
        switch scope {
        case .bands:
            centredMessage(
                "Band search is paused: the service's fallback for a missing "
                    + "band index rebuilds membership data instead of only reading it, "
                    + "so this app never sends that request.",
                identifier: "fst.profile.bands-unavailable"
            )
        case .players:
            switch searchPhase {
            case .enterQuery:
                centredMessage(
                    "Enter at least two characters to search for players.",
                    identifier: "fst.profile.search-hint"
                )
            case .loading:
                VStack {
                    Spacer(minLength: 0)
                    FestivalLoadingView(accessibilityLabel: "Searching Players")
                        .accessibilityIdentifier("fst.profile.search-loading")
                    Spacer(minLength: 0)
                }
            case let .results(results):
                if results.isEmpty {
                    VStack(spacing: 12) {
                        Spacer(minLength: 0)
                        Text("No player results were returned. Try another search or Retry.")
                            .foregroundStyle(FestivalText.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .accessibilityIdentifier("fst.profile.search-empty")
                        Button("Retry Player Search") { searchRetry += 1 }
                            .tint(BrandTokens.textPrimary)
                            .accessibilityIdentifier("fst.profile.search-retry")
                        Spacer(minLength: 0)
                    }
                } else {
                    resultsList(results)
                }
            case let .failed(message):
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .accessibilityHidden(true)
                        Text("Player search unavailable: \(message)")
                            .accessibilityIdentifier("fst.profile.search-error")
                    }
                    .foregroundStyle(BrandTokens.gold)
                    .padding(.horizontal, 32)
                    Button("Retry Player Search") { searchRetry += 1 }
                        .tint(BrandTokens.textPrimary)
                        .accessibilityIdentifier("fst.profile.search-retry")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// One `List` row per result (`PlayerSearchResultRows`' doc: a shared row of Buttons
    /// fired every result on one tap), in a native inset section.
    ///
    /// - Parameter results: Validated, non-empty search results.
    private func resultsList(_ results: [PlayerSearchResult]) -> some View {
        List {
            Section {
                PlayerSearchResultRows(results) { player in
                    Button {
                        openPlayer(accountId: player.accountId, displayName: player.displayName)
                    } label: {
                        Label(player.displayName, systemImage: "person.crop.circle")
                            .foregroundStyle(BrandTokens.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("View \(player.displayName)")
                    .accessibilityIdentifier("fst.profile.result.\(player.accountId)")
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .scrollContentBackground(.hidden)
        .festivalFadeIn(isLoaded: true)
    }

    /// Dismiss this sheet, then push the real player-profile route on the presenting
    /// tab, so its Select/Switch/Deselect actions land back on that tab, not inside
    /// a sheet the user still has to close afterward.
    ///
    /// - Parameters:
    ///   - accountId: Public account key from the selected identity or a search result.
    ///   - displayName: Name known before the pushed screen's own read completes.
    ///
    /// The page is placed on the stack without a push animation, under the sheet, and
    /// the sheet's own dismissal reveals it: one system transition. Pushing while the
    /// sheet slid away ran both at once, and the pushed page's navigation bar (Back,
    /// actions) only appeared after both finished.
    private func openPlayer(accountId: String, displayName: String) {
        let route = AppRoute.player(accountId: accountId, displayName: displayName)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { openRoute(route) }
        dismiss()
    }

    /// Debounce and cancel an obsolete search instead of presenting older results.
    private func search() async {
        guard scope == .players else { return }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        searchPhase = .loading
        do {
            try await Task.sleep(for: .milliseconds(250))
            let response = try await session.client().searchPlayers(query: term)
            try Task.checkCancellation()
            searchPhase = .results(response.results)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searchPhase = .failed(error.localizedDescription)
        }
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
