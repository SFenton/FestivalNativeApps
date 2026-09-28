import Foundation

// MARK: - Manual content

/// One expandable topic inside a `ManualSection` (`ManualPage.tsx`'s `ManualSubsection`).
struct ManualSubsection: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
}

/// One top-level topic in the App Manual (`ManualPage.tsx`'s `MANUAL_SECTIONS`).
struct ManualSection: Identifiable, Hashable {
    let id: String
    let title: String
    /// SF Symbol standing in for the web's screenshot carousel until real captures land.
    let symbol: String
    let intro: String
    let context: String
    let subsections: [ManualSubsection]
}

/// Ported copy from `FortniteFestivalWeb/src/i18n/appManual.en.json`.
///
/// TODO(orchestrator): the web shows a captured PNG/WebP screenshot carousel per section
/// and subsection (`ManualPage.tsx:394-509`, `manualScreenshotAssets.generated.ts`). This
/// native pass intentionally ships text and SF Symbol illustrations only — bundling or
/// generating equivalent native screenshots is a follow-up decision (asset licensing /
/// where the captures come from is outside a single lane's call).
enum ManualContent {
    static let sections: [ManualSection] = [
        ManualSection(
            id: "navigation", title: "Navigation Basics", symbol: "safari",
            intro: "Navigation changes depending on screen size and selected profile. The "
                + "sidebar, mobile header, bottom navigation, and floating action button all "
                + "point to the same app areas, but each layout keeps common actions close "
                + "to your thumb or cursor.",
            context: "Songs, Leaderboards, Item Shop, App Manual, and App Settings are "
                + "available from primary navigation. Suggestions and Statistics appear "
                + "once a player or band profile is active, while Rivals appears only for "
                + "a selected solo player.",
            subsections: [
                ManualSubsection(
                    id: "navigation-sidebar", title: "Sidebar And Desktop Rail",
                    body: "On wider screens, the pinned sidebar keeps the main app areas "
                        + "visible while the right-side rail can hold page quick links. The "
                        + "App Manual link sits below the profile area and above Settings "
                        + "so help stays close to account context without crowding the "
                        + "main feature links."
                ),
                ManualSubsection(
                    id: "navigation-mobile-actions", title: "Mobile Header And Floating Actions",
                    body: "On phones, the top header focuses on the current page title and "
                        + "the bottom navigation keeps high-frequency destinations "
                        + "reachable. The floating action button changes by page, opening "
                        + "search, filters, page quick links, or profile actions when those "
                        + "controls are relevant."
                ),
                ManualSubsection(
                    id: "navigation-quick-links", title: "Quick Links",
                    body: "Pages with long scrolling content expose quick links so you can "
                        + "jump directly to the part you need. In this manual, parent "
                        + "sections and nested subsections both appear in Quick Links, with "
                        + "subsections indented under their parent topic."
                ),
            ]
        ),
        ManualSection(
            id: "songs", title: "Songs Page", symbol: "music.note.list",
            intro: "The Songs page is the main browsing surface for tracks, score "
                + "progress, metadata, and profile-specific opportunities. It works well "
                + "as a full catalog when no profile is selected and becomes a personal or "
                + "band progress list after you choose a profile.",
            context: "Search, sorting, filtering, shop visibility, instrument settings, "
                + "and selected-profile data all shape what the list shows. The result "
                + "supports quick browsing, cleanup sessions, and targeted improvement "
                + "runs without forcing you into a separate view.",
            subsections: [
                ManualSubsection(
                    id: "songs-rows", title: "Rows And Visible Metadata",
                    body: "Song rows can show title, artist, season, intensity, "
                        + "difficulty, stars, score, percentile, accuracy, full-combo "
                        + "state, and shop state depending on your settings. Instrument "
                        + "icons and row ordering help you scan which parts matter before "
                        + "opening details."
                ),
                ManualSubsection(
                    id: "songs-profile-sorts", title: "Selected-Profile Data And Extra Sorts",
                    body: "When a player or band profile is selected, Songs can sort and "
                        + "filter by profile-aware fields such as scores, accuracy, stars, "
                        + "percentile, full-combo gaps, max-score distance, last played, "
                        + "missing scores, and band score state. These options make the "
                        + "same catalog behave like a tailored practice list."
                ),
                ManualSubsection(
                    id: "songs-search-sort-filter", title: "Search, Sort, And Filter",
                    body: "Search narrows the visible song list by title and artist. Sort "
                        + "controls change the order, while filters narrow by instruments, "
                        + "seasons, stars, percentile ranges, difficulty, shop state, "
                        + "missing scores, missing full combos, leeway, and selected-band "
                        + "conditions."
                ),
            ]
        ),
        ManualSection(
            id: "profiles", title: "Selecting Profiles", symbol: "person.2",
            intro: "Profiles decide which scores, suggestions, statistics, and navigation "
                + "options the app can show. You can browse without a profile, but "
                + "selecting one gives Songs and detail pages the context needed to "
                + "highlight personal progress or band progress.",
            context: "Player and band profiles intentionally affect the app differently. "
                + "Switching between those profile types resets song filters so the next "
                + "profile starts from a clean browsing state.",
            subsections: [
                ManualSubsection(
                    id: "profiles-player", title: "Player Profile Selection",
                    body: "Use Search or the profile action to select a solo player. A "
                        + "selected player unlocks personal song data, Player Details, "
                        + "solo Statistics, Suggestions, mobile Compete, and Rivals."
                ),
                ManualSubsection(
                    id: "profiles-band", title: "Band Profile Selection",
                    body: "Band profiles represent a selected team and band type. Once "
                        + "selected, Songs and Suggestions can focus on band performances, "
                        + "Band Details can show members and rank history, and Statistics "
                        + "points to the band page instead of solo player details."
                ),
                ManualSubsection(
                    id: "profiles-context", title: "Profile Context Across Pages",
                    body: "The selected profile follows you through Songs, Suggestions, "
                        + "Statistics, Leaderboards, and detail pages. Links preserve that "
                        + "context so score rows, filters, and comparison views stay "
                        + "focused on the profile you chose."
                ),
            ]
        ),
        ManualSection(
            id: "player-details", title: "Player Details", symbol: "chart.bar",
            intro: "Player Details gathers a selected player's progress into one "
                + "long-form view. It is built for scanning summary cards first, then "
                + "drilling into instrument sections, songs, bands, rank movement, and "
                + "history when you need more context.",
            context: "Most cards are navigational. Clicking a stat or song can move you "
                + "into Songs, song details, Leaderboards, or history while preserving "
                + "the selected player context.",
            subsections: [
                ManualSubsection(
                    id: "player-summary", title: "Summary And Statistic Cards",
                    body: "Summary cards highlight songs played, full combos, gold stars, "
                        + "average accuracy, best rank, and global statistic ranks when "
                        + "available. They provide the fastest read on a player's overall "
                        + "shape before you inspect individual instruments."
                ),
                ManualSubsection(
                    id: "player-instruments", title: "Instrument Sections And Graphs",
                    body: "Instrument sections break progress down by visible "
                        + "instruments. They can include ranked metrics, score history, "
                        + "rank history, percentile tables, and useful song links so you "
                        + "can understand both current strength and recent movement."
                ),
                ManualSubsection(
                    id: "player-navigation", title: "Top Songs, Bands, And Drilldowns",
                    body: "Top and bottom song groups, player bands, and card actions "
                        + "help you move from a high-level profile into the exact songs, "
                        + "teams, or rankings behind the numbers."
                ),
            ]
        ),
        ManualSection(
            id: "band-details", title: "Band Details", symbol: "person.3",
            intro: "Band Details focuses on a selected team's shared performance. It "
                + "shows who is in the band, what type of band it is, how the team "
                + "ranks, and which songs best explain the band's current position.",
            context: "Band pages keep member context visible so you can move between "
                + "team performance and individual player details without losing track "
                + "of the selected profile.",
            subsections: [
                ManualSubsection(
                    id: "band-members", title: "Members And Band Summary",
                    body: "The top of a band page identifies the band type, members, "
                        + "and selected-band context. Member rows link back to individual "
                        + "player details so you can inspect each player's contribution "
                        + "separately."
                ),
                ManualSubsection(
                    id: "band-rank-history", title: "Band Statistics And Rank History",
                    body: "Band statistics summarize the team's rank and rating while "
                        + "the rank-history graph shows how that position has changed "
                        + "over time. This is the fastest way to tell whether a band is "
                        + "climbing, holding, or slipping."
                ),
                ManualSubsection(
                    id: "band-songs", title: "Band Songs And Combo Context",
                    body: "Best and worst band songs show where the team has the "
                        + "strongest and weakest rankings. Band instrument filtering can "
                        + "focus the view on specific member-to-instrument assignments "
                        + "when a combo is selected."
                ),
            ]
        ),
        ManualSection(
            id: "song-detail", title: "Song Detail And Detail Cards", symbol: "waveform",
            intro: "Song Detail turns one track into a focused workspace. It gathers "
                + "metadata, scores, history, leaderboard previews, top performances, and "
                + "path access so you can inspect the song without losing the selected "
                + "profile context.",
            context: "Detail cards are designed for comparison. They show what the song "
                + "is, how hard each part is, where the selected profile stands, and "
                + "where to go next.",
            subsections: [
                ManualSubsection(
                    id: "song-detail-cards", title: "Song Header And Metadata Cards",
                    body: "The song header and cards group title, artist, album art, "
                        + "intensity, instrument difficulty, shop state, and "
                        + "selected-profile score information. The layout changes with "
                        + "screen size but keeps the song identity and main actions near "
                        + "the top."
                ),
                ManualSubsection(
                    id: "song-detail-leaderboards", title: "Leaderboard Previews And Score History",
                    body: "Leaderboard previews show top entries and selected-profile "
                        + "placement when available. Score history charts and lists help "
                        + "you see previous attempts, score changes, accuracy, stars, "
                        + "full-combo state, and dates for the selected song and "
                        + "instrument."
                ),
                ManualSubsection(
                    id: "song-detail-paths-history", title: "Paths And Player History",
                    body: "View Paths opens CHOpt path information as an image or text "
                        + "table according to App Settings. Player History gives a longer "
                        + "chronological view of score attempts and lets you sort the "
                        + "history data for easier comparison."
                ),
            ]
        ),
        ManualSection(
            id: "sync-history", title: "Sync Card And Post-Sync Data",
            symbol: "arrow.triangle.2.circlepath",
            intro: "When a player profile needs more history, the sync card explains "
                + "what the app is waiting on and gives you a visible progress point "
                + "inside Player Details. The card is about what you can see next, not "
                + "about technical internals.",
            context: "After sync completes, profile-aware views can show richer "
                + "history, graphs, recommendations, rank movement, and per-song "
                + "context.",
            subsections: [
                ManualSubsection(
                    id: "sync-card", title: "Sync Card",
                    body: "The sync card appears when a selected player is tracked or "
                        + "has pending profile data. It keeps progress visible from "
                        + "Player Details so you know whether to wait, browse other "
                        + "pages, or come back later."
                ),
                ManualSubsection(
                    id: "sync-after", title: "After Sync Completes",
                    body: "Once profile data is ready, the app can fill in more "
                        + "complete score history, personal bests, full-combo state, "
                        + "rank movement, and Suggestions context. The same pages become "
                        + "more useful without changing how you navigate them."
                ),
                ManualSubsection(
                    id: "sync-graphs", title: "Graphs, History, And Recommendations",
                    body: "Graphs and history views make progress visible over time, "
                        + "while Suggestions can use the completed profile context to "
                        + "surface missed songs, stale songs, percentile pushes, and "
                        + "other improvement groups."
                ),
            ]
        ),
        ManualSection(
            id: "suggestions", title: "Suggestions", symbol: "sparkles",
            intro: "Suggestions turns profile context into focused song groups. Instead "
                + "of browsing the whole catalog, you can start from categories that "
                + "point toward discovery, cleanup, improvement runs, and "
                + "profile-specific gaps.",
            context: "Suggestion filters are separate from normal Songs filters, so you "
                + "can explore recommended groups without disturbing your saved Songs "
                + "page setup.",
            subsections: [
                ManualSubsection(
                    id: "suggestions-solo", title: "Solo Suggestions",
                    body: "With a selected player, Suggestions can surface unplayed "
                        + "songs, stale songs, near-max-score songs, percentile pushes, "
                        + "artist groups, and rival-based ideas. Category cards act as "
                        + "launch points back into Songs."
                ),
                ManualSubsection(
                    id: "suggestions-band", title: "Band Suggestions",
                    body: "With a selected band profile, Suggestions focuses on the "
                        + "band's songs and available band context. This makes it easier "
                        + "to find team cleanup targets without mixing solo progress into "
                        + "the list."
                ),
                ManualSubsection(
                    id: "suggestions-filters", title: "Suggestion Filters And Category Cards",
                    body: "Suggestion filters narrow by instrument, category, and "
                        + "profile context. Category cards summarize why a group matters "
                        + "and take you directly to a filtered song list."
                ),
            ]
        ),
        ManualSection(
            id: "compete", title: "Compete", symbol: "iphone",
            intro: "Compete is a mobile-only hub for selected solo players. It groups "
                + "competitive entry points into a smaller surface so phones can jump "
                + "into Leaderboards and Rivals without requiring the wider desktop "
                + "layout.",
            context: "The Compete tab appears in bottom navigation when a solo player "
                + "profile is selected. Links from the hub preserve that player context "
                + "so ranking and rival views stay personal.",
            subsections: [
                ManualSubsection(
                    id: "compete-mobile-hub", title: "Mobile Compete Hub",
                    body: "The Compete hub is designed for phone navigation. It gives "
                        + "selected solo players a compact place to start competitive "
                        + "browsing without scrolling through desktop-oriented "
                        + "navigation."
                ),
                ManualSubsection(
                    id: "compete-leaderboards", title: "Leaderboards Entry Points",
                    body: "Leaderboards links from Compete can take you into ranking "
                        + "overviews and full ranking lists while keeping the selected "
                        + "player available for your-rank context."
                ),
                ManualSubsection(
                    id: "compete-rivals", title: "Rivals Entry Points",
                    body: "Rivals links from Compete lead into solo-player rival views, "
                        + "including song rivals and leaderboard neighbors. These views "
                        + "are only meaningful when a solo player profile is active."
                ),
            ]
        ),
        ManualSection(
            id: "leaderboards-rivals", title: "Leaderboards And Rivals", symbol: "trophy",
            intro: "Leaderboards compare ranked accounts and bands across instruments, "
                + "band types, combos, and ranking metrics. Rivals starts from a "
                + "selected solo player and narrows the comparison to nearby "
                + "competitors or shared songs.",
            context: "Use Leaderboards when you want broad ranking context. Use Rivals "
                + "when you want a more personal comparison around one selected solo "
                + "player.",
            subsections: [
                ManualSubsection(
                    id: "leaderboards-full", title: "Overview And Full Rankings",
                    body: "The Leaderboards overview groups solo instruments, band "
                        + "rankings, combo rankings, and rank-history context. Full "
                        + "ranking pages add paging, selected-player placement, metric "
                        + "controls, and instrument or scope switching."
                ),
                ManualSubsection(
                    id: "leaderboards-metrics", title: "Ranking Metrics And Scopes",
                    body: "Metric controls switch between total score, adjusted rank, "
                        + "weighted rank, full-combo rate, and max-score percentage when "
                        + "enabled. Scope controls decide whether you are looking at a "
                        + "solo instrument, band type, combo, or family ranking."
                ),
                ManualSubsection(
                    id: "rivals-solo", title: "Solo-Player Rivals",
                    body: "Rivals is available only for selected solo player profiles. "
                        + "It can show song rivals, common-song comparisons, combo or "
                        + "instrument rival groups, leaderboard neighbors, rival detail "
                        + "pages, and rivalry drilldowns."
                ),
            ]
        ),
        ManualSection(
            id: "shop", title: "Item Shop", symbol: "bag",
            intro: "The Item Shop page collects songs currently available in the shop "
                + "and highlights limited-time browsing states. It is useful when you "
                + "want to inspect shop songs directly or use shop state as a signal "
                + "while browsing Songs.",
            context: "Shop visibility can also appear on song rows and song details "
                + "when enabled in App Settings.",
            subsections: [
                ManualSubsection(
                    id: "shop-grid-list", title: "Grid And List Views",
                    body: "Grid and list views support different browsing densities. "
                        + "Grid view emphasizes album art and visual scanning, while list "
                        + "view is better when you want a tighter table-like pass through "
                        + "shop songs."
                ),
                ManualSubsection(
                    id: "shop-badges", title: "Shop Badges On Songs And Details",
                    body: "Shop badges can appear on Songs rows and song detail "
                        + "headers, helping you spot tracks that are currently available "
                        + "while staying in your normal browsing flow."
                ),
                ManualSubsection(
                    id: "shop-settings", title: "Leaving-Tomorrow And Visibility Settings",
                    body: "App Settings can hide Item Shop UI or change how shop "
                        + "highlights appear. Leaving-tomorrow states help you notice "
                        + "songs that may need attention soon."
                ),
            ]
        ),
        ManualSection(
            id: "settings", title: "App Settings", symbol: "gearshape",
            intro: "App Settings control how the app looks and how much information "
                + "appears while browsing. They are especially useful for reducing "
                + "noise when you only care about certain instruments, metadata fields, "
                + "path views, or mobile controls.",
            context: "The examples below focus on app preferences and browsing "
                + "behavior. Operational status rows are intentionally not part of this "
                + "manual.",
            subsections: [
                ManualSubsection(
                    id: "settings-instruments", title: "Instrument Visibility And Metadata",
                    body: "Show Instruments decides which instruments appear across "
                        + "Songs, Player Details, Suggestions, and Leaderboards. Show "
                        + "Instrument Metadata and Song Row Visual Order control which "
                        + "extra values appear when Songs is focused on a single "
                        + "instrument."
                ),
                ManualSubsection(
                    id: "settings-paths", title: "Paths, Leeway, And Ranking Examples",
                    body: "Common examples include changing the CHOpt path default "
                        + "view, reordering text path columns, adjusting max-score "
                        + "leeway, and enabling experimental leaderboard ranks when you "
                        + "want more ranking mechanisms visible."
                ),
                ManualSubsection(
                    id: "settings-preferences", title: "Mobile Header, Shop, Export, And Reset",
                    body: "Other examples include showing or hiding mobile header "
                        + "buttons, changing shop highlighting, replaying first-run "
                        + "guides, exporting selected profile data, and resetting saved "
                        + "app preferences."
                ),
            ]
        ),
    ]
}
