import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - NotificationsSheet

/// Native port of the web's `MobileNotificationsModal`
/// (`FortniteFestivalWeb/src/components/notifications/MobileNotificationsModal.tsx`).
///
/// **Navigation — dismiss the sheet, then show the page in the app** (web
/// `App.tsx` `handleNotificationOpen`, issue #75): a row with a destination places its
/// page on the presenting tab's stack through ``openRoute`` and dismisses the sheet.
/// The sheet has no stack of its own to push into (HIG Modality: avoid "an app within
/// the app"). Rows port the web's player-scoped presentation, including coalesced events
/// (issue #76); band grouping and the media-cycle animation are not ported natively —
/// see `.agents/controls/notifications/spec.md`.
struct NotificationsSheet: View {
    let session: FestivalSession
    /// Pushes a route on the presenting tab's stack. A plain closure parameter, **not**
    /// an environment action: a custom `@Entry` value set by the presenter does not
    /// reliably reach a sheet's content (see `ProfileSelectionSheet.openRoute`).
    /// Defaults to a no-op for hosted tests.
    var openRoute: (AppRoute) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    /// A tapped row is resolving its destination; further taps wait for it.
    @State private var opening = false
    /// The first reveal's stagger has finished; rows rebuilt later (List recycling while
    /// scrolling back up) appear without fading again (operator batch 7).
    @State private var fadeSettled = false
    /// Pinned header and scroll readings for the rows' fade under the headers (#301).
    @State private var pinnedFade = ModalPinnedHeaderFadeState()
    private var center: NotificationsCenter { session.notificationsCenter }

    var body: some View {
        FestivalModal("Notifications", closeIdentifier: "fst.notifications.close") {
            content
        }
        .task { await center.refresh(session: session) }
        .onDisappear {
            center.markSeen(center.notifications.map(\.id))
        }
    }

    @ViewBuilder private var content: some View {
        switch (session.selectedPlayer, center.state) {
        case (nil, _):
            ContentUnavailableView(
                "Choose a Profile", systemImage: "person.crop.circle",
                description: Text("Select a profile to see your notifications.")
            )
        case (_, .loading), (_, .idle):
            FestivalLoadingView(accessibilityLabel: "Loading Notifications")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let (_, .failed(issue)):
            ServiceStatusView(issue, title: "Notifications unavailable") {
                Task { await center.refresh(session: session) }
            }
        case (_, .loaded):
            if center.notifications.isEmpty {
                NotificationsEmptyState(isGenerated: center.isGenerated)
            } else {
                list
            }
        }
    }

