# Global search — iPhone notes

> **What:** the Apple design and implementation of global search (songs, players, bands) on iPhone: the iOS 26.1+ tab-bar accessory, the toolbar button elsewhere (iOS 17–26.0, iPhone Duo rail), and the shared sheet. **Read when:** changing the search entry point, surface or results on iPhone. Behavior and test IDs: [spec.md](spec.md). iPad: [ipados.md](ipados.md); Mac: [macos.md](macos.md). Placement of every page control: [nav-accessories.md](../../design/apple/nav-accessories.md).

## Decision per layout

| Layout | Entry point (every page, root or pushed) | Surface |
|---|---|---|
| iPhone iOS 26.1+, horizontal tab bar | **Tab-bar bottom accessory** (Music's mini-player slot): a field-shaped "Search" button, with the page's own action after it when it has one (player Select/Switch/Deselect). The tab bar minimizes on scroll and the accessory goes inline | `GlobalSearchSheet` |
| iPhone iOS 17–26.0 | Toolbar **Search** button (`magnifyingglass`): before the bell + avatar on tab roots (`FestivalRootTrailingItems`), `.primaryAction` on pushed pages (`FestivalTabStack` destinations) | `GlobalSearchSheet` |
| iPhone Duo (vertical bar) | Same toolbar button; the system places it in the rail (no accessory in a vertical bar) | `GlobalSearchSheet` |
| Any, hardware keyboard | ⌘K or ⌘F | `GlobalSearchSheet` |

`GlobalSearchSheet`: full-height sheet, inline title "Search", `.searchable` drawer field focused on open, scope bar, trailing Close. A result closes the sheet, then pushes on the presenting section (Back returns there).

### Why not the system search tab

`Tab(role: .search)` is Apple's first choice for app-wide search in tab apps, and it was built and tested first. On iOS 26.5 a search tab counts toward the iPhone's five-tab limit: with a player selected (five sections) the tab bar showed Songs · Suggestions · Compete · Statistics · **More**, hiding Settings and Search (screenshot evidence in the lane report). HIG: avoid overflow tabs, and don't make tabs appear and disappear with state. The accessory keeps Search at the bottom on every page (the operator's Music reference) without touching the tab set. A toolbar-only design on iOS 26 was rejected because pushed pages have no shell chrome and the top bar is already full on tab roots.

## Songs: filter stays separate

Songs keeps its **inline** `.searchable` field with the prompt "Filter Songs". It filters the list together with sort, filters and the A–Z scrubber. HIG: "Search as an inline field … when you need to filter or search within a single view"; Music does the same (global search plus an inline Library filter). Global search never reads or writes the Songs text, and vice versa ([spec](spec.md#page-local-search-songs-is-separate)). A Songs-only accessory pill from this lane's first pass was removed once search became global.

## Implementation

| Piece | File |
|---|---|
| Pure rules: scopes, prompts, ≥2 chars, 250 ms debounce, ≤20 songs in catalogue order, ≤10 players | `FestivalCore/GlobalSearch.swift` (+ `GlobalSearchTests`) |
| `GlobalSearchModel`: query, scope, per-section state, cancellation via `.task(id: runKey)`, catalogue reloaded per publication | `Features/Search/GlobalSearchModel.swift` |
| `GlobalSearchResults`, `GlobalSearchSheet`, `GlobalSearchButton`, `.globalSearchToolbarItem()`, `\.openGlobalSearch` | `Features/Search/GlobalSearchView.swift` |
| Accessory bar (Search + page action) | `Common/TabAccessory/TabAccessory.swift` (`TabAccessoryBar`) |
| Sheet, ⌘K/⌘F, `openGlobalSearch` | `App/FestivalRootView.swift` |
| Toolbar button on roots / pushed pages | `App/Shell/RootChrome.swift`, `App/AppRouteDestination.swift` |

- **Scope bar:** a segmented `Picker` (All · Songs · Players · Bands), the HIG scope-bar form with the broadest scope first, instead of web toggle chips. The container carries `fst.global-search.scope`; segments are reached by label (a system segmented control has no per-segment identifier).
- **Loading:** Songs render as soon as the catalogue filter runs; Players show their own progress (`fst.global-search.players-loading`) until the account search returns (the spec's native correction).
- **Errors:** per section via `ServiceStatusInline`, so a scrape freeze reads "Scores are updating" with its countdown. An empty players envelope offers Retry.
- **Bands:** never requested ([service-safety](../../platforms/service-safety.md)). The Bands segment shows the explanation and a **Band Rankings** button; "All" has no Bands section, and its prompt is "Search songs or players".
- **Result rows:** one `Button` per `List` row (`PlayerSearchResultRows` for players). Songs show 40 pt art (`ArtworkTile`), title and artist. A selected player's row opens Statistics.

## Test IDs (Apple)

`fst.global-search.open` (accessory button or toolbar button), `fst.global-search.surface`, `fst.global-search.scope`, `fst.global-search.hint`, `fst.global-search.section.{songs,players}`, `fst.global-search.result.{song,player}`, `fst.global-search.players-loading`, `fst.global-search.retry`, `fst.global-search.bands-unavailable`, `fst.global-search.close`. The system search field has no settable identifier: tests find the search field whose placeholder is the scope prompt ("Search songs or players").

## Open

- Result-count announcement ("3 songs, 10 players") is not implemented yet.
- If a later iOS lets a search tab sit beside five tabs without "More", revisit the search tab.
