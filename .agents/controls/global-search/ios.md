# Global search — iPhone notes

> **What:** the Apple design and implementation of global search (songs, players, bands) on iPhone: a trailing **Search tab** in the tab bar (issue #92). **Read when:** changing the search entry point, surface or results on iPhone. Behavior and test IDs: [spec.md](spec.md). iPad: [ipados.md](ipados.md); Mac: [macos.md](macos.md). Placement of every page control: [nav-accessories.md](../../design/apple/nav-accessories.md).

## Decision per layout

| Layout | Entry point | Surface |
|---|---|---|
| iPhone (iOS 18+) | Trailing `Tab(value: RootTab.search, role: .search)`: the separate round Search button beside the tab capsule on iOS 26 | `GlobalSearchTab`: system `.searchable` field focused on selection (keyboard up), scope bar and results below |
| iPhone Duo (vertical bar) | The Search tab, separate at the end of the rail | `GlobalSearchTab` |
| iPhone iOS 17 | Search tab via `.tag(RootTab.search)` (no search role) | `GlobalSearchTab` |
| Any, hardware keyboard | ⌘K or ⌘F select the Search tab | `GlobalSearchTab` |

Issue #92 (owner, 2026-10-04) replaced the header Search button and the tab-bar accessory dock with the Search tab. HIG Search fields (`apple-hig/references/hig/search-fields.md`): a separate trailing tab "focuses the field and opens the keyboard immediately… choose it for fast, transient search that returns to the previous tab on exit"; HIG Tab bars (`tab-bars.md`): "A dedicated Search tab may be trailing." There is **no other** global-search entry point on iPhone (no header button, accessory or floating capsule).

**Transitions** (`RootTabTransition`, `App/Shell/RootTab.swift`, unit-tested): the section underneath stays selected while Search shows. The system **Close** beside the field (or tapping that section) returns to it with its stack intact; a result is pushed on it; choosing a different section leaves Search for that section. iOS 26 also focuses the field itself (`tabViewSearchActivation(.searchTabSelection)`). The model (query, scope, results) lives in the shell, but the system clears the text on Close.

**Five-tab limit:** the search tab counts toward the iPhone's five tabs (iOS 26.5: five sections + Search showed **More**). `FestivalTabPolicy.fittingSearchTab` drops Statistics from compact phone tabs (player: Songs · Suggestions · Compete · Settings · Search); the drawer's Statistics row pushes it. The Duo inner display keeps its regular set and the system overflow.

`GlobalSearchSheet` (own `GlobalSearchField`, inline title, Close) is now used only by the Mac window.

## Songs: filter stays separate

Songs keeps its own list filter: the **inline** `.searchable(placement: .navigationBarDrawer(displayMode: .always))` field with the prompt "Filter Songs", pinned above the list. It filters the list together with sort, filters and the A–Z scrubber. HIG Search fields: "Use an inline field when adjacency clarifies that it filters one view rather than searches globally"; Music does the same (global Search tab plus an inline Library filter). Global search never reads or writes the Songs text, and vice versa ([spec](spec.md#page-local-search-songs-is-separate)).

## Implementation

| Piece | File |
|---|---|
| Pure rules: scopes, prompts, ≥2 chars, 250 ms debounce, ≤20 songs in catalogue order, ≤10 players | `FestivalCore/GlobalSearch.swift` (+ `GlobalSearchTests`) |
| `GlobalSearchModel`: query, scope, per-section state, cancellation via `.task(id: runKey)`, catalogue reloaded per publication | `Features/Search/GlobalSearchModel.swift` |
| `GlobalSearchResults`, `GlobalSearchSheet` (Mac), `GlobalSearchButton` (Mac), `PageTrailingItems` | `Features/Search/GlobalSearchView.swift` |
| `GlobalSearchTab`, `RootTabBarBehavior` | `Features/Search/GlobalSearchTab.swift` |
| `RootTab`, `RootTabTransition` (+ `RootTabTransitionTests`) | `App/Shell/RootTab.swift` |
| Search tab, ⌘K/⌘F, `openGlobalSearch()`, iPad sidebar search detail | `App/FestivalRootView.swift` |

- **Scope bar:** a segmented `Picker` (All · Songs · Players · Bands), the HIG scope-bar form with the broadest scope first, instead of web toggle chips. The container carries `fst.global-search.scope`; segments are reached by label (a system segmented control has no per-segment identifier).
- **Loading:** Songs render as soon as the catalogue filter runs; Players show their own progress (`fst.global-search.players-loading`) until the account search returns (the spec's native correction).
- **Errors:** per section via `ServiceStatusInline`, so a scrape freeze reads "Scores are updating" with its countdown. An empty players envelope offers Retry.
- **Bands:** never requested ([service-safety](../../platforms/service-safety.md)). The Bands segment shows the explanation and a **Band Rankings** button; "All" has no Bands section, and its prompt is "Search songs or players".
- **Result-count announcement:** once the sections the scope shows have settled, VoiceOver hears `AccessibilityNotification.Announcement` with "3 songs, 1 player", "No results found.", "No songs found." or "1 song, Players unavailable" (`GlobalSearch.resultAnnouncement`, `GlobalSearchModel.resultAnnouncement`). It is debounced (`GlobalSearchResults.announcementDelay`, 700 ms in a `.task(id:)` keyed by the text), so typing or a second section arriving speaks only the last count; Bands and queries under two characters announce nothing.
- **Result cards (batch 6, Lane A3):** a plain `List` of separate glass cards 4pt apart on 16pt margins (inset-grouped doubled the left inset); song cards reuse the Songs row's 44pt art, `.headline` title and "artist · year · duration" subtitle so both rows are the same height; section titles are small uppercase heading rows (web `sectionHeading`), not pinned bands. On the Mac the sheet's Close is `FestivalSheetCloseItem`. The result-count announcement is VoiceOver-only; no visible count text.
- **Result rows:** one `Button` per `List` row (`PlayerSearchResultRows` for players). Songs show 40 pt art (`ArtworkTile`), title and artist. A selected player's row opens Statistics.

## Test IDs (Apple)

`fst.global-search.open` (Mac toolbar button only), `fst.nav.sidebar.search` (iPad sidebar row), `fst.global-search.surface`, `fst.global-search.scope`, `fst.global-search.hint`, `fst.global-search.section.{songs,players}`, `fst.global-search.result.{song,player}`, `fst.global-search.players-loading`, `fst.global-search.retry`, `fst.global-search.bands-unavailable`, `fst.global-search.close`. The system search field has no settable identifier: tests find the search field whose placeholder is the scope prompt ("Search songs or players").

## Open

- If a later iOS lets a search tab sit beside five tabs without "More", return Statistics to the phone tab bar.
- The Search tab item has no settable identifier: tests find it as the tab-bar button labelled "Search".
