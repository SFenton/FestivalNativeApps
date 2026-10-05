# Songs Sort — Android notes

> **What:** the Android Sort sheet, sort modes and bucket headers. **Read when:** changing `SortSheet`, `SongSortDraft`, `SongCatalogSort` or `SongQuickLinkBuckets`. Behavior: [spec.md](spec.md).

- Modes (web `SortModal`): Title, Artist, Year, Duration, Item Shop (hidden while Hide Item Shop is on); **Has FC** and **Last Played** with a selected player; with a player and a Settings-visible single-chart filter, a "{Chart} Sort Mode" group — Score, Percentage, Percentile, Stars, Season, Intensity, Difficulty (each hidden when Settings hides its metadata), Max Score %, Max Score Diff — plus a **Metadata Sort Priority** reorder list (shared Settings `ReorderList`, persisted as `fst.songs.metadataOrder`, Kept). Direction is a radio group of two rows (Ascending "A–Z, low–high", Descending "Z–A, high–low"; icon circle filled when selected). Changes **apply live**; Reset (defaults, live) and the header Close (`.done`).
- The Sort button (`.open`) carries the current sort as its TalkBack state ("Artist, descending", `SongSortDraft.describe`), and turns gold when the sort differs from the default. On narrow list panes the adaptive top bar may move it into the ⋮ overflow menu (`fst.nav.overflow`), whose popup keeps test tags as resource IDs; the menu closes after the sheet it opened closes (issue #160).
- Comparator = web `useFilteredSongs`: missing scores sort after scored ones ascending (first descending, like the web); Intensity, Max Score %/Diff and unfiltered Last Played keep measurable songs first in both directions; ties title then song ID in the sort direction; Shop ties title → artist → year. Has FC and score modes read the filter chart, else the first Settings-visible chart (the web uses Lead).
- Pauses (Title order + notice, choice saved): Shop without a validated same-publication feed; single-chart modes without a chart filter; score modes without a player or a matching score index. Deselecting the player resets a score sort to Title.
- Buckets and Quick Links: see [songs/android.md](../../pages/songs/android.md). Percentage buckets use the percent scale (the web compares expanded accuracy to percent thresholds; not ported).
- IDs: `fst.songs.sort{,.open,.heading,.mode,.chart-mode,.direction,.ascending,.descending,.reset,.done,.priority}`, `fst.songs.sort.<mode>`, `fst.songs.sort-paused` (the sort's pause notice), `fst.songs.section.<mode>.<token>`, `fst.songs.shop-section.*`. The heading has its own tag so the `fst.songs.sort` root stays unique to the sheet.

## Validation (issue #125, 2026-10-03)

Live public service, SFentonX selected, dark scheme, animator scale 0 except for the motion recording. Material 3 skill checked: radio buttons in a `selectableGroup` with the whole row clickable, 48 dp targets, the modal bottom sheet (drag handle, scrim, swipe/back dismiss), window classes and foldables ("Never place interactive content or critical information across the hinge area").

| Configuration | Found | Result |
|---|---|---|
| FST_Phone portrait/landscape, fs 1.0/2.0 | Sheet heading reused the `fst.songs.sort` root ID (two nodes); the Sort button didn't say which sort was on; the sort pause notice lacked the contract's `fst.songs.sort-paused` | Fixed: `.heading` tag, state description, `sort-paused` tag. At 2.0 the sheet scrolls and nothing clips |
| FST_Tablet portrait/landscape, fs 1.0/2.0 | — | Pass (width-capped centred sheet; Shop sections with headers) |
| FST_Resizable phone/foldable/tablet/desktop | Foldable list pane: Year/Duration add Quick Links, the title truncates and the page tools collapse into ⋮ (by design); the overflow popup didn't expose test tags | Fixed: `popupTestTags()` on the overflow menu. Others pass |
| FST_Book_Fold folded/half/unfolded, fs 2.0 | **Half-open (book):** the sheet was centred across the hinge, so every radio row crossed it | Fixed: `festivalSheetHingeSide()` keeps every `FestivalModalSheet` on the wider (leading on a tie) side; tabletop keeps it below the hinge; flat unfolded stays centred |
| FST_Passport_Fold folded/half/unfolded, fs 2.0 | — (hinge fix confirmed: sheet left of the hinge) | Pass |
| FST_TriFold folded/partial/unfolded, fs 2.0 | — | Pass (unfolded folds are flat, so the sheet stays centred) |
| Light theme | App stays dark | Documented dark-only deviation ([design](../../design/android.md)) |
| TalkBack (FST_Phone) | Close, 7 mode radios ("Selected/Not selected, n of 7"), Sort Direction heading, 2 direction radios, Reset | Coherent order and roles |

States: `discard-confirm` and the web's Cancel/Apply are unreachable (live apply, operator rule); `reset-draft` is the live Reset; `band` is not ported (no native band identity; band search is a blocked endpoint). Deliberate deviations: a width-capped bottom sheet instead of a side sheet on expanded windows; dark scheme only.

Tests: `ui/songs/SongsSortUiTest` (default, changed mode/direction, Reset, applied + Sort button state, relaunch persistence, instrument-filtered chart modes, profile modes, Shop loaded/sectioned/one bucket/empty/unavailable/hidden, large text, half-open and flat folds), `core/nav/SheetHingeTest`, `core/songs/SongsCoreTest.sortButtonStateNamesModeAndDirection`, connected `SongsAccessibilityJourneyTest.songsSortStates` (FST_Phone).
