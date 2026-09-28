# Installed PWA vs native Android app: gaps

> **What:** differences between the Chrome-installed PWA ([android.md](android.md)) and the native Compose app on the same FST AVDs, with a suggested fix per row. **Read when:** picking Android parity work or reviewing an Android surface against the PWA.

Evidence: PWA `showcase\pwa\android\<AVD>[-<posture>]\<page>.png`, native `showcase\pwa\android-native\<AVD>[-<posture>]\<page>.png` (all pages on `FST_Phone`, key pages on Book Fold unfolded and Tablet; Debug APK from `master` @ `f3ffb60`, `pwa.py native`: anonymous via `FST_DEBUG_ANONYMOUS=1`, first run off, live data). Native navigation, top app bars and edge-to-edge are platform conventions ([platforms/android.md](../../platforms/android.md)); rows marked **keep native** record deliberate differences.

| # | Page / state | PWA | Native | Gap | Suggested fix |
|---|---|---|---|---|---|
| 1 | System bars | Status bar tinted `#1A0830`; white gesture strip under the tab bar | Edge-to-edge: background art under transparent status and gesture bars | PWA artefact | **Keep native** |
| 2 | Launch | Chrome splash: theme colour, centred icon, name at the bottom, then web spinner | Not compared (native cold start not recorded) | Unknown | Use the SplashScreen API with the same icon on `#1A0830`; record a cold-start clip (TODO) |
| 3 | Shell | Custom top bar (☰, title, profile, search), custom bottom tabs, FAB dock (Search pill, Sort, Quick Links / menu) | Material 3 top app bar (☰, title, sort, search, bell, avatar), Material navigation bar with pill indicator; no FAB dock | Placement of Songs search/sort/quick links | **Keep native** bars; keep every FAB action reachable (search field, sort, A–Z rail already present) |
| 4 | Anonymous player routes | `/rivals`, `/statistics`, `/suggestions`, `/compete` redirect to Songs | Rivals: "Track a player to see their rivals" + Select Player; Statistics/Player History: "No Profile/Player Selected" | Route policy differs (same as Windows gap 2) | Decide once for all natives (TODO(orchestrator)); today the web never shows these pages anonymously |
| 5 | `/bands` without an id | "Band not found" | Opens Songs | Different fallback | Mirror whichever the Bands spec picks |
| 6 | Songs banner | None when anonymous | "Player score filters paused until a player is selected." | Extra notice | Hide when no player has ever been selected |
| 7 | Songs rows | Title + "artist · year · length", no meter when anonymous | Difficulty meter on every row; long metadata marquees ("Lil Wayne ft. Cory Gunz · 2011 · 4:11" scrolls and wraps mid-text) | Extra meter, marquee | Match the web row (no meter unless the row settings ask for it); ellipsize instead of marquee |
| 8 | Songs search | FAB dock pill expands to a local filter with ✕ **Clear Search**; keyboard pushes the dock up | Inline "Search songs or artists" field under the app bar | Placement | **Keep native** field; add the web's clear affordance and count |
| 9 | Song Detail header | Compact pinned header (art, title, artist · year · length); **View Paths** in the dock | Large wrapped title, extra album line, **Paths** pill under the title; header scrolls | Pinning + density | Pin a compact header on scroll |
| 10 | Song Detail intensity | Two-column icon grid without labels | Labelled list (9 rows) | Density | Use the icon grid on phones; labels in content descriptions |
| 11 | Song Detail order | Instrument leaderboards directly after intensity | "Band Leaderboards" (Duos/Trios/Quads chips) before instrument leaderboards | Order | Follow the web order (band leaderboards last) |
| 12 | Song leaderboard rows | Score then gold accuracy badge ("100%"); instrument switcher icon in the header | "FC 100%" chip before the score; no header instrument icon | Order + FC treatment | Match web order/badge; add the instrument switcher |
| 13 | Paginator | Floating pill « ‹ n / N › » above the tab bar | "n / N" text with faint arrows at the bottom | Affordance | Use the web's pill with four buttons |
| 14 | Leaderboards overview | One line per row: rank, name, "728 / 729", blue total; "View all rankings (868,901)" | Two-line rows ("728 / 729 songs"), "View All" | Density, missing count | One-line rows; count in the link |
| 15 | Full rankings | Header "Lead Leaderboards · 868,901 ranked players", instrument pill in the FAB dock | Lead / Total Score dropdown chips under the app bar | Control placement | **Keep native** chips; title and count as the web |
| 16 | Item Shop (phone) | Rows with cart icon + chevron | Rows with an external-link icon | Icon | Use the web's cart + chevron |
| 17 | Settings | CHOpt column order: drag handles (⋮⋮ Activation, Beat, Time, Overdrive %) | Numbered list with up/down buttons | Control type | Support drag with the numbered buttons as the accessible alternative |
| 18 | Drawer | Touch tap does not open it (web bug, [android.md](android.md#layout-and-navigation-phone)) | Opens | Web bug | **Keep native** |
| 19 | Orientation | Locked portrait by the manifest | Rotates | Web limitation | **Keep native** (support landscape) |
| 20 | Motion | Rows `fadeInUp` 400 ms ease-out / 125 ms stagger; sheets 250–300 ms; background 6 s pan + 1 s crossfade | Not frame-stepped yet | Unknown | Record native clips with `pwa.py drive`-style steps (TODO) |
| 21 | Large screens (Book Fold unfolded, tablet) | Same single-column mobile shell stretched across the hinge; no two-pane; status bar untinted (`FST_Book_Fold-unfolded/`, `FST_Tablet/`) | Navigation rail (fold) / permanent drawer (tablet), search field in the top bar, list-detail Songs with a "Select a song" pane on the tablet (`android-native/FST_Tablet/songs.png`) | Native adapts, web does not | **Keep native**; keep the panes off the hinge (the web straddles it) |
| 22 | Drawer destinations (anonymous) | Songs, Leaderboards, Item Shop; footer Select Profile, Settings | Songs, Leaderboards, Settings; Browse: Item Shop, Bands; More: Licenses | Extra Bands/Licenses entries, different grouping | Match the web set and order; reach Licenses from Settings |

## Top gaps to schedule

4–7, 9–14, 16–17, 22, 2 and 20 (4 and 5 need an orchestrator decision first).
