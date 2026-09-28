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
    @State private var replayPage: FirstRunPageKey?

    /// Create the section.
    ///
    /// - Parameter session: Shared app session (first-run coordinator + seen-state store).
    init(session: FestivalSession) {
        self.session = session
    }

    var body: some View {
        FestivalGlassSection(
            "First Run Guides", subtitle: "Re-visit the first run experience for each page."
        ) {
            ForEach(Self.settingsOrder) { page in
                Button { openReplay(page) } label: {
                    HStack {
                        SettingLabel(Self.rowLabel(page))
                        Spacer(minLength: 8)
                        Text("Show")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrandTokens.accentBlue)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fst.settings.first-run.\(page.rawValue)")
                .accessibilityHint("Shows every first-run guide slide for \(Self.rowLabel(page))")
            }
        }
        .sheet(item: $replayPage) { page in
            let slides = FirstRunSlideEvaluator.allSlides(FirstRunCatalog.slides(for: page))
            FirstRunCarouselView(page: page, slides: slides) {
                session.firstRunCenter.store.markSeen(slides)
                replayPage = nil
            }
        }
    }

    /// Row order of the web Settings page (`SettingsPage.tsx:756-810`), which lists Statistics
    /// and Suggestions before Score History.
    static let settingsOrder: [FirstRunPageKey] = [
        .songs, .songInfo, .statistics, .suggestions, .playerHistory,
        .leaderboards, .compete, .rivals, .shop,
    ]

    /// Row label: the web's nav titles, where Player History is titled "Score History"
    /// (`history.title`).
    ///
    /// - Parameter page: Registered page.
    /// - Returns: Title Case row label.
    static func rowLabel(_ page: FirstRunPageKey) -> String {
        page == .playerHistory ? "Score History" : page.label
    }

    /// Reset the page's seen-state (matching the web's `open()` calling `resetPage` first) and
    /// present its full, ungated slide catalog.
    ///
    /// - Parameter page: Page to replay.
    private func openReplay(_ page: FirstRunPageKey) {
        let slides = FirstRunCatalog.slides(for: page)
        session.firstRunCenter.store.resetPage(slides.map(\.id))
        replayPage = page
    }
}
