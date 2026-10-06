# Player Bands — Android notes

> **What:** what the Android Player Bands page implements. **Read when:** changing `ui/bands/BandListScreens.kt` (`PlayerBandsScreen`) or `PlayerBandsViewModel`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implemented

- `PlayerBandsRoute(accountId, displayName?, group?)` → `GET /api/player/{accountId}/bands?group=&page=&pageSize=25` (pure read). `group` is a `PlayerBandGroup.wireId` (web `?group=`; `PlayerBandGroup.fromWireId`, unknown → All): the player page's per-group "View All Bands (N)" opens the list on Duos, Trios or Quads, See All on All (issue #312; debug route `playerBands:<id>[:<group>]`). The account must be 1–128 `[A-Za-z0-9_-]` (`BandText.isValidMemberId`, which also admits fixture IDs); otherwise the page shows "Player not found" and sends nothing.
- Top bar `<Name>'s Bands`: route name → selected player (same account) → the account's own member row → `Player Bands`. Subtitle `<Group> · N bands`.
- Group filter: Material 3 single-choice segmented buttons (All · Duos · Trios · Quads) instead of the web filter sheet; switching returns to page 1. At large text (`isLargeText`) the selected checkmark and most side padding give way to the label (`LARGE_TEXT_SEGMENT_PADDING`, 4 dp; height stays ≥ 48 dp; selection still shows as the filled container), so "Quads" fits a 411 dp phone at 200% (issue #117; it showed "Qua…"). A newer load cancels an older one, so a late response never shows an old group or page. A group or page change runs the shared load swap (issue #71; spinner `fst.player-bands.loading`), and the cards stagger in. The pager stays visible and usable below the spinner (last loaded page count, like web placeholder data), so a newer page tap supersedes the pending one; it hides only for the first load and on failure ([load-transition R4](../../patterns/load-transition.md), issue #149; test `BandsUiTest.playerBandsPagerSupersedesAPendingPage`).
- Band cards (glass, whole card tappable, trailing `RowChevron` from operator batch 7.3): distinct members with instrument icons, size pill, `N appearances` → `BandRoute(bandId, membersLabel, bandType, teamKey)`. TalkBack: one merged **Button** reading `Members, Size, N appearances` (`playerBandAnnouncement`) with the action "Open band", the song band leaderboard convention. At large text each member's name moves under its icons as a whole word and the appearances wrap under the size pill (`FlowRow`), instead of breaking "SFento/nX" and "142/appearances" in two-column cards. Shared with the player page's Bands section. Anonymous members (empty `accountId`) show "Unknown User" and never collapse into each other.
- One column under TalkBack or at large text (`rememberSingleColumn`, the repo-wide grid rule; the band grid lacked it before issue #117): cards read top to bottom in one readable-width (≤ 840 dp) column and long names fit, with no hinge split. Otherwise the adaptive grid (`BandLayout.grid`): as many ≥320 dp columns as fit (1 on phones and covers, 2 on book/passport inner and tablet portrait, 3+ wide). With a flat fold where two columns fit, exactly two columns whose gutter is the fold ±16 dp, so no card straddles the crease. Across a **separating** hinge (half-open book/passport fold, `BandLayout.listSplit`) `PlayerBandsLayout` puts the subtitle and segments in a leading pane ending at the hinge (`fst.player-bands.list.controls-pane`) and the cards, states and pager in one column on the trailing side; before issue #117 the full-width subtitle, segments and pager straddled the hinge.
- Pager: First/Previous/`page / pages`/Next/Last (48 dp targets, spoken "Page X of Y"), hidden for one page. A page past the end reloads the last page.
- States: loading, empty (`No bands found` / `No <group> have been recorded for this player yet.`), failure (`ServiceStatusView` at a fixed height inside the grid, because a lazy item cannot host its unbounded vertical scroll).

## IDs

`fst.player-bands.screen`, `.list`, `.list.controls-pane` (separating hinge only), `.subtitle`, `.loading`, `.group-picker`, `.group.<all|duos|trios|quads>`, `.row.<bandId>`, `.empty`, `.error`, `.invalid`, `.page-first|page-previous|page-info|page-next|page-last`.

## Validation (issue #117)

Live service (SFentonX, 125 bands / 5 pages; Duos 24 = one page, no pager), debug build, one emulator at a time. Tests: `PlayerBandsLayoutUiTest` (fold split, single pane, 200% segments/names/appearances, card semantics) and `BandsUiTest` journeys (plus two columns on a wide window, one at 200%).

| Configuration | Finding |
|---|---|
| FST_Phone portrait/landscape | 1 column portrait, 2 in landscape; pager 48 dp, First/Prev disabled on page 1; Duos hides the pager. 200%: "Quads" ellipsized (fixed); top-bar title ellipsizes (shared `FestivalScreen`, TalkBack reads it whole); landscape at 200% leaves little room between the shell bars (shell). |
| FST_Book_Fold / FST_Passport_Fold | Folded = phone. Unfolded: 2 columns meeting at the fold. Half-open: segments and subtitle straddled the hinge (fixed: controls pane). 200%: names broke mid-word in two-column cards (fixed: one column at large text, which also drops the hinge split, as every `rememberSingleColumn` page does). Connected `BandsSettingsJourneyTest` passes half-open. |
| FST_TriFold | Folded = phone; partial = one wide column set. Unfolded (two flat folds): the grid centred two columns on the off-centre fold and left ~280 dp of the leading panel empty (fixed: an unbalanced flat fold keeps the natural grid, as `BandLayout.panes` already did). 200% unfolded: one column. |
| FST_Tablet | Landscape 2 columns beside the permanent drawer; portrait 2 columns with the rail; 200% mid-word name breaks (fixed: one column at large text). |
| FST_Resizable | phone / foldable / tablet / desktop presets reflow 1 → 2 → 4 columns; desktop at 200% keeps 4 columns (width / fontScale ≥ 840, the `rememberSingleColumn` rule) without clipping. |
| Light theme | App is dark-only (design/android.md), unchanged by the system setting. |
| TalkBack (real, FST_Phone) | Top bar → subtitle → segments ("Selected. All. Radio button. 1 of 4") → cards ("SFentonX + Phankie.ToT, Duos, 142 appearances. Button"; before: no role) → pager. Connected `BandsSettingsJourneyTest` passes. |
| Reduced motion | At animator/transition/window scale 0 a group switch lands on the new cards with no fade or stagger (shared `rememberLoadSwap`); marquee names stay static. |

## Open

- Entry points from the player page: its Bands section ("See all", "View all bands (N)"; [player-profile/android.md](../player-profile/android.md#bands-section)). No `?name=` carry-through (band search is blocked).
