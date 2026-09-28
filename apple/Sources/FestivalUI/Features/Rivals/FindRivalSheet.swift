import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - FindRivalSheet

/// "Find Rival" search sheet, reached from `RivalsScreen`'s toolbar
/// (`fst.rivals.findRival`), mirroring the web's `SearchModal` in
/// `availableTargets: ['players']` mode.
///
/// Reuses the same public, keyless `GET /api/account/search?q=&limit=`
/// (`ProfileSearch.swift`, already allowlisted for player search in
/// `ProfileSelectionSheet`) rather than a Rivals-specific endpoint — Find Rival is
/// just "select any player, then open their rival detail". A selected result
/// pushes `AppRoute.rivalDetail` with a `nil` scope, matching how the web's
/// `handleFindRivalSelect` asks the detail page to derive scope from Settings
/// rather than from a specific instrument's list: this app's destination screen
/// already falls back to merging every Settings-visible instrument for a `nil`
/// scope (`FestivalSession.rivalDetail(forScope:rivalId:visibleInstruments:)`).
///
/// Pushes inside the sheet's own `NavigationStack` rather than dismissing and
/// pushing on the presenting tab, for the same reason `ProfileSelectionSheet`
/// does (see its type doc): no cross-lane seam exists today for a sheet to push
/// onto the presenting tab's own path.
struct FindRivalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [AppRoute] = []
    @State private var query = ""
    @State private var phase = Phase.enterQuery
    @State private var retry = 0
    @FocusState private var searchFocused: Bool

    let session: FestivalSession

    private enum Phase {
        case enterQuery
        case loading
        case results([PlayerSearchResult])
        case failed(String)
    }

    private struct SearchKey: Hashable {
        let query: String
        let retry: Int
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    searchField
                } header: {
                    FestivalSectionHeader("Find a Rival")
                }
                .listRowBackground(Color.white.opacity(0.06))
                Section {
                    resultsContent
                }
                .listRowBackground(Color.white.opacity(0.06))
                .listRowInsets(EdgeInsets())
            }
            .scrollContentBackground(.hidden)
            .background(BrandTokens.appBackground)
            .navigationTitle("Find Rival")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Dismiss-only modal: trailing, per the app's modal-standard placement
                // (operator, 2026-09-28) — not leading like a paired Cancel action.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("fst.rivals.findRival.close")
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(
                    route: route, session: session, visibleInstruments: [],
                    path: $path, isVisible: true
                )
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in phase = .enterQuery }
        .task(id: SearchKey(query: query, retry: retry)) { await search() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FestivalText.deemphasized)
                .accessibilityHidden(true)
            TextField(
                "", text: $query,
                prompt: Text("Find Rival").foregroundStyle(FestivalText.deemphasized)
            )
            .textFieldStyle(.plain)
            .focused($searchFocused)
            .submitLabel(.search)
            .onSubmit { searchFocused = false }
            .accessibilityLabel("Find Rival")
            .accessibilityIdentifier("fst.rivals.findRival.search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FestivalText.deemphasized)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(BrandTokens.appBackground, in: Capsule())
    }

    @ViewBuilder private var resultsContent: some View {
        switch phase {
        case .enterQuery:
            VStack {
                Spacer(minLength: 0)
                Text("Enter at least two characters to search for a rival.")
                    .foregroundStyle(FestivalText.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .containerRelativeFrame(.vertical) { length, _ in max(length * 0.55, 180) }
        case .loading:
            HStack {
                Spacer(minLength: 0)
                FestivalLoadingView(accessibilityLabel: "Searching Players")
                Spacer(minLength: 0)
            }
            .padding(.vertical, 32)
        case let .results(results):
            if results.isEmpty {
                VStack(spacing: 12) {
                    Text("No player results were returned. Try another search or Retry.")
                        .foregroundStyle(FestivalText.primary)
                        .multilineTextAlignment(.center)
                    Button("Retry Search") { retry += 1 }
                        .tint(BrandTokens.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // One `Form` row per result (`PlayerSearchResultRows`' doc: a
                // shared row of links fired every result on one tap).
                PlayerSearchResultRows(results) { player in
                    NavigationLink(value: AppRoute.rivalDetail(
                        rivalId: player.accountId, name: player.displayName, scope: nil
                    )) {
                        Label(player.displayName, systemImage: "person.crop.circle")
                            .foregroundStyle(BrandTokens.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .accessibilityLabel("View rivalry with \(player.displayName)")
                    .accessibilityIdentifier("fst.rivals.findRival.result.\(player.accountId)")
                }
            }
        case let .failed(message):
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Player search unavailable: \(message)")
                }
                .foregroundStyle(BrandTokens.gold)
                Button("Retry Search") { retry += 1 }
                    .tint(BrandTokens.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }

    /// Debounce and cancel an obsolete search instead of presenting older results.
    private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        phase = .loading
        do {
            try await Task.sleep(for: .milliseconds(250))
            let response = try await session.client().searchPlayers(query: term)
            try Task.checkCancellation()
            phase = .results(response.results)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
