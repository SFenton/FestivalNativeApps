# Solo song leaderboard — Android notes

> **What:** Android state of the per-song solo leaderboard (`/songs/:songId/:instrument`). **Read when:** changing `ui/songdetail/SongLeaderboardScreen.kt` or `SongLeaderboardViewModel`. Behavior: [spec.md](spec.md); Song Detail: [song-detail/android.md](../song-detail/android.md).

## Implemented

- 25-row pages of `GET /api/leaderboard/{song}/{instrument}?top=25&offset=[&leeway=]` (`leeway` only while Filter Invalid Scores is on; `SongLeaderboardRouteScreen`, re-read when it changes); page count from `localEntries ?? totalEntries`; out-of-range pages corrected.
- Paging runs the shared load swap (issue #71): the rows fade out, the spinner `fst.song-leaderboard.loading` shows, the new page staggers in. Only the rows item swaps: the song header, instrument picker, pinned score and pager stay in place while the page loads (issue #93, checked: already so; `songLeaderboardKeepsItsHeaderPinnedScoreAndPagerWhilePaging` holds the `offset=25` read).
- Footer edge (issue #93, web `useScrollMask`): this screen passes `fadeAboveFooter = true` to `RankingsBoardScaffold` (the other boards keep the default `false`), so in a single pane rows are cleared beneath the floating "your score" card and pager and fade out over a 40 dp eased band ending at the footer's top (`BoardFooterEdgeFade`, offscreen layer + `DstIn` gradient, draw phase only). The band eases away over the last 40 dp of scrolling so the last row is never faded. Increase Contrast and Reduce Transparency keep the previous hard edge (rows pass under the opaque card). With the fade on, the list is also clipped at the footer's top, so hidden rows leave touch and TalkBack (issue #104, below). Around a hinge the footer sits in the other pane, so nothing is masked. Pixel test: `BoardFooterFadeDrawUiTest`.
- The page is written back into the back-stack entry's route (`SongLeaderboardRoute.page` via `SyncRouteArguments`), so Back and a recreated entry restore it (spec native correction).
- Uses the rankings board scaffold and shared floating pager ([full-rankings/android.md](../full-rankings/android.md)): header (instrument icon + label) scrolls with the rows; the "your score" card and pager are anchored to the bottom above the bottom bar / floating toolbar, or on the far side of a hinge.
- End-of-list spacing (issue #293): at the end of the list the last row sits one list item gap (12 dp, `ROW_GAP_DP`) above the pinned score card, or above the pager when there is no score row. Before the fix the gap was 16 dp, and 24 dp without a score row, because `AnchoredFooter`'s `spacedBy(8.dp)` also spaced an empty footer slot. Now the 8 dp score→pager gap is added only when the footer has height (`gapBelowIfShown`). This applies to all three boards. Tests: `BoardFooterFadeDrawUiTest.lastRowSitsOneItemGapAbove…`. The header was already the Song Details `SongHeader`, with no gradient band, so the Apple header half of #293 doesn't apply to Android.
- Rows (`ScoreRow`: rank, name, FC/accuracy pill, score, and from a 700 dp row (`LeaderboardColumnLayout.STARS_BREAKPOINT`) the star images — `StarRating`, web `MiniStars` with `star_white`/`star_gold`, never Material glyphs) open the player's profile; the selected player's row opens Statistics (web `LeaderboardPage.tsx`) and is highlighted in place. Rows without a usable account ID are not interactive ("Profile unavailable").
- Selected player off the page: a pinned row above the pager built from the Profile lane's `SelectedProfileStore.scoreIndex` (no extra read; `SongScoreSpotlight.footer`), shown **only** when the score index and the page were observed under the same publication. With Filter Invalid Scores on, an invalid best score is replaced by its next valid score and filtered rank (`PlayerScore.effective`), like the web. Like the web footer it is just the row and opens Statistics (no page-jump button since 7.9, so its columns align with the board).
- TalkBack click labels come from `RankingNavigation.actionLabel`: "Open your statistics" on the selected player's in-place row and pinned row, "Open profile" on the others (issue #104; they all said "Open profile" before).
- Instrument switcher (`InstrumentSwitcher`, web instrument switcher): with more than one Settings-visible chart it is a 48 dp `Role.DropdownList` ("Switch instrument") opening a `DropdownMenu` whose current item is `selected` and carries a trailing check, like the rankings' top-bar pickers. With a single chart it is plain text, not a disabled control (issue #104).

## IDs

`fst.song-leaderboard.list`, `.instrument`, `.instrument-menu`, `.instrument.<wireId>`, `.loading`, `.row.<accountId|rank-N>`, `.spotlight-footer`, `.bottom-bar`, `.pager`, `fst.stars`, `fst.score` (score cell; aligned per section), `.page-first|page-previous|page-info|page-next|page-last`; failure: `fst.service-status.title|retry`.

## Open

- No entry-totals subtitle; no season pill column.
- The spec's header song title → Song Detail link is not a separate control; Back returns to Song Detail (deliberate, all native platforms).

## Validation (issue #104, 2026-10-03)

Live public service, SFentonX selected, *Through the Fire and Flames* Lead (rank #27, page 2). The app is dark-only by design ([design/android.md](../../design/android.md)), so system light theme renders the same.

| Configuration | Result |
| --- | --- |
| FST_Phone portrait/landscape, font 1.0/2.0, dark/light | Paging, pinned #27 footer on page 1, in-place highlight on page 2, instrument menu. Font 2.0: rows stack, title wraps, nothing clips. Landscape: header and instrument fill the short viewport, rows scroll under the pager. |
| FST_Tablet landscape/portrait, font 2.0 | Drawer/rail, stars from 600 dp, footer capped at 720 dp and centred (shared scaffold). |
| FST_Book_Fold / FST_Passport_Fold folded, half, unfolded | Half: rows in one pane, header, footer and pager in the other; nothing crosses the hinge. Folded/unfolded: single pane. |
| FST_TriFold folded, partial, unfolded | Folded (narrow) pager drops first/last; names ellipsize; no clipping. |
| FST_Resizable phone, foldable, tablet, desktop | Compact → bottom bar, medium → rail, expanded → drawer; columns follow row width. |
| Reduced motion (default boot, animator scale 0) | Paging swaps without the fade/stagger. |

Fixed: the instrument switcher was a ~32 dp target with no role and a disabled state on one-chart songs; selected-row/footer TalkBack label said "Open profile" (both now covered by `LeaderboardsUiTest`). Robolectric now covers empty, failure + retry, out-of-range correction, boundary buttons, anonymous rows, single chart and the selected-row labels.

Fixed (TalkBack walk, FST_Phone): rows the fade hides beneath the footer stayed in the accessibility tree and touch, because Compose only drops a node that another node covers completely. TalkBack skipped the row wholly behind the pinned card (#8, #18) and focused invisible rows in the gaps around and below the pager instead of scrolling. With `fadeAboveFooter`, the list now reports a height that ends at the footer's top and clips there (`clipAboveFooter`; its viewport, padding and fade are unchanged), so TalkBack reads #1–#25 in order, scrolling as it goes. Test: `BoardFooterFadeDrawUiTest.rowsHiddenBeneathTheFooterLeaveTalkBack`. Band Rankings opted in with issue #116. Full Rankings and the Increase Contrast/Reduce Transparency hard edge still let rows pass visibly under the footer (open: the same skip applies to a row wholly behind the opaque card there).

Observation (shared shell, not changed here): compact windows reserve the floating-toolbar band (`FLOATING_TOOLBAR_HEIGHT_DP + 2 × margin`) below content even on pages without page actions, so ~96 dp of backdrop shows between this pager and the bottom bar.
