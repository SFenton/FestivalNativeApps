# Songs Sort — Windows notes

> **What:** WinUI 3 Sort flyout, Item Shop sort, design decisions and validation results. **Read when:** changing `SongSortDraft`, `SongListPipeline.CompareShop`/`ShopSections` or the Sort flyout in `SongsPage.xaml`. Rules: [spec.md](spec.md).

## Implementation

- `SongsPage.xaml`: a `DropDownButton` (`fst.songs.sort`, name "Sort Songs") whose content is the applied summary (`Item Shop ↑`, gold when non-default). `AutomationProperties.HelpText` is `SongsViewModel.SortDescription` ("Year, descending"), so Narrator reads the applied sort, not the arrow glyph.
- The flyout (`Flyout`, 300 epx `StackPanel`) holds a "Sort Songs" Level 2 heading, then two `RadioButtons` groups:
  - **Sort By** (`fst.songs.sort.mode`): `SongSortDraft.ModeLabels`, the web's list. A selected player adds Last Played; an instrument filter adds Score, Percentage, Percentile, Stars, Seasons, Intensity, Max Score Diff (the form gets taller than the window and the flyout scrolls). Item Shop is removed while the Shop is hidden, and a saved Shop sort then shows no selection.
  - **Direction** (`fst.songs.sort.direction`): two rich `RadioButton` rows, `.ascending` "Ascending, A–Z, low–high" and `.descending` "Descending, Z–A, high–low". An arrow glyph is `AccessibilityView.Raw`. `SelectedIndex` binds `SongSortDraft.DirectionIndex` (0 ascending, 1 descending; other values are ignored).
  - A full-width red **Reset** (`fst.songs.sort.reset`, `FSTDanger*` brushes; ButtonFace/ButtonText under contrast themes) restores Title ↑.
- Every change applies live and persists (`songSort`, `songSortAscending`). There is no Cancel/Apply (operator decision, 2026-09-28). Light dismiss or Esc closes.
- Item Shop sort needs `ShopOffersForCatalog` from the same publication. Otherwise rows show in Title order in the saved direction with the `fst.songs.sort-paused` InfoBar (hidden Shop, loading/failed feed, publication mismatch). The summary keeps the saved choice (`Item Shop ↑`).
- Buckets use the first-seen order of the sorted rows (Leaving Tomorrow / In Shop / Not In Shop). Each heading carries `fst.songs.shop-section.{leaving-tomorrow|in-shop|not-in-shop}` (`SongListPipeline.SectionAutomationId`, only under an effective Shop sort). A single bucket has no heading and no Jump index. The first section's in-list heading is collapsed under the sticky header (`fst.songs.section-header`), so only later buckets expose their ID.
- Notices are `SongNotice(AutomationId, Message)` records: `fst.songs.sort-paused`, `fst.songs.filter-paused`, `fst.songs.profile-paused`, `fst.songs.score-filter-paused`, each on its InfoBar.
- The button tint is set from code, so `SongsPage` re-applies it on `ContrastTheme.Changed` (subscribed on `Loaded`, removed on `Unloaded`).

## Design decisions (winui-design)

- `winapp find-ui "radio group"` → `RadioButtons`. The skill's control guidance: use `RadioButtons` for "a small set of mutually exclusive options", which "handles arrow-key navigation and a single tab stop". Direction used two loose `RadioButton`s (two Tab stops, no group name for UIA). It is now a `RadioButtons` with a header like Sort By: Tab reaches the selected direction once and arrows move within the group.
- `find-ui "sort menu"` also returns `DropDownButton` + `MenuFlyout` with `RadioMenuFlyoutItem`. We keep a `Flyout` with `RadioButtons`: the web's Sort modal has a heading, a two-line description per direction and a full-width Reset, which a `MenuFlyout` can't hold. The flyout keeps light dismiss and Esc.
- `theme-accessibility.md`: inline brushes don't follow `{ThemeResource}` on a contrast switch, hence the `ContrastTheme.Changed` re-tint of the button label.
- The live apply without Cancel/Apply is a deliberate deviation from the spec's draft table (operator, 2026-09-28): the Fluent flyout pattern applies choices as you make them.
- The app theme is dark-only: the light system theme still renders dark (see [design/windows.md](../../design/windows.md)).

## States and reachability

