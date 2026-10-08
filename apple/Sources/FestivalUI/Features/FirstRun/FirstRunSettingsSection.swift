import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Settings section

/// The Settings "First Run Guides" section: one "Show" row per registered page that replays its
/// *entire* slide catalog, ignoring gates and seen-state — ported from the web's
/// `useFirstRunReplay`/`getAllSlides` pair used by `SettingsPage.tsx`.
///
/// Self-contained so the Settings lane only needs to add one call site inside
/// `SettingsScreen.swift`; this file owns its own state and sheet presentation.
struct FirstRunSettingsSection: View {
    let session: FestivalSession
    /// False on the list/detail Settings' First Run Guides page (issue #371).
    let titled: Bool
    @State private var replayPage: FirstRunPageKey?
    /// Page of the replay being shown (kept after `replayPage` clears, for `onDismiss`).
    @State private var lastReplayed: FirstRunPageKey?
    @State private var viewing = FirstRunViewing(slides: [])

    /// Create the section.
    ///
    /// - Parameters:
    ///   - session: Shared app session (first-run coordinator + seen-state store).
    ///   - titled: Show the section title (false on its own list/detail page).
    init(session: FestivalSession, titled: Bool = true) {
        self.session = session
        self.titled = titled
    }

    var body: some View {
        SettingsSectionCard(
            "First Run Guides", subtitle: "Re-visit the first run experience for each page.",
            titled: titled
        ) {
            ForEach(Self.settingsOrder) { page in
                HStack {
                    SettingLabel(Self.rowLabel(page))
                    Spacer(minLength: 8)
                    // The web's blue `btnPrimary` "Show" button; no slide counts.
                    Button { openReplay(page) } label: {
                        Text("Show")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AccentText.prominentFill)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Show \(Self.rowLabel(page)) guide")
                    .accessibilityIdentifier("fst.settings.first-run.\(page.rawValue)")
                    .accessibilityHint("Shows every first-run guide slide for \(Self.rowLabel(page))")
                }
            }
        }
        .sheet(item: $replayPage, onDismiss: finishReplay) { page in
            FirstRunCarouselView(page: page, slides: Self.replaySlides(page), viewing: $viewing) {
                replayPage = nil
            }
            .environment(\.firstRunSession, session)
        }
    }

    /// Every slide for a page, ignoring gates and seen-state (`getAllSlides`).
    ///
    /// - Parameter page: Page to replay.
    /// - Returns: The page's full catalog.
    static func replaySlides(_ page: FirstRunPageKey) -> [FirstRunSlide] {
        FirstRunSlideEvaluator.allSlides(FirstRunCatalog.slides(for: page))
    }

    /// Row order of the web Settings page (`SettingsPage.tsx:756-810`), which lists Statistics
    /// and Suggestions before Score History.
    static let settingsOrder: [FirstRunPageKey] = [
        .songs, .songInfo, .statistics, .suggestions, .playerHistory,
        .leaderboards, .compete, .rivals, .shop,
    ]

    /// Row label: the page's ``FirstRunPageKey/guideTitle``, the same title its replayed guide
    /// shows in the navigation bar.
    ///
    /// - Parameter page: Registered page.
    /// - Returns: Title Case row label.
    static func rowLabel(_ page: FirstRunPageKey) -> String {
        page.guideTitle
    }

    /// Reset the page's seen-state (matching the web's `open()` calling `resetPage` first) and
    /// present its full, ungated slide catalog.
    ///
    /// - Parameter page: Page to replay.
    private func openReplay(_ page: FirstRunPageKey) {
        let slides = FirstRunCatalog.slides(for: page)
        session.firstRunCenter.store.resetPage(slides.map(\.id))
        viewing = FirstRunViewing(slides: Self.replaySlides(page))
        lastReplayed = page
        replayPage = page
    }

    /// Mark only the replayed pages that were actually shown, however the sheet closed.
    private func finishReplay() {
        guard let page = lastReplayed else { return }
        lastReplayed = nil
        session.firstRunCenter.store.markSeen(viewing.seenSlides(Self.replaySlides(page)))
    }
}
