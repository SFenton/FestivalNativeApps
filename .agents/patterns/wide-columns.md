# Wide columns

> **What:** the app-wide rule for when a page's rows or cards show in two columns: in wide landscape windows (iPad landscape, iPhone Duo unfolded in landscape, a wide Mac surface) and never in portrait. It covers reading order, headings, the Duo hinge and reflow, and lists every page that adopts it. **Read when:** making a page or sheet two-column, changing when Songs, Search or a full leaderboard pair their rows, or adding a page (add it to the audit below).

Status: **current**, 2026-10-09. Provenance: #350 (split from #332), #353 (full-width leaderboards, R8); generalizes the Songs landscape grid (`SongGridPolicy`, #312, #321). Settings adopted it with R7 (#355); owner #371 replaces R7's Settings page with a list/detail split on iPad, the iPhone Duo and Android tablets/foldables ([split-panes](split-panes.md) R6), so R7 now governs only the Mac Settings window panes. The Item Shop list adopts it (#378). Owner #543 draws each board column as one card (R8). Owner #581 ports it to Android Songs (owner-approved Android variant below).

## Intent

A list of rows that spans a landscape iPad or an unfolded Duo is mostly empty space with long eye travel. Two columns show twice as many results without changing what a row is. In portrait the same window is narrow enough that one column reads better. The owner's words (#332): "two-col on Duo unfolded/MacOS/iPad in landscape mode; Duo unfolded portrait/iPad portrait should be single-page (should replicate across every page in app)". The rule is therefore based on window shape and size class, not on the device or the page.

## Web source (behavior reference)

None. The web pages are a single column, including the search modal (`FortniteFestivalWeb/src/components/modals/SearchModal.tsx`) and Songs. This is a native extension for wide screens that the owner requested. The row content, copy and order stay as on the web.

## Rules

