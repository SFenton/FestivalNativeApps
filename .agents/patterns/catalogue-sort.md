# Catalogue sort

> **What:** the Sort control for song catalogues (Songs and Item Shop): the sheet or flyout, its mode radios and Sort Direction section, the shared comparator, default and Reset, the trigger's active state, persistence, and the pause when a mode's data is missing. **Read when:** adding a sort to a page that lists catalogue songs, changing Songs or Item Shop sorting, or touching the Sort sheet's direction rows on any platform.

Status: **current**, 2026-10-07. Provenance: #125 (Songs Sort on Android), #379 (Item Shop sort; agent decision below).

## Intent

A page that lists catalogue songs sorts them the same way Songs does. The owner asked for Item Shop sorts "same as song list" (#379), so a new consumer reuses the Songs Sort control and comparator with its own subset of modes. It never builds its own picker, direction control or ordering rules.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songs/modals/SortModal.tsx` (`SortModal`) | Songs Sort modal: mode radio rows, then the ↑/↓ direction rows, Reset, Apply. |
| `FortniteFestivalWeb/src/hooks/data/useFilteredSongs.ts` | Songs comparator: Title/Artist by locale compare, Year/Duration numeric with missing values as 0, title as the tie-breaker. |
| `FortniteFestivalWeb/src/pages/shop/ShopPage.tsx` | Item Shop page (title order on master). |
| `pages/shop/shopSort.ts`, `pages/shop/modals/ShopSortModal.tsx` on web branch `report/379-web` (SFenton/FortniteFestivalLeaderboardScraper#175, #379) | Item Shop sort: Title, Artist, Year, Duration with direction in a modal built from the Songs `SortModal` pieces; one comparator for grid and list; Duration from the catalogue; saved in `localStorage` `fst:shopSort`. |

## Rules

1. **R1. One sort UI per platform.** A catalogue page's Sort opens the platform's Songs Sort frame: the modal sheet (Apple, Android) or flyout (Windows) with the mode choices as one single-select radio group, then the shared **Sort Direction** section (Ascending "A–Z, low–high" / Descending "Z–A, high–low"), Reset and Close. A page passes its own mode subset. Never a page-local dropdown, segmented control, chip row or copied direction rows; first-run demos of the sheet reuse the same direction section.
2. **R2. One comparator.** Title and Artist compare locale-aware; Year and Duration numerically, with a missing value sorting as 0; ties break by title, then song ID, in the sort direction (web `useFilteredSongs`). The page filter runs first, then the sort.
3. **R3. Item Shop modes.** Title, Artist, Year and Duration, in that order. No player, score, Shop or single-chart modes: the Shop has no selected-player dimension.
4. **R4. Default, Reset and trigger state.** Default and Reset are Title ascending. The trigger is tinted gold while the sort is anything else, and its accessible state reads "<Mode>, <direction>" ("Artist, descending"; Songs vocabulary), so TalkBack, VoiceOver and Narrator hear what the tint shows.
5. **R5. Live apply, saved per page.** A choice applies as it is picked and is saved under the page's own keys (Songs and Item Shop never share one). An Item Shop sort is not a player setting: deselecting a player keeps it.
6. **R6. One order for every layout.** Grid, list and hinge-split layouts render the one sorted list in reading order (row-major; around a separating hinge the rows run across it, [hinge-columns](hinge-columns.md)). A changed sort scrolls back to the top.
7. **R7. Missing data pauses, never guesses.** When a mode needs data the page's feed lacks (Item Shop Duration: `/api/shop` has no length), it reads it from the catalogue of the **same observed publication**. While that loads, the page stays in its loading state. When it fails or the publications differ, the page shows title order in the chosen direction with a visible pause notice and keeps the choice (the Songs paused-sort rule). The web joins by song ID without the publication check; the native check is the publication-provenance invariant (AGENTS.md).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Comparator (R2) | `apple/Sources/FestivalCore/SongCatalogSort.swift` `SongCatalogSort` | `android/app/src/main/java/com/festivalscoretracker/android/core/songs/SongCatalogSort.kt` `SongCatalogSort` | `windows/Festival.Core/Domain/SongQuery.cs` `SongCatalogQuery` (`Compare`) |
| Sort UI (R1) | `apple/Sources/FestivalUI/Features/Songs/SongsSortSheet.swift` `SongsSortSheet`, `SortDirectionControl` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongsSheets.kt` `LiveSheet`, `RadioRow`, `SortDirectionSection` | `windows/Festival.App/Pages/SongsPage.xaml` `SortFlyout`; `windows/Festival.Core/ViewModels/SongsViewModel.cs` `SongSortDraft` |
| Item Shop consumer (R3–R7) | not yet (debt) | `android/app/src/main/java/com/festivalscoretracker/android/core/shop/ShopSort.kt` `ShopOfferSort` (`ShopSortChoice`, `ShopDurations`); `android/app/src/main/java/com/festivalscoretracker/android/ui/shop/ShopSortSheet.kt` `ShopSortSheet` | not yet on master (debt) |

Android consumers: Songs `SortSheet` (`fst.songs.sort.*`), Item Shop `ShopSortSheet` (`fst.shop.sort.*`, saved in `fst.shop.sort` / `fst.shop.sortAscending`), and the first-run Songs sort demo (`SongsSortDemo`, `fst.first-run.demo.sort.*`). Tests: `core/shop/ShopSortTest` (modes, directions, ties, missing values, decoding, Duration pauses), `presentation/songs/SongDetailAndShopTest` (view model), Robolectric `ui/shop/ShopSortUiTest`, connected `shop/ShopSortDeviceJourneyTest` (sheet → Duration descending → grid and list order → relaunch on the same settings → Reset; ATF and reading order; `--posture half` for the hinge split).

**Not this pattern:** the Score History **Sort Scores** sheet (`fst.history.sort.*`, Android `ScoreSortControls`, issue #380) sorts a player's scores, not catalogue songs; its segmented direction row is its own control.

## Decision: Item Shop sorts on native and web (#379)

**Question.** Owner (#379, split from #357): "Item Shop should have sorts by Title, Artist, Year, Duration, same as song list (multi-plat and web?)". Should the sorts ship on the web as well as the native apps?

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| A | Native Item Shop gets the Sort control; the web Shop keeps title order | Material 3 Bottom Sheet: "Modal (blocks interaction, has scrim)" (should: the Songs sheet); Radio Button: "Group radios in a container with `role="radiogroup"`" (should); Buttons: "Minimum touch target 48x48dp" (must). Fluent: "contextual action → `Flyout`" (should). HIG: none decides scope | Web Shop sorts by title only (`ShopPage.tsx`); the Shop Filter (#19/#376) shipped natively first | The natives diverge from the web, the product source of truth |
| B | The same four sorts with direction on every native app **and** the web Shop, each through its Songs Sort control | Same as A on native; the web reuses its Songs `SortModal` | Web Songs `SortModal` already offers Title/Artist/Year/Duration with direction; the Shop becomes its second consumer | One more web change, in the web repo |

**Agent decision (#379, 2026-10-07): option B; owner may override with `/choose A`.** The owner asked for the sorts "multi-plat and web" and "same as song list". No platform *must* separates the options (the guidance above governs how the control looks, which both options share), and there is no explicit owner choice, so the precedence rule "web behavior beats native copies" decides: shipping the sorts natively only would make the web the exception to its own Songs behavior. Each platform reuses its Songs Sort control and comparator (R1, R2), so there is no new UI to learn. The web half is on web branch `report/379-web` (PR SFenton/FortniteFestivalLeaderboardScraper#175); Android ships in FestivalNativeApps #379; Apple and Windows ship in their own #379 branches.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple Item Shop has no Sort | R1, R3 | Apple #379 branch: reuse `SongsSortSheet`'s frame and `SortDirectionControl`, order with `SongCatalogSort` |
| Windows Item Shop has no Sort on master | R1, R3 | Windows #379 branch (moves the Songs flyout body into a shared control); update the Windows row here when it merges |
| Web Item Shop sort not merged | R3 (web) | Web PR SFenton/FortniteFestivalLeaderboardScraper#175; then cite `pages/shop/shopSort.ts` in `contracts/patterns.json` |

## Guards (`tools/pattern_guard.py`)

- `catalogue-sort/android-copied-direction-rows`
