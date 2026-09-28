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

/// Native profile-discovery sheet: an already-selected profile summary, a
/// Players/Bands search scope, and an honest Bands gate.
///
/// Presented by the root shell inside `.festivalSheet()` (dark Liquid Glass per
/// `.agents/design/apple/liquid-glass.md`); this file supplies only the content, and
/// follows that doc's "sections inside sheets" rule (native `Form`/`List` sections
/// with `FestivalSectionHeader` and a tinted `listRowBackground`, never a nested
/// glass card, to avoid glass-on-glass inside the already-glass sheet).
///
/// **Navigation choice — dismiss the sheet, then push onto the presenting tab:**
/// a result row and the selected-profile summary's "View Profile" both dismiss this
/// sheet and push the *real* `AppRoute.player` route onto whichever tab presented it,
/// via the `openRoute` closure parameter `FestivalRootView` passes in (see that
/// property's own doc comment for why it is a plain closure and not the
/// environment-based `OpenRouteAction`/`\.openRoute` the rest of the app uses for
/// this same dismiss-then-push shape). An earlier draft pushed `AppRoute.player`
/// inside this sheet's own `NavigationStack`
/// instead — genuinely simpler (no cross-lane seam) but the wrong UX once compared to
/// native search flows: the pushed player screen offers Select/Switch/Deselect
/// actions that change app-wide state (the selected profile, visible tabs, Songs
/// filters), and having those actions live one level inside a still-presented sheet
/// reads as "still searching" rather than "you're now on your new profile" — closing
/// the sheet afterward is an extra, unnecessary step. Dismiss-then-push matches how
/// Contacts/Messages "New Message" search hands off to the real destination, and
/// keeps this sheet a pure finder with no navigation state of its own.
///
/// **Search field — a styled `TextField`, not literal `.searchable`:** HIG prefers
/// `.searchable` for a search pill, but this sheet is exercised by macOS
/// `NSHostingView` snapshot tests that introspect a concrete `NSTextField` /
/// `NSSegmentedControl` off-window (`ProfileSelectionSheetRenderTests.swift`).
/// `.searchable`'s system search bar is chrome the host window places, not a plain
/// subview, so it cannot be relied on to render (or to be found) in an off-window
/// host. The field below matches `.searchable`'s exact visual shape (leading
/// magnifying glass, rounded capsule, trailing clear button, scope-aware prompt)
/// while staying a directly hosted, testable control.
struct ProfileSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scope = ProfileSearchScope.players
    @State private var query = ""
    @State private var searchPhase = PlayerSearchPhase.enterQuery
    @State private var searchRetry = 0
    @State private var deselectPending = false
    @FocusState private var searchFocused: Bool

    let session: FestivalSession
    /// Dismiss-then-push hook, called after `dismiss()` with the route to push onto
    /// the presenting tab. A plain closure parameter, **not** `\.openRoute`
    /// (`FestivalRootView`'s environment action of the same shape): verified
    /// empirically that a custom `@Entry` environment value set by the presenting
    /// view — this one, and the pre-existing `\.openDrawer` — never actually fires
    /// once read from inside this sheet's own content, even though both read
    /// correctly everywhere else in the app. `FestivalRootView` passes its
    /// `paths[selected, default: []].append` directly here instead, the same
    /// closure-capture mechanism `FestivalDrawer`'s proven-working `onIntent:
    /// handleDrawer` already uses. Defaults to a no-op for hosted previews/tests
    /// that construct this sheet without the root shell.
    var openRoute: (AppRoute) -> Void = { _ in }

    private struct SearchKey: Hashable {
        let query: String
        let scope: ProfileSearchScope
        let retry: Int
    }

    var body: some View {
        NavigationStack {
            Form {
                if let selected = session.selectedPlayer {
                    Section {
                        selectedProfileRow(selected)
                    } header: {
                        FestivalSectionHeader("Selected Profile")
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                Section {
                    scopePicker
                    searchField
                } header: {
                    FestivalSectionHeader("Find a Profile")
                }
                .listRowBackground(Color.white.opacity(0.06))
                Section {
                    scopeResultsContent
                }
                .listRowBackground(Color.white.opacity(0.06))
                .listRowInsets(EdgeInsets())
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Profiles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
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
        .confirmationDialog(
            "Deselect profile?", isPresented: $deselectPending,
            titleVisibility: .visible
        ) {
            Button("Deselect Profile", role: .destructive) { session.deselectPlayer() }
        } message: {
            Text("Scores and profile-only content will be hidden; app Settings stay saved.")
        }
    }

    /// Native segmented Players/Bands scope (`fst.profile.scope`, an `NSSegmentedControl`
    /// under macOS hosting) — unchanged shape so existing native-render tests still
    /// introspect a real control.
    private var scopePicker: some View {
        Picker("Search profiles", selection: $scope) {
            ForEach(ProfileSearchScope.allCases) { target in
                Text(target.label).tag(target)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("fst.profile.scope")
    }

    /// Search-pill styled like `.searchable`; see the type doc for why it is a plain
    /// `TextField` rather than the modifier itself.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FestivalText.deemphasized)
                .accessibilityHidden(true)
            TextField(
                "", text: $query,
                prompt: Text(scope.searchPrompt).foregroundStyle(FestivalText.deemphasized)
            )
            .textFieldStyle(.plain)
            .focused($searchFocused)
            .submitLabel(.search)
            .onSubmit { searchFocused = false }
            .disabled(scope == .bands)
            .accessibilityLabel(scope.searchPrompt)
            .accessibilityIdentifier("fst.profile.search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FestivalText.deemphasized)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
                .accessibilityIdentifier("fst.profile.search-clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(BrandTokens.appBackground, in: Capsule())
    }

    /// Selected-profile summary; "View Profile" routes through the real `AppRoute.player`.
    ///
    /// - Parameter selected: Currently selected, previously validated identity.
    private func selectedProfileRow(_ selected: SelectedPlayerIdentity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .accessibilityHidden(true)
                Text(selected.displayName)
                    .accessibilityIdentifier("fst.profile.selected")
            }
            .foregroundStyle(BrandTokens.textPrimary)
            HStack(spacing: 16) {
                Button("View Profile") {
                    openPlayer(accountId: selected.accountId, displayName: selected.displayName)
                }
                .accessibilityIdentifier("fst.profile.view-selected")
                Button("Deselect", role: .destructive) { deselectPending = true }
                    .accessibilityIdentifier("fst.profile.deselect")
            }
            .buttonStyle(.borderless)
            .tint(BrandTokens.accentBlue)
        }
    }

    /// Bands gate, the enter-query hint (centered in the remaining sheet space,
    /// per the operator's requirement), loading, results and error states.
    @ViewBuilder private var scopeResultsContent: some View {
        switch scope {
        case .bands:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.3")
                    .accessibilityHidden(true)
                Text("Band search is paused: the service's fallback for a missing "
                    + "band index rebuilds membership data instead of only reading it, "
                    + "so this app never sends that request.")
                    .accessibilityIdentifier("fst.profile.bands-unavailable")
            }
            .foregroundStyle(FestivalText.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
        case .players:
            switch searchPhase {
            case .enterQuery:
                VStack {
                    Spacer(minLength: 0)
                    Text("Enter at least two characters to search for players.")
                        .foregroundStyle(FestivalText.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
                .containerRelativeFrame(.vertical) { length, _ in max(length * 0.55, 180) }
                .accessibilityIdentifier("fst.profile.search-hint")
            case .loading:
                HStack {
                    Spacer(minLength: 0)
                    FestivalLoadingView(accessibilityLabel: "Searching Players")
                        .accessibilityIdentifier("fst.profile.search-loading")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 32)
            case let .results(results):
                if results.isEmpty {
                    VStack(spacing: 12) {
                        Text("No player results were returned. Try another search or Retry.")
                            .foregroundStyle(FestivalText.primary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("fst.profile.search-empty")
                        Button("Retry Player Search") { searchRetry += 1 }
                            .tint(BrandTokens.textPrimary)
                            .accessibilityIdentifier("fst.profile.search-retry")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    // One `Form` row per result (`PlayerSearchResultRows`' doc: a
                    // shared row of Buttons fired every result on one tap).
                    PlayerSearchResultRows(results) { player in
                        Button {
                            openPlayer(accountId: player.accountId, displayName: player.displayName)
                        } label: {
                            Label(player.displayName, systemImage: "person.crop.circle")
                                .foregroundStyle(BrandTokens.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .padding(.horizontal, 16)
                        .accessibilityLabel("View \(player.displayName)")
                        .accessibilityIdentifier("fst.profile.result.\(player.accountId)")
                    }
                }
            case let .failed(message):
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .accessibilityHidden(true)
                        Text("Player search unavailable: \(message)")
                            .accessibilityIdentifier("fst.profile.search-error")
                    }
                    .foregroundStyle(BrandTokens.gold)
                    Button("Retry Player Search") { searchRetry += 1 }
                        .tint(BrandTokens.textPrimary)
                        .accessibilityIdentifier("fst.profile.search-retry")
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        }
    }

    /// Dismiss this sheet, then push the real player-profile route on the presenting
    /// tab, so its Select/Switch/Deselect actions land back on that tab, not inside
    /// a sheet the user still has to close afterward.
    ///
    /// - Parameters:
    ///   - accountId: Public account key from the selected identity or a search result.
    ///   - displayName: Name known before the pushed screen's own read completes.
    private func openPlayer(accountId: String, displayName: String) {
        let route = AppRoute.player(accountId: accountId, displayName: displayName)
        dismiss()
        openRoute(route)
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
