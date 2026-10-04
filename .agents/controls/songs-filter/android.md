# Songs Filter — Android notes

> **What:** the Android Filter sheet, its draft model and persistence. **Read when:** changing `FilterSheet`, `SongFilterDraft`, `SongPlayerScoreFilter` or `SongsPreferences`. Behavior: [spec.md](spec.md).

- Always available (issue #77; web `6415d3e3`); gold icon when a saved filter applies (`SongsUiState.filterActive` → `SongsPreferencesState.filterActive(hasPlayer, hideShop)`, web `isFilterActive`: General always, Item Shop only while shown, instrument/score/bucket filters only with a player).
- Sheet structure follows the web `FilterModal` (operator 6.32; the old difficulty range slider is gone): **General** (`fst.songs.filter.general`: Year and Duration bucket switches with Select All / Clear All from `SongsUiState.availableDecades`/`durationBuckets`, Item Shop availability omitted while the Shop is hidden, Double Bass). With a player only: **Global Score & FC Toggles** group, **Individual Score & FC Toggles** with one collapsible group per visible chart (web labels such as "Missing Lead Scores" plus descriptions), then **Selected Instrument Filters**: the shared Instrument Selector (`deferSelection`, compact on phones) revealing **Season**, **Percentile**, **Stars** and **Song Intensity** groups of bucket switches with trailing **Select All / Clear All** text actions (7.17). Groups open by default when they hold a saved choice. Changes apply live; **Reset** is red (7.10), **Done** closes.
- Model: `SongGeneralFilter` (`core/songs/SongFilters.kt`: hidden decades/durations, `shopAvailable`/`shopUnavailable`, `doubleBassSupported`/`doubleBassUnsupported`; `SongCatalogBuckets` keys and labels; `Song.doubleBassSupported` is the wire field); without a player the view model passes `SongFilter()` so a saved instrument never narrows the list. `SongFilter(instrument, excludedIntensities)` (intensity buckets 1–7 plus 0 = web `difficultyFilter` `false` keys, public, need an instrument); `SongPlayerScoreFilter` adds `excludedSeasons` / `excludedPercentiles` / `excludedStars` (`core/songs/SongBuckets.kt` keys, web `seasonFilter` / `percentileFilter` / `starsFilter`), applied only with a visible Songs instrument; percentile bucket = first threshold ≥ rank / total × 100 (0 = no score or rank). Profile presets use `onlyStars`, `onlyPercentile`, `cleanedFor`.
- Semantics: AND within a chart, OR across active charts, then the buckets; uncharted parts never match; an available empty index still allows Missing Scores (spec correctness fix).
- Persistence: public filters in `fst.songs.filters` (retired `min/maxDifficulty` keys ignored; unknown or duplicate intensity, decade or duration keys drop that section; retired `inShop`/`leavingTomorrow` migrate to Available only), player filter in `fst.songs.playerScoreFilters` (typed JSON, ≤ 4 KB; unknown or duplicate charts or bucket keys → corrupt → list blocked until Reset; filters without buckets encode to the old bytes). Deselection clears the player filter and the instrument/intensity filter, keeping General.
- IDs: `fst.songs.filter{,.open,.form,.title,.reset,.done}`, `fst.songs.filter.{global,shop,year,duration,double-bass}` (group headers), `fst.songs.filter.general`, `fst.songs.filter.{year,duration}[.select-all|.clear-all|.<key>]`, `fst.songs.filter.{shop-available,shop-unavailable}`, `fst.songs.filter.double-bass.{supported,unsupported}`, `fst.songs.filter.score-sections`, `fst.songs.filter.score.{global,instrument,chart}.*`, `fst.songs.filter.instrument[.<wireId>|.compact|.previous|.next|.preview]`, `fst.songs.filter.<season|percentile|stars|intensity>[.select-all|.clear-all|.<key>]`, `fst.songs.score-filter-hidden`, `fst.songs.filter-{invalid,reset-invalid}`. Pause notices are `fst.songs.notice.<i>`. The contract's `fst.songs.filter-paused` / `fst.songs.score-filter-paused` IDs don't exist on Android: one notice list carries every pause reason.
- Compact-height windows (< 480 dp, such as a landscape phone or folded landscape) put **Reset** in the header beside Close instead of a pinned footer.

## Validation (issue #126, 2026-10-04)

Emulator API 37, debug build, live public service with SFentonX selected (keyless; no selected-profile headers). Dark scheme only by repo rule; the system light theme was checked and the app stays dark.

| Configuration | Result |
|---|---|
| FST_Phone portrait, font 1.0 and 2.0; system light and dark | OK. At 2.0 the toggles' rows wrap without clipping. |
| FST_Phone landscape, font 1.0 | OK |
| FST_Phone landscape, font 2.0 | **Fixed**: the pinned header and Reset footer left about 120 dp of form. Reset now moves to the header on compact height. |
| FST_Tablet portrait ⇄ landscape (PermanentDrawer ⇄ Rail) | **Fixed**: rotating closed the open sheet and lost its draft. The shell now hosts content through `movableContentOf`. |
| FST_Resizable phone / foldable / tablet / desktop presets | OK; the sheet stays open across resizes, centred at 640 dp max. |
| FST_Book_Fold unfolded / folded | OK, continuity kept. |
| FST_Book_Fold half-open (separating vertical hinge at x=1038 px) | **Fixed**: the sheet straddled the hinge. It now sits in the start pane. |
| FST_Passport_Fold unfolded / half / folded | OK (half: start pane after the fix). |
| FST_TriFold unfolded / partial / folded | OK. The hinges are flat (non-separating), so the sheet stays centred. |

- Accessibility:
  - A real TalkBack walk on FST_Phone reads Close, then "General" (heading), then each group as "Collapsed. <name>. Button. Heading", then the Instrument Selector (Previous, radio, Next), then Reset, then the scrim "Close sheet", the drag handle and the title.
  - ATF (`SongsAccessibilityJourneyTest.songsFilterExpandedSectionsStayAccessibleAndClearOfTheHinge`) found that the M3 drag handle was 32 dp wide. Its actionable area is now 48 dp.
  - Touch targets: toggle rows 56 dp; bucket rows, accordion headers and Close 48 dp; selector 64 dp.
  - Reduced motion: device runs default to animator scale 0. Close dismisses instantly under Reduce Motion.
- Material 3 deviations, deliberate:
  - Dark scheme only (brand).
  - A bottom sheet rather than a side sheet on expanded widths: the shared `FestivalModalSheet` is centred, 640 dp max, and matches Apple and web.
  - The red Reset (operator 7.10) and BrandTokens colours.
- States → tests. Robolectric `SongsFilterStatesUiTest`, unless noted:

| States | Tests |
|---|---|
| `player-loaded`, `score`, `full-combo` | `chartScoreAndFullComboTogglesFilterRows`, `globalToggleTurnsOnEveryVisibleChart` |
| `instrument`, `season`, `percentile`, `stars`, `intensity` | `instrumentSelectionRevealsBucketGroups` |
| `shop-draft`, `applied` | `shopAvailabilityAppliesLiveAndIsSaved` |
| `relaunch-persisted` | `savedShopFilterAppliesOnRelaunch` |
| `leaving-draft` (retired keys migrate) | `retiredLeavingTomorrowKeyMigratesToAvailable` |
| `shop-hidden-paused`, `shop-sort-badges-suppressed` | `hiddenShopPausesSavedShopFilter`, plus `SongsViewModelTest.shopSortAndHighlightsNeedSamePublication` |
| `shop-unavailable-paused` | `failedShopReadPausesShopFilter` |
| `shop-validated-empty` | `emptyMatchingShopFeedShowsEmptyResult` |
| `publication-mismatch-paused` | `shopFromAnotherPublicationPausesFilterAndBadges`, plus the view-model copy test above |
| `player-unavailable` | `unavailableScoresPauseScoreFilters` |
| `deselected-paused` | `deselectionClearsScoreChecksAndKeepsGeneral`, plus `SongsDataTest.deselectionClearsOnlyPlayerPredicates` |
| `anonymous-hidden` | `SongsUiTest.anonymousFilterOffersOnlyGeneralFilters` |
| `reset-draft` | `SongsUiTest.selectedPlayerRowsShowChipsShopAccentsAndFilter` |
| `player-loading-shop-active` | `SongsViewModelTest.selectedPlayerChipsFiltersAndPauses` |
| `normal-audit`, `focus-return`, hinge | connected `SongsAccessibilityJourneyTest` (FST_Phone; FST_Book_Fold `--posture half`) |
| compact height | `SongsFilterCompactHeightUiTest` |
| `largest-text` | emulator at font 2.0, above |

- Not reachable on Android:
  - `discard-confirm`: live apply, with no Cancel/Apply.
  - `band-pending` and `band-member`: there is no selected band, and band search is a blocked endpoint.
  - `reselected-restored-native`: deselection clears the player predicates, so reselecting starts clean while General stays.
