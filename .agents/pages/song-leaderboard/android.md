# Solo song leaderboard — Android notes

> **What:** Android state of the per-song solo leaderboard (`/songs/:songId/:instrument`). **Read when:** changing `ui/songdetail/SongLeaderboardScreen.kt` or `SongLeaderboardViewModel`. Behavior: [spec.md](spec.md); Song Detail: [song-detail/android.md](../song-detail/android.md).

## Implemented

- 25-row pages of `GET /api/leaderboard/{song}/{instrument}?top=25&offset=[&leeway=]` (`leeway` only while Filter Invalid Scores is on; `SongLeaderboardRouteScreen`, re-read when it changes); page count from `localEntries ?? totalEntries`; out-of-range pages corrected.
- Paging runs the shared load swap (issue #71): the rows fade out, the spinner `fst.song-leaderboard.loading` shows, the new page staggers in. Only the rows item swaps: the song header, instrument picker, pinned score and pager stay in place while the page loads (issue #93, checked: already so; `songLeaderboardKeepsItsHeaderPinnedScoreAndPagerWhilePaging` holds the `offset=25` read).
- The pinned score card shares the rows' reveal (issue #295): it carries the swap's `staggered(0)` modifier, so it fades out with the old page (keeping its slot) and fades back in with the new page's first row, on the first load and on every page change. Before this fix it had no fade: it popped in while the rows faded, and stayed solid while they swapped. Remove animations / Reduce Motion shows it with the rows at once. On first load the footer slot may start one frame (16 ms of 400 ms) after the list. Tests: `songLeaderboardPinnedScoreFadesInWithTheFirstRows`, `…PagingReRevealsThePinnedScoreWithTheNewRows` and `…PinnedScoreAppearsWithTheRowsUnderReduceMotion` compare the `fadeInUp` drift of the card and the first row. This deliberately departs from the web, whose portalled footer stays visible while a page loads.
- Footer edge (issue #93, web `useScrollFade`, [scroll-edge](../../patterns/scroll-edge.md) bottom chrome): this screen passes `fadeAboveFooter = true` to `RankingsBoardScaffold` (as do Song Band Leaderboard, Band Rankings and Full Rankings), so in a single pane rows are cleared beneath the floating "your score" card and pager and fade out over a linear 36 dp band ending at the footer's top (`BoardFooterEdgeFade.DEPTH_DP`/`STOPS`, R3; 40 dp with the Songs smoothstep before the #190 review; offscreen layer + `DstIn` gradient, draw phase only). The band weakens over the last 36 dp of scrolling so the last row is never faded. Increase Contrast and Reduce Transparency drop the ramp but keep the cut: rows end hard at the footer's top ([scroll-edge](../../patterns/scroll-edge.md) R7, issue #190; before, the cut went with the fade and rows showed through the gaps around the pinned card and pager). The list is clipped at the footer's top whenever `fadeAboveFooter` is set, so hidden rows leave touch and TalkBack (issue #104, below). Around a hinge the footer sits in the other pane, so nothing is masked. Pixel test: `BoardFooterFadeDrawUiTest`.
- The page is written back into the back-stack entry's route (`SongLeaderboardRoute.page` via `SyncRouteArguments`), so Back and a recreated entry restore it (spec native correction).
- Uses the rankings board scaffold and shared floating pager ([full-rankings/android.md](../full-rankings/android.md)): header (instrument icon + label) scrolls with the rows; the "your score" card and pager are anchored to the bottom above the bottom bar / floating toolbar, or on the far side of a hinge.
- End-of-list spacing (issue #293): at the end of the list the last row sits one list item gap (12 dp, `ROW_GAP_DP`) above the pinned score card, or above the pager when there is no score row. Before the fix the gap was 16 dp, and 24 dp without a score row, because `AnchoredFooter`'s `spacedBy(8.dp)` also spaced an empty footer slot. Now the 8 dp score→pager gap is added only when the footer has height (`gapBelowIfShown`). This applies to all three boards. Tests: `BoardFooterFadeDrawUiTest.lastRowSitsOneItemGapAbove…`. The header was already the Song Details `SongHeader`, with no gradient band, so the Apple header half of #293 doesn't apply to Android.
- Rows (`ScoreRow`: rank, name, FC/accuracy pill, score, and from a 700 dp row (`LeaderboardColumnLayout.STARS_BREAKPOINT`) the star images — `StarRating`, web `MiniStars` with `star_white`/`star_gold`, never Material glyphs) open the player's profile; the selected player's row opens Statistics (web `LeaderboardPage.tsx`) and is highlighted in place. Rows without a usable account ID are not interactive ("Profile unavailable").
- Selected player's pinned row: above the pager, built from the Profile lane's `SelectedProfileStore.scoreIndex` (no extra read; `SongScoreSpotlight.footer`), shown **only** when the score index and the page were observed under the same publication, and pinned on every page like the web and Apple (issue #307; before, it hid while the row was on the page). With Filter Invalid Scores on, an invalid best score is replaced by its next valid score and filtered rank (`PlayerScore.effective`), like the web. It is just the row (`SelectedScoreFooterRow`, no separate page-jump button since 7.9, so its columns align with the board). Its action follows [leaderboard-row](../../patterns/leaderboard-row.md) R7 (`SelectedRowAction.footer`): while the row is on another page it jumps there ("Jump to your position") and centres the highlighted row above the footer (`revealSelectedRow`, instant under Reduce Motion); once the row is on the shown page it opens Statistics. The decision waits for the requested page to be on screen (`swap.shown === board`), not the previous page still showing over a fresh load. Song Detail's appended row opens `SongLeaderboardRoute(page, navToPlayer = true)`, which reveals the row once. Tests: `songLeaderboardPinnedFooterJumpsToThePlayersPageThenOpensStatistics`, `songLeaderboardOpenedForThePlayerRevealsTheirRow`.
- TalkBack click labels come from `RankingNavigation.actionLabel` and `SelectedRowAction.label`: "Open your statistics" on the selected player's in-place row and on the pinned row while that row is on the page, "Jump to your position" on the pinned row otherwise, "Open profile" on the others (issues #104, #307).
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
| FST_Tablet landscape/portrait, font 2.0 | Drawer/rail, stars from 600 dp, footer capped at 720 dp and centred (shared scaffold; since issue #149 it spans the rows). |
| FST_Book_Fold / FST_Passport_Fold folded, half, unfolded | Half: rows in one pane, header, footer and pager in the other; nothing crosses the hinge. Folded/unfolded: single pane. |
| FST_TriFold folded, partial, unfolded | Folded (narrow) pager drops first/last; names ellipsized then (since issue #292 they scroll in their column); no clipping. |
| FST_Resizable phone, foldable, tablet, desktop | Compact → bottom bar, medium → rail, expanded → drawer; columns follow row width. |
| Reduced motion (default boot, animator scale 0) | Paging swaps without the fade/stagger. |

Fixed: the instrument switcher was a ~32 dp target with no role and a disabled state on one-chart songs; selected-row/footer TalkBack label said "Open profile" (both now covered by `LeaderboardsUiTest`). Robolectric now covers empty, failure + retry, out-of-range correction, boundary buttons, anonymous rows, single chart and the selected-row labels.

Fixed (TalkBack walk, FST_Phone): rows the fade hides beneath the footer stayed in the accessibility tree and touch, because Compose only drops a node that another node covers completely. TalkBack skipped the row wholly behind the pinned card (#8, #18) and focused invisible rows in the gaps around and below the pager instead of scrolling. With `fadeAboveFooter`, the list now reports a height that ends at the footer's top and clips there (`clipAboveFooter`; its viewport, padding and fade are unchanged), so TalkBack reads #1–#25 in order, scrolling as it goes. Test: `BoardFooterFadeDrawUiTest.rowsHiddenBeneathTheFooterLeaveTalkBack`. Band Rankings opted in with issue #116. Since issue #190 the Increase Contrast/Reduce Transparency hard edge keeps this clip too.

Observation (shared shell, not changed here): compact windows reserve the floating-toolbar band (`FLOATING_TOOLBAR_HEIGHT_DP + 2 × margin`) below content even on pages without page actions, so ~96 dp of backdrop shows between this pager and the bottom bar.

## Validation (issue #149, column alignment from issue #37, 2026-10)

Live public service, SFentonX selected, *Through the Fire and Flames* Lead (rank #28, so pinned on page 1). Checked that every row of the board, and the pinned row, shows the same columns at the same x positions (`LeaderboardSectionColumns`, `core/rankings/LeaderboardColumnLayout`).

| Configuration | Result |
| --- | --- |
| FST_Phone portrait/landscape, font 1.0/2.0 | Aligned: rank, name, score and accuracy columns (season from a 520 dp row, stars from 700 dp) match between the rows and the pinned row. At 2.0 rows stack. The pinned card and pager then take most of a portrait viewport; the list still scrolls. Song Detail's top-score card at 2.0: before the fix, `#9`'s name sat about 6.5 dp left of `#10` and the pinned `#28`. After it, all three share the 48 dp rank slot (14 sp measured at the non-linear 2.0 scale, 26 dp). |
| FST_Tablet landscape/portrait, font 1.0/2.0 | **Fixed:** the pinned row was capped at 720 dp and centred while the rows spanned the pane, so its rank, name, score and stars sat inward of every row above. It now spans the rows. At 2.0 (stacked), a bold `#28` widened its own rank slot and shifted the name about 6 dp; fixed. |
| FST_Resizable phone, foldable, tablet, desktop (1.0, desktop 2.0) | Compact/medium/expanded all aligned after the fix. Desktop (1920 dp wide at 160 dpi) rows and the pinned row share edges and columns. |
| FST_Book_Fold folded, half, unfolded | Folded is phone-like; unfolded as tablet. Half: the rows keep the leading pane (names about 72 dp, `MIN_NAME_WIDTH`, long names scroll per issue #292), and the pinned row and pager sit in the other pane with the same column set. At large text the hinge split is skipped by design (`rememberSingleColumn`), so it is one stacked pane. |
| FST_Passport_Fold folded, half, unfolded | As the book fold. Unfolded 1.0 and 2.0 aligned. |
| FST_TriFold folded, partial, unfolded | Before the fix, unfolded (1080 dp) showed the pinned row narrower than the rows. After: aligned in all three postures, 1.0 and 2.0. |
| Reduced motion (animator scale 0) | Recorded side by side with scale 1 on FST_Phone, paging 1 → 2 → 1 (live). Scale 1: rows and the pinned row fade out, spinner, then the new rows and the pinned row stagger in together. Scale 0: no fades or stagger, the page swaps at once. **Fixed:** at scale 0 the stale page-1 pinned `#28` stayed visible, readable by TalkBack and tappable over the spinner (`LoadSwap` skipped the content fade-out that otherwise hides it). At scale 1 it was invisible but still in the accessibility tree and touchable. `LoadSwap.pinnedContentModifier` now hides the pinned row (only; the pager stays usable, R4) while the spinner shows ([load-transition R2](../../patterns/load-transition.md)). Tests: `LeaderboardsUiTest.songLeaderboardHidesTheStalePinnedScoreWhileThePageLoads[UnderReduceMotion]`. |
| TalkBack (FST_Phone, `talkback_walk.py`) | Notifications, Profile, heading, "Lead. Drop down list", rows #1–#25 ("#N. name. score. Full combo, accuracy 100%. Button"), "#28. SFentonX … Button", the pager (First/Previous disabled, "Page 1 of 402", Next, Last), then the tabs. Every row is one 48 dp+ stop and the column change adds no stops. |

Material 3 ([layout and responsive](https://m3.material.io/foundations/layout/understanding-layout/overview)): a pane is "a layout container within the window" and a column "a vertical content block within a pane". The rows and the pinned row are one column of one pane, so they share edges. The pager keeps its natural width, centred, like the web `Paginator`. Deliberate deviations: 16 dp page margins on medium and wider windows (M3 suggests 24 dp; the app keeps 16 dp on every width, an existing cross-page choice), and the dark-only theme.

Tests: `LeaderboardsExpandedUiTest.expandedSongLeaderboardPinnedRowLinesUpWithTheRows` (w1280dp: row and pinned row share edges and `fst.score` right edges; the pager is narrower and centred), `ScoreAccuracyUiTest.largeTextNamesLineUpWhateverTheRankWidth` (font 2.0, ranks 9, 10 and a pinned 28). Both fail without the fix.

## Validation (issue #190, #93 behavior, 2026-10)

Live public service, SFentonX selected (#28), *Through the Fire and Flames* Lead, 402 pages. Checked #93's criteria: no bar title before scroll, the footer floats with no band, rows fade (or, under Increase Contrast, cut) above the pinned row and pager, and paging keeps the pager in place.

| Configuration | Result |
| --- | --- |
| FST_Phone portrait, font 1.0 | Pass: bar empty at the top, song title after the header scrolls away; rows fade over a linear 36 dp ramp above the pinned row (re-captured on the 36 dp build after the review); pager floats on the page background. |
| FST_Phone, Increase Contrast (`contrast_level 1.0`) | **Fixed:** rows showed beneath the pinned card and between the pager buttons (the clip went with the fade). Now rows end hard at the footer's top (R7). |
| FST_Phone font 2.0 / landscape | Pass. Font 2.0: two stacked rows between header and footer; the title stays off until the instrument row has gone too (header item). Landscape: the header, pinned row and pager fill the short viewport; rows scroll in (known, issues #104/#149). |
| FST_Tablet portrait / landscape (1.0, 2.0) | Pass: rail or drawer, fade above the pinned row. |
| FST_Resizable phone, foldable, tablet, desktop | Pass: compact bottom bar, medium rail, expanded drawer; fade above the pinned row in each. |
| FST_Book_Fold folded, half, unfolded (1.0, 2.0) | Pass. Half: rows in one pane, header, pinned row and pager in the other, nothing masked or across the hinge, bar stays empty (header never scrolls away). |
| FST_Passport_Fold folded, half (1.0, 2.0), unfolded | Pass, as the book fold; at large text the split is skipped (`rememberSingleColumn`). |
| FST_TriFold folded (1.0, 2.0), partial, unfolded | Pass. Folded at 2.0 the header, pinned card and pager take most of the narrow viewport (known trade-off); rows scroll. |
| Reduced motion (animator scale 0) | Pass: paging swaps without fades; the pinned row hides with the rows under the spinner (#295), the pager stays. |
| TalkBack order | Header → rows → pinned row ("Jump to your position", 48 dp) → pager in one pane; around a separating hinge (no TalkBack) rows pane first, then header → pinned → pager. |

The app is dark-only, so a light system theme renders the same. Reduce Transparency is an in-app setting covered by Robolectric. Observation: on a cold first launch after install, the song header and pinned row can take 20–60 s to appear (cold catalogue and profile reads over the emulator network; the bar shows the "Leaderboard" fallback title until then); they arrive without a reload.

Material 3 notes: top app bar title on scroll follows the "collapses on scroll" bar behavior; the footer has no shadow band ("Shadows are only used when needed for additional protection"); pager buttons are 48 dp targets; foldables keep content off the hinge ("Never place interactive content or critical information across the hinge area"). Deliberate deviations: dark-only theme and 16 dp margins (existing cross-page choices).

Tests: `SongLeaderboardJourneyTest` (connected; FST_Phone, FST_Book_Fold half), `BoardFooterFadeDrawUiTest` (Increase Contrast and Reduce Transparency hard cut, Robolectric).

Evidence (live service, dark theme; captures on the tracker issue's Android resolution update):

| Capture | AVD / posture | Font / accessibility | Shows |
| --- | --- | --- | --- |
| [unfolded, scrolled](https://github.com/user-attachments/assets/156fb924-909a-4e46-99f1-c3857f9ff33a) | FST_Book_Fold unfolded (expanded, rail) | 1.0, none | 36 dp linear ramp above the pinned row (after the #190 review) |
| [folded, Increase Contrast](https://github.com/user-attachments/assets/ce1bfa3b-8f28-49c1-bb60-bfc315534b18) | FST_Book_Fold folded (compact) | 1.0, `contrast_level 1.0` | R7 hard cut at the pinned row (36 dp build) |
| [paging motion](https://github.com/user-attachments/assets/0c8f29fb-f15e-425d-9d0c-32673e3a8df2) | FST_Book_Fold folded | 1.0, animations on | scroll under the footer, Next, Previous: pinned row and pager stay |
| [phone, Increase Contrast](https://github.com/user-attachments/assets/4881a546-5f45-4291-b2b4-0652d042ce4c) | FST_Phone portrait | 1.0, `contrast_level 1.0` | R7 hard cut (40 dp build, first pass) |
| [folded, scrolled](https://github.com/user-attachments/assets/d8325d10-bf20-4e2f-ac40-9b8349e99952) | FST_Book_Fold folded | 1.0, none | bar title after scroll (40 dp build, first pass) |
| [phone paging motion](https://github.com/user-attachments/assets/5c8e9410-5809-4a6a-bcde-8c55f6bddffc) | FST_Phone portrait | 1.0, animations on | paging keeps the pager (first pass) |
| [phone portrait sheet](https://github.com/user-attachments/assets/22e59e39-723d-4c7b-88af-536f50e7bbc0) | FST_Phone portrait | 1.0 and 2.0 | top and scrolled: bar title after the header, ramp above the pinned row, stacked rows at 2.0 |
| [phone landscape](https://github.com/user-attachments/assets/b5435eba-8371-4e7e-a4c7-e0c4dc10250e) | FST_Phone landscape | 1.0 | header fills the short viewport; after it scrolls, one row fades into the pinned row |
| [tablet sheet](https://github.com/user-attachments/assets/45182992-2d76-4f8b-9a37-cbe7bea7395a) | FST_Tablet landscape and portrait | 1.0 and 2.0 | scrolled: drawer or rail, ramp above the pinned row |
| [resizable compact/medium](https://github.com/user-attachments/assets/3fb6ef20-a80e-48c9-97b3-aa7b46a05a83) | FST_Resizable phone, foldable | 1.0 | bottom bar, rail; top and scrolled |
| [resizable expanded](https://github.com/user-attachments/assets/2d071af3-726c-482d-adbb-da3fb4ce7cf9) | FST_Resizable tablet, desktop | 1.0 | drawer; top and scrolled |
| [book fold sheet](https://github.com/user-attachments/assets/7a99c0ae-b68d-4c77-a84a-a93361924d5c) | FST_Book_Fold half, unfolded | half 1.0, unfolded 2.0 | half: rows pane and footer pane split at the hinge; unfolded 2.0 ramp |
| [passport fold sheet](https://github.com/user-attachments/assets/fc83182c-02d2-4d44-894a-fe1b69e6720b) | FST_Passport_Fold folded, half, unfolded | 1.0, half at 2.0 | split at 1.0, single pane at 2.0 (`rememberSingleColumn`) |
| [trifold sheet](https://github.com/user-attachments/assets/2e5e33ea-2dea-4ea4-9f05-e064e41738a1) | FST_TriFold folded, partial, unfolded | 1.0, folded at 2.0 | compact, medium and expanded; folded 2.0 trade-off |
| [phone paging, animations on](https://github.com/user-attachments/assets/893c5a1a-2938-4bdb-a1f0-38ce50ba32d9) | FST_Phone portrait | 1.0, animations on | 36 dp build: scroll, bar title, Next and Previous keep the pinned row and pager |
| [phone paging, animator scale 0](https://github.com/user-attachments/assets/75daea95-26d2-47f4-9677-fdaf231242cd) | FST_Phone portrait | 1.0, animator scale 0 | same sequence; rows swap instantly |

Every row of the validation table has a capture above (the #190 review asked for the full matrix).
