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
/// **Navigation choice — push inside the sheet's own stack, not dismiss-then-push:**
/// a result (or the selected-profile summary's "View Profile") pushes the *real*
/// `AppRoute.player` route through the shared `AppRouteDestination`, the exact same
/// screen the Songs/Leaderboards tabs push, using this sheet's own `NavigationStack`.
/// This needed no cross-lane seam change: `AppRoute`/`AppRouteDestination` are
/// orchestrator types already visible within `FestivalUI`. Dismissing the sheet and
/// pushing onto the *presenting tab's* own path instead would require
/// `FestivalRootView` (Lane A, which owns the sheet presentation and per-tab paths)
/// to expose a new callback/environment action — flagged as a follow-up rather than
/// done here. Because the pushed screen already offers Select/Switch/Deselect,
/// closing the sheet from there returns straight to the tab it was opened from,
/// which matches how Contacts/Messages "New Message" search behaves.
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
    @State private var path: [AppRoute] = []
    @State private var scope = ProfileSearchScope.players
    @State private var query = ""
    @State private var searchPhase = PlayerSearchPhase.enterQuery
    @State private var searchRetry = 0
    @State private var deselectPending = false
    @FocusState private var searchFocused: Bool

    let session: FestivalSession

    private struct SearchKey: Hashable {
        let query: String
        let scope: ProfileSearchScope
        let retry: Int
    }

    var body: some View {
        NavigationStack(path: $path) {
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
            .background(BrandTokens.appBackground)
            .navigationTitle("Profiles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("fst.profile.close")
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(
                    route: route, session: session, visibleInstruments: [],
                    path: $path, isVisible: true
                )
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
                .foregroundStyle(BrandTokens.textSecondary)
                .accessibilityHidden(true)
            TextField(
                "", text: $query,
                prompt: Text(scope.searchPrompt).foregroundStyle(BrandTokens.textSecondary)
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
                        .foregroundStyle(BrandTokens.textSecondary)
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
                NavigationLink(value: AppRoute.player(
                    accountId: selected.accountId, displayName: selected.displayName
                )) {
                    Text("View Profile")
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
            .foregroundStyle(BrandTokens.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
        case .players:
            switch searchPhase {
            case .enterQuery:
                VStack {
                    Spacer(minLength: 0)
                    Text("Enter at least two characters to search for players.")
                        .foregroundStyle(BrandTokens.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
                .containerRelativeFrame(.vertical) { length, _ in max(length * 0.55, 180) }
                .accessibilityIdentifier("fst.profile.search-hint")
            case .loading:
                HStack {
                    Spacer(minLength: 0)
                    ProgressView("Searching Players")
                        .accessibilityIdentifier("fst.profile.search-loading")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 32)
            case let .results(results):
                if results.isEmpty {
                    VStack(spacing: 12) {
                        Text("No player results were returned. Try another search or Retry.")
                            .foregroundStyle(BrandTokens.textSecondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("fst.profile.search-empty")
                        Button("Retry Player Search") { searchRetry += 1 }
                            .tint(BrandTokens.textPrimary)
                            .accessibilityIdentifier("fst.profile.search-retry")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { player in
                            Divider().overlay(BrandTokens.glassBorder)
                            NavigationLink(value: AppRoute.player(
                                accountId: player.accountId, displayName: player.displayName
                            )) {
                                Label(player.displayName, systemImage: "person.crop.circle")
                                    .foregroundStyle(BrandTokens.textPrimary)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .accessibilityLabel("View \(player.displayName)")
                            .accessibilityIdentifier("fst.profile.result.\(player.accountId)")
                        }
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
