import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Available native search scopes; band reads remain blocked by the service contract.
private enum ProfileSearchScope: String, CaseIterable, Identifiable {
    case players
    case bands

    var id: Self { self }
    var label: String { rawValue.capitalized }
}

private enum PlayerSearchPhase {
    case enterQuery
    case loading
    case results([PlayerSearchResult])
    case failed(String)
}

private enum ViewedPlayerPhase {
    case loading
    case available(PlayerProfilePayload)
    case syncing
    case failed(String)
}

/// One compact, named native toolbar action shared across root destinations.
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

/// Separate viewed player, explicit selection and confirmed switching/deselection.
struct ProfileSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scope = ProfileSearchScope.players
    @State private var query = ""
    @State private var searchPhase = PlayerSearchPhase.enterQuery
    @State private var viewed: PlayerSearchResult?
    @State private var preview = ViewedPlayerPhase.loading
    @State private var searchRetry = 0
    @State private var previewRetry = 0
    @State private var switchPending = false
    @State private var deselectPending = false
    @State private var selectionError: String?
    @FocusState private var searchFocused: Bool

    let session: FestivalSession

    private struct SearchKey: Hashable {
        let query: String
        let scope: ProfileSearchScope
        let retry: Int
    }

    private struct PreviewKey: Hashable {
        let accountId: String?
        let retry: Int
        let publicationRevision: Int
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let selected = session.selectedPlayer {
                    Section("Selected profile") {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.fill")
                                .accessibilityHidden(true)
                            Text(selected.displayName)
                                .accessibilityIdentifier("fst.profile.selected")
                        }
                        .foregroundStyle(BrandTokens.textPrimary)
                        Button("Deselect Profile", role: .destructive) {
                            deselectPending = true
                        }
                        .tint(BrandTokens.textPrimary)
                        .accessibilityIdentifier("fst.profile.deselect")
                    }
                }
                if viewed == nil {
                    Section("Find a profile") {
                        Picker("Search profiles", selection: $scope) {
                            ForEach(ProfileSearchScope.allCases) { target in
                                Text(target.label).tag(target)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("fst.profile.scope")
                        if scope == .players {
                            TextField(
                                "", text: $query,
                                prompt: Text("Search players")
                                    .foregroundStyle(BrandTokens.textSecondary)
                            )
                            .textFieldStyle(.roundedBorder)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .onSubmit { searchFocused = false }
                            .accessibilityLabel("Search players")
                            .accessibilityIdentifier("fst.profile.search")
                        } else {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "person.3")
                                    .accessibilityHidden(true)
                                Text("Band search is paused until the service can read without "
                                    + "rebuilding membership data.")
                                    .accessibilityIdentifier("fst.profile.bands-unavailable")
                            }
                            .foregroundStyle(BrandTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if scope == .players {
                    if let viewed {
                        viewedSection(viewed)
                    } else {
                        resultsSection
                    }
                }
                if let selectionError {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .accessibilityHidden(true)
                            Text(selectionError)
                                .accessibilityIdentifier("fst.profile.selection-error")
                        }
                        .foregroundStyle(BrandTokens.gold)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BrandTokens.appBackground)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    Text("Profiles")
                        .font(.title2.bold())
                        .foregroundStyle(BrandTokens.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button {
                        dismiss()
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "xmark")
                                .font(.body)
                                .foregroundStyle(BrandTokens.textPrimary)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(BrandTokens.cardBackground, in: Capsule())
                        } else {
                            Label("Close", systemImage: "xmark")
                                .font(.body)
                                .foregroundStyle(BrandTokens.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(BrandTokens.cardBackground, in: Capsule())
                        }
                    }
                    .buttonStyle(HighContrastPagerStyle())
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("fst.profile.close")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(BrandTokens.appBackground)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewed != nil {
                    previewFooter
                }
            }
        }
        .onChange(of: query) { _, _ in
            searchPhase = .enterQuery
            viewed = nil
            selectionError = nil
        }
        .onChange(of: scope) { _, _ in
            searchPhase = .enterQuery
            viewed = nil
            selectionError = nil
        }
        .onChange(of: viewed?.accountId) { _, _ in
            selectionError = nil
        }
        .task(id: SearchKey(query: query, scope: scope, retry: searchRetry)) {
            await search()
        }
        .task(id: PreviewKey(
            accountId: viewed?.accountId, retry: previewRetry,
            publicationRevision: session.publicationRevision
        )) {
            await loadViewedPlayer()
        }
        .confirmationDialog(
            "Switch selected profile?", isPresented: $switchPending,
            titleVisibility: .visible
        ) {
            Button("Switch Profile", role: .destructive) { selectViewedPlayer() }
        } message: {
            Text("Scores and profile-dependent pages will update to the new player.")
        }
        .confirmationDialog(
            "Deselect profile?", isPresented: $deselectPending,
            titleVisibility: .visible
        ) {
            Button("Deselect Profile", role: .destructive) {
                session.deselectPlayer()
                dismiss()
            }
        } message: {
            Text("Scores and profile-only content will be hidden; app Settings stay saved.")
        }
    }

    /// Keep Select/Retry and Back reachable without a Form row suppressing text scaling.
    private var previewFooter: some View {
        actionLayout {
            switch preview {
            case let .available(payload)
                where payload.publicationId == session.publicationId
                    && session.selectedPlayer?.accountId != viewed?.accountId:
                Button {
                    if session.selectedPlayer == nil {
                        selectViewedPlayer()
                    } else {
                        switchPending = true
                    }
                } label: {
                    Text("Select Profile")
                        .font(.body.bold())
                        .foregroundStyle(BrandTokens.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(BrandTokens.appBackground,
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(HighContrastPagerStyle())
                .accessibilityIdentifier("fst.profile.select")
            case .syncing, .failed:
                Button {
                    previewRetry += 1
                } label: {
                    Text("Retry Player Scores")
                        .font(.body.bold())
                        .foregroundStyle(BrandTokens.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(BrandTokens.appBackground,
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(HighContrastPagerStyle())
                .accessibilityIdentifier("fst.profile.preview-retry")
            case .loading, .available:
                EmptyView()
            }
            Button {
                viewed = nil
            } label: {
                Text("Back to Results")
                    .font(.body)
                    .foregroundStyle(BrandTokens.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(BrandTokens.appBackground,
                                in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(HighContrastPagerStyle())
            .accessibilityIdentifier("fst.profile.back")
        }
        .padding(12)
        .background(BrandTokens.cardBackground)
    }

    /// Keep a service failure separate from an empty account-search envelope.
    @ViewBuilder private var resultsSection: some View {
        Section("Players") {
            switch searchPhase {
            case .enterQuery:
                Text("Enter at least two characters to search for players.")
                    .foregroundStyle(BrandTokens.textSecondary)
            case .loading:
                ProgressView("Searching players")
                    .accessibilityIdentifier("fst.profile.search-loading")
            case let .results(results):
                if results.isEmpty {
                    Text("No player results were returned. Try another search or Retry.")
                        .foregroundStyle(BrandTokens.textSecondary)
                        .accessibilityIdentifier("fst.profile.search-empty")
                } else {
                    ForEach(results) { player in
                        Button {
                            viewed = player
                            preview = .loading
                            searchFocused = false
                        } label: {
                            Label(player.displayName, systemImage: "person.crop.circle")
                        }
                        .tint(BrandTokens.textPrimary)
                        .accessibilityLabel("View \(player.displayName)")
                        .accessibilityIdentifier("fst.profile.result.\(player.accountId)")
                    }
                }
            case let .failed(message):
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text("Player search unavailable: \(message)")
                        .accessibilityIdentifier("fst.profile.search-error")
                }
                .foregroundStyle(BrandTokens.gold)
            }
            switch searchPhase {
            case .failed:
                Button("Retry Player Search") { searchRetry += 1 }
                    .tint(BrandTokens.textPrimary)
                    .accessibilityIdentifier("fst.profile.search-retry")
            case let .results(results) where results.isEmpty:
                Button("Retry Player Search") { searchRetry += 1 }
                    .tint(BrandTokens.textPrimary)
                    .accessibilityIdentifier("fst.profile.search-retry")
            case .enterQuery, .loading, .results:
                EmptyView()
            }
        }
    }

    /// Display a viewed identity before offering an independent Select action.
    ///
    /// - Parameter player: Search result whose detail request is in flight or validated.
    /// - Returns: Preview, error, syncing and explicit action states.
    private func viewedSection(_ player: PlayerSearchResult) -> some View {
        Section("Viewing player") {
            Text(player.displayName)
                .font(.headline)
                .foregroundStyle(BrandTokens.textPrimary)
                .accessibilityIdentifier("fst.profile.viewed")
            switch preview {
            case .loading:
                ProgressView("Loading public scores")
            case let .available(payload):
                Text("\(payload.profile.totalScores) public scores available")
                    .foregroundStyle(BrandTokens.textSecondary)
                    .accessibilityIdentifier("fst.profile.score-count")
                if payload.profile.totalScores == 0 {
                    Text("No public scores were returned. Registration status is unknown.")
                        .foregroundStyle(BrandTokens.textSecondary)
                        .accessibilityIdentifier("fst.profile.empty-status")
                }
                if payload.publicationId == nil {
                    Text("These scores have no verified publication. Selection is paused.")
                        .foregroundStyle(BrandTokens.gold)
                        .accessibilityIdentifier("fst.profile.unverified")
                } else if payload.publicationId != session.publicationId {
                    Text("Published scores changed. Refreshing this preview before selection.")
                        .foregroundStyle(BrandTokens.gold)
                        .accessibilityIdentifier("fst.profile.preview-changed")
                } else if session.selectedPlayer?.accountId == player.accountId {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .accessibilityHidden(true)
                        Text("Already selected")
                    }
                    .foregroundStyle(BrandTokens.textPrimary)
                }
            case .syncing:
                Text("Public scores are syncing. Try again before selecting this player.")
                    .foregroundStyle(BrandTokens.textSecondary)
                    .accessibilityIdentifier("fst.profile.syncing")
            case let .failed(message):
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text("Player scores unavailable: \(message)")
                        .accessibilityIdentifier("fst.profile.preview-error")
                }
                .foregroundStyle(BrandTokens.gold)
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

    /// Read real status separately from a search hit without silently selecting it.
    private func loadViewedPlayer() async {
        guard let viewed else { return }
        preview = .loading
        do {
            let payload = try await session.viewPlayer(viewed)
            try Task.checkCancellation()
            preview = payload.state == .syncing ? .syncing : .available(payload)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            preview = .failed(error.localizedDescription)
        }
    }

    /// Apply only the current viewed, publication-proven player on user confirmation.
    private func selectViewedPlayer() {
        guard let viewed, case let .available(payload) = preview else {
            selectionError = FestivalAPIError.invalidPlayerProfile.localizedDescription
            return
        }
        do {
            try session.selectPlayer(viewed, from: payload)
            dismiss()
        } catch {
            selectionError = error.localizedDescription
        }
    }
}