    private var list: some View {
        let unread = center.notifications.filter { center.unreadIds.contains($0.id) }
        let older = center.notifications.filter { !center.unreadIds.contains($0.id) }
        return List {
            if !unread.isEmpty {
                Section { rows(unread) } header: { sectionHeader("New", first: true) }
            }
            if !older.isEmpty || unread.isEmpty {
                Section { rows(older, offset: unread.count) } header: {
                    if !unread.isEmpty { sectionHeader("Older", first: false) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .modalPinnedHeaderList(pinnedFade, showsHeaders: !unread.isEmpty)
        .task(id: center.notifications.count) {
            await FadeStagger.settle(afterRevealing: min(center.notifications.count, 12)) {
                fadeSettled = true
            }
        }
    }

    /// White section title ("New" / "Older", operator batch 7), measured for the rows'
    /// fade under it while pinned; the first is drawn where it pins from the start (#301).
    private func sectionHeader(_ title: String, first: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FestivalText.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
            .modalPinnedSectionHeader(pinnedFade, first: first)
    }

    @ViewBuilder
    private func rows(_ notifications: [AppNotification], offset: Int = 0) -> some View {
        ForEach(Array(notifications.enumerated()), id: \.element.id) { index, notification in
            Button {
                Task { await open(notification) }
            } label: {
                NotificationRow(
                    notification: notification, isUnread: center.unreadIds.contains(notification.id),
                    session: session
                )
            }
            .festivalRowButtonStyle()
            .festivalFadeIn(isLoaded: true, index: FadeStagger.index(offset + index, settled: fadeSettled))
            .modalPinnedHeaderRow(pinnedFade, first: offset == 0 && index == 0)
            .accessibilityIdentifier("fst.notifications.row.\(notification.id)")
        }
    }

    /// Mark the tapped row seen; when it has a destination, show that page in the app
    /// and dismiss the sheet.
    ///
    /// The page is placed on the presenting tab's stack without a push animation, under
    /// the sheet, and the sheet's own dismissal reveals it: one system transition (the
    /// same choice as `ProfileSelectionSheet.openPlayer`). A row without a destination,
    /// or whose song is no longer in the catalogue, keeps the sheet open.
    ///
    /// - Parameter notification: Row that was tapped.
    private func open(_ notification: AppNotification) async {
        center.markSeen([notification.id])
        guard !opening else { return }
        opening = true
        defer { opening = false }
        guard let route = await NotificationRoute.resolve(
            notification.destination, song: { try await session.song(songId: $0) }
        ) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { openRoute(route) }
        dismiss()
    }
}

// MARK: - Route resolution

/// Maps a notification's destination to the app route the main navigation shows
/// (web `notificationDestination.ts` → `App.tsx` `handleNotificationOpen`).
enum NotificationRoute {
    /// Resolve the route for a tapped row.
    ///
    /// - Parameters:
    ///   - destination: The row's destination; nil for rows that do not navigate.
    ///   - song: Looks a song up in the current catalogue by ID.
    /// - Returns: Song Detail for a song row, Full Rankings for a rank row with an
    ///   instrument, the Leaderboards hub for one without, or nil when the row does not
    ///   navigate or its song cannot be found.
    @MainActor static func resolve(
        _ destination: AppNotificationDestination?,
        song: (String) async throws -> Song?
    ) async -> AppRoute? {
        switch destination {
        case nil:
            return nil
        case let .song(songId, _):
            guard let found = try? await song(songId) else { return nil }
            return .songDetail(found)
        case let .rankings(instrument?, metric):
            return .fullRankings(instrument: instrument, rankBy: metric.rawValue)
        case .rankings(nil, _):
            return .leaderboards
        }
    }
}

// MARK: - Empty state

/// Matches `notifications.empty.*` copy from the web's `en.json`.
struct NotificationsEmptyState: View {
    let isGenerated: Bool

    var body: some View {
        ContentUnavailableView(
            "No notifications available", systemImage: "bell.slash",
            description: Text(isGenerated
                ? "Notifications will appear here when new high scores are set or "
                    + "global ranks improve. Set new high scores and compete with friends to see them!"
                : "Notifications may appear here after the next leaderboard update. Set new "
                    + "high scores and compete with friends to see them!")
        )
        .accessibilityIdentifier("fst.notifications.empty")
    }
}

// MARK: - Row

/// One notification row, ported from the web's `NotificationRow`
/// (`MobileNotificationsModal.tsx`): a leading media rail, the title, the message with
/// bold runs, colour-coded flag chips (or per-instrument flag lines when the row touched
/// several charts), and the trailing unread dot / chevron column.
///
/// Artwork and icons are decorative (hidden from VoiceOver); the row reads as one element,
/// "title. message", followed by the flag labels so flag meaning never depends on colour.
struct NotificationRow: View {
    let notification: AppNotification
    let isUnread: Bool
    let session: FestivalSession
    /// Web `UNREAD_DOT_COLOR` (#FACC15).
    static let unreadDot = Color(.sRGB, red: 250 / 255, green: 204 / 255, blue: 21 / 255)

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            NotificationMediaRail(media: notification.media, session: session)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(notification.title)
                    .font(.headline)
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                Text(Self.message(notification.messageParts))
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
                    .fixedSize(horizontal: false, vertical: true)
                NotificationFlags(notification: notification)
            }
            Spacer(minLength: 0)
            // Web trailing column: 20pt wide, the chevron centred vertically and the
            // unread dot centred 24pt above it (`trailingAction` / `unreadDot`).
            if isUnread || notification.destination != nil {
                ZStack {
                    if notification.destination != nil {
                        Image(systemName: "chevron.forward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FestivalText.primary.opacity(0.72))
                    }
                    if isUnread {
                        Circle()
                            .fill(Self.unreadDot)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(BrandTokens.surfaceSubtle, lineWidth: 2))
                            .offset(y: -24)
                    }
                }
                .frame(width: 20)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(notification))
        .accessibilityAddTraits(notification.destination != nil ? .isButton : [])
    }

    /// Message runs as one attributed string; emphasized runs are strongly emphasized
    /// (bold) so they keep the row's Dynamic Type text style.
    ///
    /// - Parameter parts: Plain and emphasized runs from `NotificationText`.
    /// - Returns: Attributed message text.
    static func message(_ parts: [NotificationMessagePart]) -> AttributedString {
        parts.reduce(into: AttributedString()) { result, part in
            var run = AttributedString(part.text)
            if part.emphasis { run.inlinePresentationIntent = .stronglyEmphasized }
            result += run
        }
    }

    /// Spoken row: the web's "title. message", then each flag by name.
    ///
    /// - Parameter notification: Row content.
    /// - Returns: VoiceOver label for the combined row.
    static func accessibilityLabel(_ notification: AppNotification) -> String {
        let flags = notification.flagGroups.isEmpty
            ? notification.flags.map(\.label).joined(separator: ", ")
            : notification.flagGroups.map(\.accessibilityLabel).joined(separator: ". ")
        return flags.isEmpty ? notification.accessibilityLabel : "\(notification.accessibilityLabel) \(flags)."
    }
}

// MARK: - Media rail

/// The 64pt leading media column (web `NotificationMediaRail`): 54pt album art, 44pt art
/// above a two-column grid of 18pt instrument icons for multi-chart rows, or a 36pt
/// instrument icon when there is no art. Decorative.
struct NotificationMediaRail: View {
    let media: NotificationMedia
    let session: FestivalSession

    var body: some View {
        Group {
            switch media {
            case let .song(albumArt):
                ArtworkTile(raw: albumArt, session: session, size: 54)
                    .id(albumArt)
            case let .songInstrumentGrid(albumArt, instruments):
                VStack(spacing: 4) {
                    ArtworkTile(raw: albumArt, session: session, size: 44)
                        .id(albumArt)
                    InstrumentIconGrid(instruments: instruments)
                }
            case let .soloInstrument(instrument):
                InstrumentIcon(instrument, size: 36)
            }
        }
        .frame(width: 64)
        .frame(minHeight: 64)
    }
}

/// Two-column grid of 18pt instrument icons, 3pt apart (web `songInstrumentGrid`).
private struct InstrumentIconGrid: View {
    let instruments: [Instrument]
    private let icon: CGFloat = 18

    var body: some View {
        let rows = stride(from: 0, to: instruments.count, by: 2).map {
            Array(instruments[$0..<min($0 + 2, instruments.count)])
        }
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: 3) {
                    ForEach(row) { InstrumentIcon($0, size: icon) }
                    if row.count == 1 { Color.clear.frame(width: icon, height: icon) }
                }
            }
        }
    }
}

