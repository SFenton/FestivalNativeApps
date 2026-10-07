# Wide columns

> **What:** the app-wide rule for when a page's rows or cards show in two columns: in wide landscape windows (iPad landscape, iPhone Duo unfolded in landscape, a wide Mac surface) and never in portrait. It covers reading order, headings, the Duo hinge and reflow, and lists every page that adopts it. **Read when:** making a page or sheet two-column, changing when Songs or Search pair their rows, or adding a page (add it to the audit below).

Status: **current**, 2026-10-08. Provenance: #350 (split from #332); generalizes the Songs landscape grid (`SongGridPolicy`, #312, #321).

## Intent

A list of rows that spans a landscape iPad or an unfolded Duo is mostly empty space with long eye travel. Two columns show twice as many results without changing what a row is. In portrait the same window is narrow enough that one column reads better. The owner's words (#332): "two-col on Duo unfolded/MacOS/iPad in landscape mode; Duo unfolded portrait/iPad portrait should be single-page (should replicate across every page in app)". The rule is therefore based on window shape and size class, not on the device or the page.

## Web source (behavior reference)

None. The web pages are a single column, including the search modal (`FortniteFestivalWeb/src/components/modals/SearchModal.tsx`) and Songs. This is a native extension for wide screens that the owner requested. The row content, copy and order stay as on the web.

## Rules

