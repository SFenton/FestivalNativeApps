# Hinge columns

> **What:** where two-column layouts (grids, side-by-side rows) put their centre gutter and where full-width titles wrap when a foldable is partially folded with a vertical fold (iPhone Duo book pose, Android book posture). **Read when:** adding a grid, a two-up row or a full-width title to a page that can show on a foldable's inner display, or changing column counts on the Duo inner display.

Status: **current**, 2026-10-07. Provenance: #343 (split from #332), #365 (R8), #366 (Song Detail band previews); Android precedent from the Rivals, Shop, Songs and Settings hinge work.

## Intent

A partially folded device has a physical crease. Content that straddles it is hard to read and to tap, and a grid that splits at half its own width (left of the iPhone Duo vertical bar) puts its gutter beside the crease rather than on it. While a vertical fold crosses a layout, columns meet at the fold and titles stay on the side they start on. Fully open, folded and on every other device, the flat layout is unchanged; unfolding reflows the same views in place and reloads nothing.

## Web source (behavior reference)

The web app has no fold. This is a native platform requirement (HIG Designing for iPhone Duo; Material foldable guidance), not web parity. The flat layouts keep their web-derived column counts.

## Rules

1. **R1. Columns meet at the fold.** While an active vertical fold (Apple `DeviceLayout.foldFrame`, Android a separating vertical `FoldingFeature`) crosses a grid or two-up row, the leading columns end at the fold clearance and the trailing columns start after it. The clearance is the fold's width, at least the layout's normal gutter, centred on the fold. Each side fills its own physical side, so the sides may differ in width (the iPhone Duo vertical bar stays inside the trailing side, like the on-demand split panes in [split-view](../design/apple/split-view.md)). HIG Designing for iPhone Duo: "If the system doesn't move a custom component automatically, use reserved-region APIs to keep important elements clear of the center" (should).
2. **R2. Even column counts.** Apple keeps the same column count on each side: half the flat count for a fixed grid, or as many as fit the narrower side for an adaptive grid. HIG Designing for iPhone Duo: "Prefer a layout container that adapts automatically, and even grid column counts" (should). Android's `ShopColumnPolicy` may fit each pane separately (approved variant, Material guidance).
3. **R3. Titles stay on their side.** A full-width section title or subtitle that starts on the leading side of the fold wraps before it, at least 16 pt clear of the fold's centre line; it never truncates the landmark ([section-headers](section-headers.md) R3, R10). A title that starts within 160 pt of the fold keeps its width.
4. **R4. Only what's necessary.** No split without an active fold through the layout's interior; a horizontal fold, a layout entirely on one side (a split pane, a half column), a side narrower than 120 pt (Apple `HingeColumns.minimumSide`), or an adaptive grid that is one flat column keeps the flat layout. An adaptive grid that already shows two or more flat columns always splits, one column a side at least, even when a side is a little under its minimum (Song Detail's 360 pt cards get ~356 pt beside a 40 pt fold): its flat gutter would otherwise sit beside the fold with a card across it (#343). HIG Designing for iPhone Duo: "Avoid extreme changes: move only what's necessary to keep elements visible and easy to tap" (should).
   - Approved variant ([wide-columns](wide-columns.md) R3, #350): a row that is already two columns flat (Songs grid, Search results) passes `HingeRow(hinge: .page)`, so its gutter sits on the hinge in book pose like the on-demand split divider. Other rows keep `.fold` (only an active fold).
5. **R5. Reflow in place.** Fold changes swap column widths on the same grid or row view; they never change view identity, restart a load or replay a fade-in.
6. **R6. One component per platform.** Grids and two-up rows use the canonical component below and pass their flat columns; pages never measure the fold themselves. Every state of a layout follows the policy, including accessibility-size fallbacks: an eager replacement for a lazy grid uses `HingeEagerGrid`, never an `HStack` of equal cells (#343 review). A new `LazyVGrid` on Apple is a review failure unless it is listed under the guard's allowed files.
7. **R7. Owner-approved: flat splits at the midpoint of free space (#361, 2026-10-07).** Owner: "When completely unfolded, midpoint should still be midpoint of free space, not hinge. When partially folded, midpoint should be hinge. This is an override from me, app-wide." Only a partially folded device (Apple book pose, `pose == .partiallyFolded`; Android a **separating** `FoldingFeature`) divides on the hinge. Fully unfolded (flat), `.page` rows, on-demand split panes, Song Detail grids and every other two-column layout divide at the midpoint of the free content area beside the bar or rail, never on the flat hinge line; a flat reported or synthesized hinge midline is not a split position. Folding and unfolding reflows in place (R5, #346). This supersedes the `.page` variant's flat-hinge midline (#350). HIG Designing for iPhone Duo: "Folding region | Present when partially open"; Material 3 foldable postures: "Flat (unfolded): Treat as Medium or Expanded window class based on width"; "Half-opened (book): Split content at the hinge". Android reads only separating folds everywhere (`rememberHingeSplit`, `HingeColumns`, `AdaptiveCardGrid`, `BandLayout`); Bands anchored on a balanced flat fold until #361.
8. **R8. Cells start at the top of their row.** Cards of different heights that share a row align to the row's top edge, folded, flat and at every text size: `HingeGrid` top-aligns any column that names no alignment (`HingeColumns.topAligned`; `GridItem` otherwise centres a shorter cell in its taller neighbour's row), and `HingeEagerGrid`, `HingeRow` and `StatTileGridLayout` place cells top-leading. Pages pass plain columns and never add their own `.top`. #365: Song Detail's Pro Lead card started lower than the taller Pro Bass card beside it because its columns named no alignment. HIG Layout: "Align components to aid scanning and communicate organization" (should).
9. **R9. A page's card groups share one column rule.** Card sections that follow a grid on the same page use the same grid component and columns, not full-width rows under it. Song Detail's Duos, Trios and Quads previews are a second `SongDetailCardGrid` after the instrument cards (#366): they had been a plain stack copied from the web's single-column band block, so on iPad, the Mac and the unfolded Duo each preview spanned the page. Android (`BandLayout`, Duos | Trios, Quads) and Windows (`BandBoards`) already paired them.

## Agent decision (#343, 2026-10-07): each side fills its half; P2 overridden

The owner asked that, partially unfolded, "the 'vertical split' of the app should be the hinge, not the 50/50 of visible content to the left of the rail". That overrides delegated decision P2 (Shop cards may scroll under the fold in book pose, [duo.md](../design/apple/duo.md)). Open question: equal column widths placed symmetrically about the hinge, or each side filling its physical side?

| Option | What you see | Guidance (strength) | Precedent | Trade-offs |
|---|---|---|---|---|
| **A (chosen)** | Leading columns run from the content edge to the fold; trailing columns from the fold to the vertical bar, ~84 pt narrower. | HIG Duo "use reserved-region APIs to keep important elements clear of the center" (should); "move only what's necessary" (should). | Apple `OnDemandSplitPolicy` panes end at the fold's edges; Android `HingeColumns.resolve` (unequal sides). | Columns differ in width in book pose; content edges stay where they are. |
| B | Equal columns symmetric about the hinge, padding the leading edge by the bar's width. | Same clauses; HIG "split columns adjust width/margins for inner-display symmetry" (describes system split views). | None in the native apps. | An empty ~84 pt strip at the leading edge; grids no longer line up with full-width cards above them. |

Chose **A**: the existing native split and the Android precedent already fill each side, and it moves less. Owner may override with `/choose B`.

## Agent decision (#366, 2026-10-07): band previews start a new row in the same columns

Question: owner, "Why aren't Duos/Trios/Quads leaderboards preview multi-col?" Should the band previews continue the instrument cards' flow, or start their own rows in the same columns?

| Option | What you see | Guidance (strength) | Precedent | Trade-offs |
|---|---|---|---|---|
| **A (chosen)** | Duos, Trios and Quads start on a new row under the instrument cards, in the same columns (Duos \| Trios, then Quads). | HIG Layout: "Group related information/functions using negative space, containers, or separators" (should); HIG Designing for iPhone Duo: "Expand the existing layout with space" (should). | Web band block after the instrument grid (`SongDetailPage.tsx` `bandSections`); Android `BandLayout` and Windows `BandBoards` pair them the same way. | When the instrument count does not fill the last row, that row keeps an empty cell. |
| B | Band previews continue the instrument grid's flow. | Same clauses. | Apple Leaderboards overview (band cards continue its instrument `HingeGrid`). | No empty cell, but a band preview can sit beside an instrument card. |
| C | Keep one full-width column. | — | Web layout. | Ignores the owner's question. |

Chose **A**: same column rule, the web's grouping and order, and the Android and Windows layout. Owner may override with `/choose B` or `/choose C`.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Pure policy (band, per-side counts, title width) | `apple/Sources/FestivalUI/App/Layout/HingeColumns.swift` `HingeColumns` | `android/app/src/main/java/com/festivalscoretracker/android/core/rivals/HingeColumns.kt` `HingeColumns`; `core/shop/ShopColumns.kt` `ShopColumnPolicy` | — (no foldable target) |
| Card grid | `apple/Sources/FestivalUI/App/Layout/HingeColumns.swift` `HingeGrid` (Statistics instrument tiles, Leaderboards, Suggestions, Item Shop, Profile bands, Song Detail Intensity, instrument cards and Duos/Trios/Quads previews); `Features/Profile/PlayerStatGrid.swift` `StatTileGridLayout` (Global Statistics tiles) | `android/app/src/main/java/com/festivalscoretracker/android/ui/rivals/AdaptiveCardGrid.kt` `AdaptiveCardGrid`; band cards and Band Detail panes `android/app/src/main/java/com/festivalscoretracker/android/core/bands/BandLayout.kt` `BandLayout` (`grid`, `panes`, `listSplit`) | — |
| Eager card grid (no lazy layout) | `apple/Sources/FestivalUI/App/Layout/HingeColumns.swift` `HingeEagerGrid` (Song Detail instrument cards and band previews at accessibility sizes, `SongDetailCardGrid`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/rivals/AdaptiveCardGrid.kt` `AdaptiveCardGrid` | — |
| Two-up row | `apple/Sources/FestivalUI/App/Layout/HingeColumns.swift` `HingeRow` (Songs two-card rows, Songs profile-panel rows ([songs-profile-panel](songs-profile-panel.md) R6), Compete halves) | `android/app/src/main/java/com/festivalscoretracker/android/ui/settings/HingeSplit.kt` `rememberHingeSplit` | — |
| Two-up row | `apple/Sources/FestivalUI/App/Layout/HingeColumns.swift` `HingeRow` (Songs two-card rows and Search result rows with `Hinge.page`, Compete halves) | `android/app/src/main/java/com/festivalscoretracker/android/ui/settings/HingeSplit.kt` `rememberHingeSplit` | — |
| Title side (R3) | `apple/Sources/FestivalUI/App/Layout/HingeColumns.swift` `staysOnHingeSide` (in `FestivalSectionHeader`, so `FestivalGlassSection` too) | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FoldLane.kt` `foldLaneItem` / `FoldLane` ([section-headers](section-headers.md) R10, #343) | — |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple `DeviceLayout.splitHinge` still returns the flat reported or synthesized hinge midline, so flat Duo `.page` rows and on-demand splits divide on the hinge | R7 | Apple lane of #361 (Android is compliant) |

## Guards (`tools/pattern_guard.py`)

- `hinge-columns/apple-lazy-grid`