// MARK: - Flags

/// Web `NotificationFlags`: per-instrument flag lines for multi-chart rows, else one
/// wrapping line of chips.
private struct NotificationFlags: View {
    let notification: AppNotification

    var body: some View {
        if !notification.flagGroups.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(notification.flagGroups) { group in
                    HStack(alignment: .center, spacing: 4) {
                        InstrumentIcon(group.instrument, size: 20)
                        NotificationChipFlow(spacing: 4) {
                            ForEach(group.flags, id: \.self) { NotificationFlagChip(kind: $0) }
                        }
                    }
                }
            }
        } else if !notification.flags.isEmpty {
            NotificationChipFlow(spacing: 4) {
                ForEach(notification.flags, id: \.self) { NotificationFlagChip(kind: $0) }
            }
        }
    }
}

/// One flag pill: the web label in white semibold on its `FLAG_COLORS` fill with a
/// translucent white border. Every fill keeps white text above 4.5:1 contrast.
struct NotificationFlagChip: View {
    let kind: NotificationFlagKind

    var body: some View {
        Text(kind.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Self.color(kind), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 2)
            )
            .fixedSize()
    }

    /// Web `FLAG_COLORS` (`MobileNotificationsModal.tsx`).
    ///
    /// - Parameter kind: Flag kind.
    /// - Returns: The chip fill.
    static func color(_ kind: NotificationFlagKind) -> Color {
        let hex: UInt32 = switch kind {
        case .improvement: 0x4B5563
        case .firstPlay: 0x6D28D9
        case .newHighScore: 0x0F766E
        case .fullCombo: 0x7C2D12
        case .rankUp: 0x1D4ED8
        case .goldStars: 0x92400E
        case .starsUp: 0xBE123C
        case .difficultyUp: 0x047857
        case .progress: 0x4338CA
        }
        return Color(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Wraps chips onto as many lines as the width needs (web `flex-wrap: wrap`), so larger
/// Dynamic Type sizes stack chips instead of truncating them.
struct NotificationChipFlow: Layout {
    var spacing: CGFloat

    /// - Parameters:
    ///   - proposal: Offered width; unbounded lays everything on one line.
    ///   - subviews: Chips.
    ///   - cache: Unused.
    /// - Returns: The wrapped lines' bounding size.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    /// - Parameters:
    ///   - bounds: Assigned rectangle.
    ///   - proposal: Offered size.
    ///   - subviews: Chips.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, width: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Greedy line breaking, each chip at its ideal size.
    ///
    /// - Parameters:
    ///   - subviews: Chips.
    ///   - width: Available line width.
    /// - Returns: One frame per chip, relative to the layout origin.
    func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        Self.arrange(subviews.map { $0.sizeThatFits(.unspecified) }, width: width, spacing: spacing)
    }

    /// Greedy line breaking over measured sizes (unit-testable).
    ///
    /// - Parameters:
    ///   - sizes: Ideal chip sizes, in order.
    ///   - width: Available line width.
    ///   - spacing: Gap between chips and between lines.
    /// - Returns: One frame per size; a chip wider than the line gets a line to itself.
    static func arrange(_ sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}