1. **R1. When.** Two columns only when the window is landscape (`DeviceLayout.orientation`, from the window, never from the page frame: the iPad keyboard shortens a portrait page into a wide box), its width and height size classes are both regular (`windowWidthClass`, `heightClass`), and the page has room for two 320 pt columns plus a 12 pt gutter inside its 16 pt row margins (≥ 684 pt; `WideColumns.count(layout:width:)`). Everything else is one column: iPhone, any portrait window, a folded Duo, and compact Split View, Slide Over or Stage Manager tiles. On the Mac the page's own surface decides (`WideColumns.count(size:)`): it must be wider than tall and wide enough, because Mac windows and sheets resize freely and have no device orientation. HIG Layout: "Choose layout from size classes, not device type/idiom or orientation" (should). The size classes and the measured width are the gate. The landscape condition is the owner's explicit choice (portrait stays one column even when it would fit), which wins over a *should* (supported deviation, #350). HIG Mac Catalyst: "split a single column into multiple columns; use regular-width and regular-height size classes, reflowing content side by side as the window resizes" (should).
2. **R2. Row-major order under full-width headings.** Items flow left then right, then down (`WideColumns.rows`). A short last row keeps its card at column width and fills the rest with clear space. Section headings, hints, empty, failed and loading states, footers and "View all" buttons span both columns. Each card keeps its own button, accessibility identifier and label, so VoiceOver reads the same sequence in one or two columns ([load-transition](load-transition.md) R6 stagger order follows the flattened index).
3. **R3. On the Duo the columns meet at the hinge.** Rows draw through `HingeRow(spacing:hinge: .page)`. The gutter sits on `DeviceLayout.splitHinge`, which is the active fold in book pose, otherwise the reported or synthesized hinge midline when flat, so the two columns meet at the hinge in every pose. Each side fills its own physical side, as in the on-demand split ([hinge-columns](hinge-columns.md) R1, agent decision #343). HIG Designing for iPhone Duo: "Expand the existing layout with space" (should); Duo layout guidance (WWDC T463, `apple-hig` duo checklist): "Prefer even grid column counts".
4. **R4. Reflow in place.** Rotation, a fold change or resizing a window re-chunks the same loaded items. It never starts a new request, shows a spinner, changes a row's identity or replays a fade-in ([back-keeps-place](back-keeps-place.md), [load-transition](load-transition.md)). Page models live outside the column decision (Search's `GlobalSearchModel` is owned by the shell).
5. **R5. One policy.** Pages call `WideColumns` and `HingeRow`; they never compare widths, idioms or devices themselves. `SongGridPolicy` delegates to it. A page that cannot adopt the rule (a content-sized grid, a table, a split pane) is listed in the audit with its reason.
6. **R6. Mac Search opens at a two-column size in a wide window.** In a landscape Mac window at least 960 × 700 pt, the Search sheet opens at 880 × 640 pt, so its results show two columns. Otherwise it opens at 620 × 680 pt with one column, the web modal's shape. The sheet stays resizable (minimum 560 × 520), and its columns follow its live size (R1). HIG Sheets (macOS): "Present a sheet in a reasonable default size" (should).

## Agent decision (#350, 2026-10-08): a flowing grid under full-width headings

Question: what does two-column Search look like? Posted on the issue.

| Option | What you see | Guidance (strength) | Precedent | Trade-offs |
|---|---|---|---|---|
| **A (chosen)** | Results flow into two columns in reading order; "Songs", "Players" and "Bands" headings span both columns. | HIG Duo "Expand the existing layout with space" (should); T463 "Prefer even grid column counts"; HIG Layout "Choose layout from size classes" (should). | Apple Songs `SongGridPolicy` (two cards per row under full-width section headers). | Works for every scope and any result count; order matches portrait. |
| B | Songs in one column; Players and Bands in the other. | Same clauses. | None. | A column is empty for single-scope searches or when a category has no results; columns are very uneven; order changes on rotation. |
| C | Keep one column. | — | Web modal (single column). | Ignores the owner's request. |

Chose **A**. The owner may override it with `/choose B` or `/choose C`.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Policy (when, widths, row chunking, Mac sheet size) | `apple/Sources/FestivalUI/App/Layout/WideColumns.swift` `WideColumns` | — (not yet; out of the Apple lane for #350) | — |
| Two-up row meeting at the hinge | `apple/Sources/FestivalUI/App/Layout/HingeColumns.swift` `HingeRow` with `Hinge.page` | — | — |
| Songs grid | `apple/Sources/FestivalUI/Features/Songs/SongsScreen.swift` `SongGridPolicy` (delegates) | — | — |
| Search results | `apple/Sources/FestivalUI/Features/Search/GlobalSearchView.swift` `GlobalSearchResults` | — | — |
| Mac Search sheet size | `apple/Sources/FestivalUI/Mac/MacRootView.swift` `MacRootView` (`searchSheetSize`) | — | — |

## Page audit (#350)

Status per page: **adopts** (follows R1–R5), **exempt** (a layout the rule does not govern, with the reason), **follow-up** (should adopt; not changed in #350).

| Page / surface | Status | Today (Apple) |
|---|---|---|
| Search results (`global-search`) | adopts | Two columns per R1, at the hinge (R3); Mac sheet R6. |
| Songs | adopts | `SongGridPolicy` → `WideColumns`, `HingeRow(.page)`. The Mac keeps one row per song, a sortable table ([songs-section-index](../controls/songs-section-index/spec.md) owns its layout). |
| Song Detail | exempt | Content-sized adaptive grids (`HingeGrid`, Intensity and instrument cards) already fill width in any orientation. |
| Item Shop | exempt | Adaptive even-column card grid (`ShopGridPolicy`, [hinge-columns](hinge-columns.md) R2). |
| Statistics | exempt | Adaptive stat tile grid (`StatTileGridLayout`). |
| Leaderboards | follow-up | Two `HingeGrid` columns whenever the width class is regular, including iPad portrait. Should switch to R1. |
| Player Profile | follow-up | Instrument tiles in two columns at regular width, including portrait. Should switch to R1. |
| Suggestions | follow-up | Two columns at regular width, including portrait. Should switch to R1. |
| Compete | follow-up | Leaderboards beside Rivals (`HingeRow`) at regular width, including portrait. Should switch to R1. |
| Settings | follow-up (#355) | One readable-width column. |
| Full Rankings, Song Leaderboard, Song Band Leaderboard, Band Rankings | follow-up (#353) | One leaderboard table column. |
| Bands, Player Bands, Band Detail | follow-up | One column (the Mac Band Detail places Summary beside Statistics). |
| Rivals, All Rivals, Rival Detail, Rivalry, Player History | follow-up | One column of rows. |
| Licenses | exempt | Legal text in one readable column. |
| Home redirect | not applicable | No content. |
| Sheets and modals (Paths, Filter, Sort, What's New, Notifications) | not applicable | Form-sheet sized; one column. |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Leaderboards, Player Profile, Suggestions, Compete use two columns at any regular width | R1 (two columns in iPad and Duo portrait) | Adopt `WideColumns` per page in follow-up issues, as #353 and #355 do for leaderboards and Settings. |
| Android and Windows have no wide-columns policy | R1–R5 | Port when those lanes pick up #350's split issues. |

## Guards (`tools/pattern_guard.py`)

- [hinge-columns](hinge-columns.md) `apple-lazy-grid` keeps new page grids on the shared components; no wide-columns-specific guard yet.