1. **R1. When.** Two columns only when the window is landscape (`DeviceLayout.orientation`, from the window, never from the page frame: the iPad keyboard shortens a portrait page into a wide box), its width and height size classes are both regular (`windowWidthClass`, `heightClass`), and the page has room for two 320 pt columns plus a 12 pt gutter inside its 16 pt row margins (≥ 684 pt; `WideColumns.count(layout:width:)`). Everything else is one column: iPhone, any portrait window, a folded Duo, compact Split View, Slide Over or Stage Manager tiles, and a split's sub-page (#353): the page an on-demand split opens in its trailing pane beside the list, kept as the trailing root while a profile covers the split (`\.splitPaneSubPage`, from `SplitPaneContext.isSubPage`). A page pushed after a covering profile fills the window and follows R1 again. On the Mac the page's own surface decides (`WideColumns.count(size:)`): it must be wider than tall and wide enough, because Mac windows and sheets resize freely and have no device orientation. HIG Layout: "Choose layout from size classes, not device type/idiom or orientation" (should). The size classes and the measured width are the gate. The landscape condition is the owner's explicit choice (portrait stays one column even when it would fit), which wins over a *should* (supported deviation, #350). HIG Mac Catalyst: "split a single column into multiple columns; use regular-width and regular-height size classes, reflowing content side by side as the window resizes" (should).
2. **R2. Row-major order under full-width headings.** Items flow left then right, then down (`WideColumns.rows`). A short last row keeps its card at column width and fills the rest with clear space. Section headings, hints, empty, failed and loading states, footers and "View all" buttons span both columns. Each card keeps its own button, accessibility identifier and label, so VoiceOver reads the same sequence in one or two columns ([load-transition](load-transition.md) R6 stagger order follows the flattened index).
3. **R3. On the Duo the columns meet at the hinge in book pose and at the free space's midpoint flat.** Rows draw through `HingeRow(spacing:)` (Settings through `WideColumnStack`). Partially folded (book pose), the gutter follows `DeviceLayout.splitHinge`, the active fold (else the inner display's middle), so the two columns meet at the hinge; each side then fills its own physical side, as in the on-demand split ([hinge-columns](hinge-columns.md) R1, agent decision #343). **Owner-approved rule (#361, app-wide):** fully unfolded (flat) there is no hinge, so the two columns are equal and meet at the midpoint of the page's free content area beside the vertical bar, never on the flat hinge line or the display's middle ([hinge-columns](hinge-columns.md) R7). Owner: "When completely unfolded, midpoint should still be midpoint of free space, not hinge. When partially folded, midpoint should be hinge." Supersedes #350's flat hinge alignment. HIG Designing for iPhone Duo: "Expand the existing layout with space" (should), "Folding region | Present when partially open"; Duo layout guidance (WWDC T463, `apple-hig` duo checklist): "Prefer even grid column counts".
4. **R4. Reflow in place.** Rotation, a fold change or resizing a window re-chunks the same loaded items. It never starts a new request, shows a spinner, changes a row's identity or replays a fade-in ([back-keeps-place](back-keeps-place.md), [load-transition](load-transition.md)). Page models live outside the column decision (Search's `GlobalSearchModel` is owned by the shell).
5. **R5. One policy.** Pages call `WideColumns` and `HingeRow`; they never compare widths, idioms or devices themselves. `SongGridPolicy` delegates to it. A page that cannot adopt the rule (a content-sized grid, a table, a split pane) is listed in the audit with its reason.
6. **R6. Mac Search opens at a two-column size in a wide window.** In a landscape Mac window at least 960 × 700 pt, the Search sheet opens at 880 × 640 pt, so its results show two columns. Otherwise it opens at 620 × 680 pt with one column, the web modal's shape. The sheet stays resizable (minimum 560 × 520), and its columns follow its live size (R1). HIG Sheets (macOS): "Present a sheet in a reasonable default size" (should).
7. **R7. Pages of unequal section cards flow column by column (Mac Settings window panes, #355).** Superseded for the Settings page by owner #371: on iPhone Duo unfolded, iPad and Android tablets/foldables Settings is a list/detail split ([split-panes](split-panes.md) R6), not two columns of sections; the Mac Settings window keeps its toolbar panes split by this rule. iOS Settings is one readable column wherever it does not split. A page of stacked section cards with very different heights does not pair rows: pairing would leave large holes beside a tall card. `WideColumnStack` places whole sections top to bottom in the left column, then in the right. It splits at the index that makes the taller column shortest (`WideColumns.balancedSplit`, earliest on a tie, neither column empty). The columns are R1's cells and meet at the Duo hinge (R3, `HingeRowLayout.cells`). Section order, Quick Links, the load-in stagger and VoiceOver keep the one-column sequence. Each section is an accessibility container sorted by page order (iOS 18 / macOS 15 and later; earlier systems fall back to geometric order). Accessibility text sizes (AX1 and larger) always use one column (`WideColumns.readable`). HIG Layout: "Accommodate Dynamic Type… horizontal views may stack" (should). Each column is capped at 680 pt (`ReadableWidthContainer.maxWidth(columns:)`). The page measures its own width, so a page narrowed by the Licenses trailing pane drops to one column. On the Mac, Settings window panes split the same way (`count(size:)`). The window is 860 × 620 pt, so General, Songs, Paths and About show two columns of about 400 pt; single-section panes (Guides, Service) stay one centred column. A section that grows may move to the other column; this is an in-place reflow (R4).
8. **R8. Full-width leaderboards (#353).** Full Rankings, Band Rankings, Song Leaderboard and Song Band Leaderboard pair their page's rows per R1 when they fill the window, never as a split's sub-page. Rows run row-major (#1 | #2, then #3 | #4) through `WideColumns.indexedRows` and `WideColumnsRow` (`HingeRow` with a clear filler for a short last row), and each screen reads its count with `.wideColumnsCount($columns)`. Every row keeps its own button, identifier, keyboard row and stagger index. Each column fits the section's one column plan ([leaderboard-row](leaderboard-row.md) R1) at `WideColumns.columnPageWidth`. The Solo board's pinned selected row shares that per-column plan, and the band board's pinned row keeps its full-width plan. The pinned selected row and the pager span both columns under the board ([leaderboard-row](leaderboard-row.md) R5, R7). In two columns a row's scroll id is its first entry's, so a selected-row reveal scrolls to `WideColumns.rowStart(of:columns:)`. Each column is one group card on the native apps ([leaderboard-row](leaderboard-row.md) R10, owner #543): on Apple every cell is a segment of its column's card, and `WideColumnsRow(matchesHeights: true)` stretches a pair's shorter cell so the column's card has no gap.

## Agent decision (#350, 2026-10-08): a flowing grid under full-width headings

Question: what does two-column Search look like? Posted on the issue.

| Option | What you see | Guidance (strength) | Precedent | Trade-offs |
|---|---|---|---|---|
| **A (chosen)** | Results flow into two columns in reading order; "Songs", "Players" and "Bands" headings span both columns. | HIG Duo "Expand the existing layout with space" (should); T463 "Prefer even grid column counts"; HIG Layout "Choose layout from size classes" (should). | Apple Songs `SongGridPolicy` (two cards per row under full-width section headers). | Works for every scope and any result count; order matches portrait. |
| B | Songs in one column; Players and Bands in the other. | Same clauses. | None. | A column is empty for single-scope searches or when a category has no results; columns are very uneven; order changes on rotation. |
| C | Keep one column. | — | Web modal (single column). | Ignores the owner's request. |

Chose **A**. The owner may override it with `/choose B` or `/choose C`.

## Agent decision (#355, 2026-10-07): Settings sections in two balanced columns

Question: what does two-column Settings look like? Owner: "Settings page should be two-col when unfolded/iPad landscape/MacOS". Posted on the issue.

| Option | What you see | Guidance (strength) | Precedent | Trade-offs |
|---|---|---|---|---|
| **A (chosen)** | The same sections flow column by column into two height-balanced columns; sub-pages (Licenses) still push or open in the trailing pane. | HIG Duo inner display: "a width reflow (Music goes from stacked to two columns)"; "Keep the same hierarchy inside and out" (should). HIG Layout: "Choose layout from size classes" (should); "Accommodate Dynamic Type" (should). | This pattern (R1–R4); web Settings is one column (`SettingsPage.tsx` `cardColumn`), so its sections and order are kept. | Keeps every section, row, Quick Link and the reading order. |
| B | Section list on the left, the selected section on the right (iPad Settings app). | HIG Duo allows "a split view" but "show another level only if it suits the content" (should). | None; it would clash with the Settings → Licenses trailing pane and Quick Links. | Adds a navigation level that iPhone and portrait don't have; one section at a time. |
| C | Keep one 680 pt readable column. | — | Previous `duo.md` rule. | Ignores the owner's request. |

Chose **A**. Its R7 supersedes `duo.md`'s "Settings intentionally does not get a 2-column grid". The owner may override it with `/choose B` or `/choose C`.

Superseded (#371, 2026-10-08): the owner chose a list/detail Settings page (close to option B: a list on the left, the selected setting's options on the right behind a centred placeholder) on Duo, iPad and Android tablets/foldables; see [split-panes](split-panes.md) R6. Option A stays for the Mac Settings window panes.

## Agent decision (#353, 2026-10-08): row-major boards with full-width chrome

Question: how does a full leaderboard read in two columns? Posted on the issue.

| Option | What you see | Guidance (strength) | Precedent | Trade-offs |
|---|---|---|---|---|
| **A (chosen)** | Ranks run left then right (#1 \| #2, #3 \| #4); the pinned selected row and the pager stay one full-width bar under both columns. | HIG Duo "Expand the existing layout with space" (should), "Avoid extreme changes" (should); T463 "Prefer even grid column counts"; HIG macOS "Use large displays to show more content" (should). | R2 (Search, Songs); [leaderboard-row](leaderboard-row.md) R5 (one pager under the board, beside the bar on the Duo, #345). | The same reading order as Search and Songs; ranks still read in order across each line; rotating keeps the page and selection. |
| B | Ranks run down the left column, then down the right (#1–#13, #14–#25). | Same clauses. | None in the app. | The column break moves with the window height, the second column starts off screen on a short window, and VoiceOver order differs from what you see. |
| C | A second pager and pinned row under each column. | — | None. | Two copies of the same controls; breaks leaderboard-row R5. |

Chose **A**. The owner may override it with `/choose B` or `/choose C`.

## Owner-approved Android variant (#581, 2026-10-09): Songs in two columns, no list/detail split

Owner (#581, split from #573): "Songs page should be two-col in landscape and unfolded like iPhone Duo." Scoped to **Android Songs**. Other Android pages and the other platforms keep the base rules. Do not revert it to the list/detail split.

- **When (R1, Android form):** two columns when the content holds two 320 dp columns and a 12 dp gutter inside its 16 dp row margins (≥ 652 dp), and either the window is wider than tall or it spans a vertical fold (flat or half-open). A separating vertical hinge with room for a column on each side always splits. There is no height-class gate: the owner asked for landscape phones too, which are compact-height. A Book Fold's inner display (≈ 851 × 882 dp) is not landscape, but it is unfolded. Portrait and compact windows keep one column, and so does every window while TalkBack runs or at large text (`rememberSingleColumn`). In that one-column case the list spans a fold full width, as every Android hinge split does at large text. `WideColumns.count`.
- **Hinge (R3):** in book posture the columns meet at the fold (`HingeColumns.resolve`, [hinge-columns](hinge-columns.md) R1). Flat, they split at the content midpoint (R7). The search field, notices, sticky section headers and the empty state keep to the leading pane (`FoldLane`, [section-headers](section-headers.md) R9/R10).
- **Order (R2):** rows chunk row-major within each section: a sort's section header, or a scrubber (A–Z) section. Every section therefore starts a line in the leading column, and Quick Links or the index lands on its first song. The trade-off is a clear cell after an odd section. Each line is one traversal group, so TalkBack reads its start song, then its end song.
- **Reflow (R4):** rotation and folding regroup the same rows (`WideColumnLines`). A line's key is its first song, and `KeepPlaceAcrossColumnChanges` keeps the reader's first visible song. Nothing reloads.
- **No list/detail split:** Songs fills the window on every Android width, and a tap pushes Song Detail, as on Apple. This supersedes, for Songs only, the operator rule of 2026-09-28 ("two populated panes whenever the window allows two") and Android `ListDetailPolicy` (removed). Settings and Licenses keep their list/detail split ([split-panes](split-panes.md) R6). Material 3 suggests list/detail for a book posture; the owner's explicit choice wins over that *should*. M3 "Never place interactive content or critical information across the hinge area" is kept.

Options weighed and posted on #581: A, this. B: keep the split on expanded windows and use two columns only elsewhere. C: two columns inside the 320–440 dp list pane, under 160 dp each. The owner may override with `/choose`.

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Policy (when, widths, row chunking, Mac sheet size) | `apple/Sources/FestivalUI/App/Layout/WideColumns.swift` `WideColumns` (`count(layout:size:subPage:)`, `columnPageWidth`, `indexedRows`, `rowStart`) | `android/app/src/main/java/com/festivalscoretracker/android/core/layout/WideColumns.kt` `WideColumns` (`count`, `spec`), `WideColumnLines` (row-major lines per section, item ↔ row mapping, `reflow`) (#581) | — |
| Two-up row meeting at the hinge | `apple/Sources/FestivalUI/App/Layout/HingeColumns.swift` `HingeRow` (follows `DeviceLayout.splitHinge`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/WideColumnsLayout.kt` `rememberWideColumns` (window, fold via `shellPosture`, `rememberSingleColumn`, RTL), `WideColumnsLine`, `KeepPlaceAcrossColumnChanges` (#581) | — |
| Board row pairs and count (R8) | `apple/Sources/FestivalUI/App/Layout/WideColumns.swift` `WideColumnsRow` (`matchesHeights`, one card per column, #543), `WideColumnsRowItems`, `View.wideColumnsCount(_:)`; sub-page flag `apple/Sources/FestivalUI/App/Layout/OnDemandSplit.swift` `SplitPaneContext.isSubPage` (`\.splitPaneSubPage`). Consumers: `FullRankingsScreen`, `BandRankingsScreen`, `SoloLeaderboardScreen`, `SongBandLeaderboardScreen`, Item Shop list (`ShopScreen.shopContent`, #378) | — | — |
| Songs grid | `apple/Sources/FestivalUI/Features/Songs/SongsScreen.swift` `SongGridPolicy` (delegates) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongsScreen.kt` `SongList` (owner variant #581, no list/detail split) | — |
| Search results | `apple/Sources/FestivalUI/Features/Search/GlobalSearchView.swift` `GlobalSearchResults` | — | — |
| Mac Search sheet size | `apple/Sources/FestivalUI/Mac/MacRootView.swift` `MacRootView` (`searchSheetSize`) | — | — |
| Column-by-column balanced stack (R7) | `apple/Sources/FestivalUI/App/Layout/WideColumns.swift` `WideColumnStack`, `WideColumnStackLayout`, `WideColumns.balancedSplit`, `WideColumns.readable` | — | — |
| Mac Settings panes (iPad and Duo: [split-panes](split-panes.md) R6) | `apple/Sources/FestivalUI/Features/Settings/SettingsScreen.swift` (`columns`, macOS only; `ReadableWidthContainer`); window size `apple/Sources/FestivalUI/Mac/MacSettingsView.swift` | — (Settings page is a list/detail split instead: [split-panes](split-panes.md) R6, #371) | — |

## Page audit (#350, #353)

Status per page: **adopts** (follows R1–R5), **exempt** (a layout the rule does not govern, with the reason), **follow-up** (should adopt; not changed in #350).

| Page / surface | Status | Today (Apple) |
|---|---|---|
| Search results (`global-search`) | adopts | Two columns per R1, at the hinge (R3); Mac sheet R6. |
| Songs | adopts | `SongGridPolicy` → `WideColumns`, `HingeRow`. The Mac keeps one row per song, a sortable table ([songs-section-index](../controls/songs-section-index/spec.md) owns its layout). Android adopts it through the owner-approved variant (#581). |
| Song Detail | exempt | Content-sized adaptive grids (`HingeGrid`, Intensity, instrument cards and, since #366, the Duos/Trios/Quads previews in `SongDetailCardGrid`) already fill width in any orientation. |
| Item Shop | adopts (list, #378); grid exempt | List mode pairs its Song rows row-major per R1–R4 through `WideColumnsRow` and `.wideColumnsCount` (one column at accessibility sizes, `WideColumns.readable`); the disclosures span both columns; Mac arrow keys step by row. Switching List and Grid replays the web view transition but never reads the Shop again. The grid is an adaptive even-column card grid (`ShopGridPolicy`, [hinge-columns](hinge-columns.md) R2). |
| Statistics | exempt | Adaptive stat tile grid (`StatTileGridLayout`). |
| Leaderboards | follow-up | Two `HingeGrid` columns whenever the width class is regular, including iPad portrait. Should switch to R1. |
| Player Profile | follow-up | Instrument tiles in two columns at regular width, including portrait. Should switch to R1. |
| Suggestions | follow-up | Two columns at regular width, including portrait. Should switch to R1. |
| Compete | follow-up | Leaderboards beside Rivals (`HingeRow`) at regular width, including portrait. Should switch to R1. |
| Settings | Mac adopts (#355); page replaced (#371) | The Mac Settings window panes flow column by column in two balanced columns (R7). The Settings page on iPad and Duo landscape and Android tablets/foldables, and the Windows Settings page at least 1100 epx wide, is a list/detail split instead ([split-panes](split-panes.md) R6). iPhone, Android phones, portrait and narrower Windows pages keep one column. |
| Full Rankings, Song Leaderboard, Song Band Leaderboard, Band Rankings | adopts (#353) | Two row-major columns when full width (R8); one column as a split's sub-page (beside Leaderboards or Song Detail). |
| Bands, Player Bands, Band Detail | follow-up | One column (the Mac Band Detail places Summary beside Statistics). |
| Rivals, All Rivals, Rival Detail, Rivalry, Player History | follow-up | One column of rows. |
| Licenses | exempt | Legal text in one readable column. |
| Home redirect | not applicable | No content. |
| Sheets and modals (Paths, Filter, Sort, What's New, Notifications) | not applicable | Form-sheet sized; one column. |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Leaderboards, Player Profile, Suggestions, Compete use two columns at any regular width | R1 (two columns in iPad and Duo portrait) | Adopt `WideColumns` per page in follow-up issues, as #353 did for the full leaderboards and #355 does for Settings. |
| Android and Windows have no wide-columns policy for pages other than Android Songs | R1–R5 | Android Songs adopted it (#581); Item Shop list, Search results and full leaderboards adopt the same `WideColumns`/`rememberWideColumns` in their own issues. Windows ports when its lane picks up #350's split issues. |
| Android `SongDetailRouteScreen(embedded = true)` and `SongRow(selected = true)` have no caller since Songs stopped splitting (#581) | — | Remove the embedded detail mode and the selected-row tint once no other split needs them. |

## Guards (`tools/pattern_guard.py`)

- [hinge-columns](hinge-columns.md) `apple-lazy-grid` keeps new page grids on the shared components; no wide-columns-specific guard yet.