| State | Windows | Evidence |
|---|---|---|
| `default` | Title ↑, Sort By/Direction/Reset | `songs-sort-states` |
| `changed-mode` | Year applies at once (`Year ↑`) | `songs-sort-states`; Core `SortDraft_AppliesLiveAndPersists` |
| `changed-direction` | Descending applies at once (`Year ↓`) | `songs-sort-states`; Core `DirectionIndex` asserts |
| `reset-draft` | Reset applies Title ↑ at once (no draft) | `songs-sort-states`, `songs-sort-instrument` |
| `discard-confirm` | **Not reachable**: no Cancel/Apply, so nothing to discard | Design decision above |
| `applied` | Decade sections, Jump hidden | `songs-sort-states`, `songs-sort` |
| `relaunch-persisted` | `Year ↓` after a restart on the same settings file | `songs-sort-states` (`{relaunch}`) |
| `instrument-filtered` | Lead filter adds the nine instrument modes; flyout scrolls | `songs-sort-instrument` |
| `profile` | Selected player adds Last Played | `songs-sort-states` vs `songs-sort-anonymous` |
| `band` | **Not reachable**: Windows selects only players (band search is a blocked endpoint) | [service-safety](../../platforms/service-safety.md) |
| `shop-loaded` / `shop-sectioned` | Leaving Tomorrow + In Shop headings, both directions | `songs-sort-shop`, `songs-sort-shop-single` (Not In Shop) |
| `shop-one-bucket` | A search leaving one bucket: no headings, no Jump | `songs-sort-shop`; Core `SortDraft_HidesShopWhenHidden_AndShopSortGroups` |
| `shop-empty` | Known-empty feed: one unlabeled Not In Shop section, no notice | `songs-sort-shop-empty` (fixture `shop-empty`) |
| `shop-unavailable` | 503 feed: Title order + `fst.songs.sort-paused` | `songs-sort-shop-unavailable` (fixture `shop-error`); Core `ShopUnavailable_PausesSavedShopSortAndFilter_WithNoticeIds` |
| `shop-hidden` | Item Shop mode removed; saved Shop sort paused | `songs-sort-shop-hidden` |
| `large-text` | Text 200%: rows wrap inside the flyout, which scrolls | `a11y_matrix.py --mode text-200` |

Run: `python tools/windows/songs_journey.py --only songs-sort-states,songs-sort-anonymous,songs-sort-instrument,songs-sort-shop,songs-sort-shop-single,songs-sort-shop-hidden,songs-sort-shop-empty,songs-sort-shop-unavailable,songs-sort --sizes compact,medium,wide`. The app sends no `scenario` query, so the Shop-feed scenarios run behind a loopback proxy that adds one to `/api/shop` only. All of them use UIA patterns only, so they pass on a locked console.

## Validation (issue #218, 2026-10-03)

| Configuration | Result |
|---|---|
| Fixture journeys above at compact / medium / wide | 27/27 pass |
| `a11y_matrix.py --only songs-sort --scan --tabs 14` C/M/W | Axe 0; 3 Tab stops cycling in the flyout (Title → Ascending → Reset). Before the fix there were 4 (each direction was its own stop) |
| High contrast Desert, Night sky (compact, wide) | Axe 0, 3 stops; Reset and radios use system colours |
| Light / dark system theme | Axe 0; the app stays dark (deliberate) |
| Text 200% | Axe 0; labels wrap, the flyout scrolls, nothing clips |
| Display 100% / 150% | Axe 0; layout unchanged in epx |
| Keyboard | `kb-songs-sort-esc`, `kb-songs-order` pass: Enter/Space opens, arrows move within each group, Esc closes and returns focus to the Sort button |
| Keyboard (groups) | `kb-songs-sort-groups` passes: Tab moves Sort By → Direction → Reset, and arrows stay inside each group |
| Live public service (SFentonX selected, 731 songs): compact / medium / wide, maximized, snap-left; HC Night sky, text 200%, display 150% | The flyout anchors under the button at every size. Year ↓ applies decade sections live. Item Shop ↑ shows buckets in first-seen order: In Shop, then Leaving Tomorrow, then Not In Shop. "(Don't Fear) The Reaper" is In Shop and sorts first by title, so that bucket comes first on 2026-10-03 |

The console was locked during this pass, so Narrator itself wasn't run. Reading order was checked from the UIA tree: "Sort Songs" button (HelpText "Title, ascending") > heading "Sort Songs" > group "Sort By" > radios > group "Direction" > "Ascending, A–Z, low–high" (1 of 2) > "Descending, Z–A, high–low" (2 of 2) > "Reset".
