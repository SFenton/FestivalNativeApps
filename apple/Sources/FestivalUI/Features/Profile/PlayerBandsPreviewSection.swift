import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerBandsPreviewSection

/// The player profile's inline "{name}'s Bands" section (issue #312), porting the web
/// client's `buildPlayerBandsItems`
/// (`FortniteFestivalWeb/src/pages/player/components/PlayerBandsSection.tsx`): a section
/// title with View All, then Duos, Trios and Quads, each one card of up to six band rows
/// ending with the purple "View All Bands (N)" when the group has more (owner #596), or a
/// "No Bands Yet" card when empty.
///
/// The section loads on its own (``FestivalSession/playerBandsPreview(accountId:)``,
/// three keyless player-bands reads), so the rest of the profile never waits for it:
/// HIG Loading, "Keep it usable while loading". A failure stays inside the section with
/// its own Retry (HIG Writing, "Show errors as close to the problem as possible").
struct PlayerBandsPreviewSection: View {
    let session: FestivalSession
    let accountId: String
    /// Name shown in the title ("SFentonX's Bands").
    let displayName: String
    /// Name passed to the Player Bands list title, nil when the route has none.
    let routeDisplayName: String?

    /// The preview read's states.
    enum Phase {
        case loading
        case failed(ServiceIssue)
        case loaded(PlayerBandsPreview)
    }

    private struct LoadKey: Hashable {
        let accountId: String
        let retry: Int
        let publicationRevision: Int
    }

    @State private var phase: Phase
    @State private var retryRevision = 0
    /// `LoadKey` whose read succeeded. `.task(id:)` restarts on every reappearance (Back
    /// from Player Bands or a band), which must not reset the loaded cards to a spinner.
    @State private var loadedKey: LoadKey?
    @Environment(\.deviceLayout) private var layout

    /// Create the section.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - accountId: Viewed account.
    ///   - displayName: Name for the section title.
    ///   - routeDisplayName: Name for the pushed Player Bands title.
    ///   - phase: Initial state; tests pass a loaded preview to skip the read.
    init(
        session: FestivalSession, accountId: String, displayName: String, routeDisplayName: String?,
        phase: Phase = .loading
    ) {
        self.session = session
        self.accountId = accountId
        self.displayName = displayName
        self.routeDisplayName = routeDisplayName
        _phase = State(initialValue: phase)
    }

    private var loadKey: LoadKey {
        LoadKey(accountId: accountId, retry: retryRevision, publicationRevision: session.publicationRevision)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch phase {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading bands")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("fst.player.bands.loading")
            case let .failed(issue):
                FestivalGlassSection {
                    ServiceStatusInline(issue, scope: "player.bands", fallbackTitle: "Bands unavailable") {
                        retryRevision += 1
                    }
                }
                .accessibilityIdentifier("fst.player.bands.error")
            case let .loaded(preview):
                groups(preview)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.contain` first, or the identifier replaces every card's own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.player.bands")
        // On the whole section so the Bands Quick Link lands on its title.
        .quickLinkSection(id: "bands", title: "Bands", symbol: "person.3.fill")
        .task(id: loadKey) {
            guard loadedKey != loadKey else { return }
            let key = loadKey
            if case .loaded = phase, loadedKey == nil, retryRevision == 0 {
                loadedKey = key
                return
            }
            if await load(resetting: loadedKey?.accountId != key.accountId), !Task.isCancelled {
                loadedKey = key
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            FestivalSectionHeader("\(displayName)'s Bands")
            SectionViewAllLink(
                route: .playerBands(accountId: accountId, displayName: routeDisplayName ?? displayName),
                identifier: "fst.player.bands-link",
                listName: "\(displayName)'s Bands"
            )
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Groups

    /// The group's "View All Bands (N)" label.
    ///
    /// - Parameter group: The previewed band group.
    /// - Returns: The visible label with the group's total.
    static func viewAllTitle(_ group: PlayerBandsPreview.Group) -> String {
        "View All Bands (\(group.totalCount.formatted()))"
    }

    /// Duos, Trios and Quads: stacked, or in the profile's two instrument-tile columns
    /// on a regular-width window (`.agents/design/apple/duo.md`, hinge-columns R8).
    @ViewBuilder
    private func groups(_ preview: PlayerBandsPreview) -> some View {
        if layout.widthClass == .regular {
            HingeGrid(
                columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)],
                alignment: .leading, spacing: 20
            ) {
                ForEach(preview.groups) { group in
                    groupSection(group)
                }
            }
        } else {
            ForEach(preview.groups) { group in
                groupSection(group)
            }
        }
    }

    @ViewBuilder
    private func groupSection(_ group: PlayerBandsPreview.Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.group.label)
                .font(.title3.bold())
                .foregroundStyle(FestivalText.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fst.player.bands.group.\(group.group.rawValue)")
            if group.entries.isEmpty {
                emptyCard(group.group)
            } else {
                // Owner #596: one card of band rows with hairlines, ending with the
                // purple View All inside it, like Song Detail's band previews and the
                // Rivals cards (surface-materials R8, view-all-cta R1). The rows read
                // `festivalGroupedRow` and drop their own card; the group header already
                // names the size, so the rows carry no Duos/Trios/Quads chip.
                FestivalGlassSection(rows: .flush(separatorInset: 12)) {
                    ForEach(group.entries) { entry in
                        PlayerBandRow(entry: entry)
                    }
                } action: {
                    if group.hasMore {
                        PurpleActionLink(
                            title: Self.viewAllTitle(group),
                            route: .playerBands(
                                accountId: accountId, displayName: routeDisplayName ?? displayName,
                                group: group.group
                            ),
                            identifier: "fst.player.bands.view-all.\(group.group.rawValue)",
                            card: group.group.label
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("fst.player.bands.card.\(group.group.rawValue)")
                .festivalFadeInOnAppear()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // In two columns, VoiceOver reads a whole group (heading, rows, View All)
        // before the group beside it.
        .accessibilityElement(children: .contain)
    }

    /// Web `InstrumentEmptyState` (`player.noBandsTitle`/`player.noBandsSubtitle`):
    /// a scoped title and next step on the shared card, never a failure.
    private func emptyCard(_ group: PlayerBandGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No Bands Yet")
                .font(.headline)
                .foregroundStyle(BrandTokens.textPrimary)
            Text("Band lineups will appear here once this player posts band scores.")
                .font(.subheadline)
                .foregroundStyle(FestivalText.primary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(14)
        .festivalCard(cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fst.player.bands.empty.\(group.rawValue)")
        .festivalFadeInOnAppear()
    }

    // MARK: - Loading

    /// Read the three group previews.
    ///
    /// - Parameter resetting: Show the spinner first (a different account); a reload for
    ///   the same account keeps the shown cards until the new ones arrive.
    /// - Returns: Whether the read succeeded.
    private func load(resetting: Bool) async -> Bool {
        if resetting {
            phase = .loading
        } else if case .failed = phase {
            // Retry: replace the message with the spinner (empty-error-states R6).
            phase = .loading
        }
        do {
            let preview = try await session.playerBandsPreview(accountId: accountId)
            try Task.checkCancellation()
            phase = .loaded(preview)
            return true
        } catch is CancellationError {
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            phase = .failed(ServiceIssue(error))
            return false
        }
    }
}
