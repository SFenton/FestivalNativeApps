# Windows accessibility results

> **What:** per-page Windows accessibility status (Axe.Windows, keyboard, Narrator, contrast themes, text size, motion/transparency, in-app settings) and open gaps. **Read when:** changing a Windows page or control, or re-running the accessibility pass. Tools and the Narrator script: [windows.md](windows.md#accessibility); design rules: [design/windows.md](../design/windows.md#accessibility).

Evidence: `tools/windows/a11y_matrix.py` against the anonymized fixture (`rivals_fixture.py`) on Debug and NativeAOT Release (`--exe aot`, automation mode), 3840×2160 at 150%. Sizes are `compact` 500×800, `medium` 900×700 and `wide` 1440×900 epx. Committed samples are `windows/reports/screenshots/a11y-*.png`. Legend: ✅ pass · ⚠️ pass with a noted gap · — not applicable.

## Checks

| Check | How |
|---|---|
| Axe | `--scan`: Axe.Windows 2.4.2 over every top-level window of the process; 0 errors at compact, medium and wide (Debug), and at medium on AOT |
| Tab | `--tabs 30`: focus stays in the window, no repeated stop, order title bar → pane → page |
| Keys | `journeys/a11y-keyboard.json` (`assertfocus`): Songs toolbar → rows; Up/Down within row lists; Tab across cards; Esc returns focus from Sort, Filter, Profile, Notifications, Quick Links and Paths; first-run dialog closes on Esc; Ctrl+1…7/Ctrl+comma; Ctrl+E; Alt+Left from a text field; title-bar order at each size. All sizes on Debug, medium on AOT |
| Narrator | Tree audit (names, roles, headings, landmarks, groups); unit-tested load/result/error notifications; operator script in [windows.md](windows.md#narrator-manual-script-operator) |
| HC | Aquatic, Desert, Dusk and Night sky at medium on every page: theme colours behind content, no artwork, text legible, focus visible |
| Text | 225% at medium on every page, and at compact on the core pages; 150% on the core pages |
| Motion | Animation effects off, transparency off, in-app Reduce Motion + Disable Animated Artwork + Save Data, and More Contrast + Less Transparency, on the core pages |
| Touch targets | Issue #72 (2026-10-02): UIA bounds of the title-bar Search/bell/profile, Songs Sort/Filter/Jump and Quick Links at compact, then a `ui_journey.py` coordinate `click` at the centre and 18.5 epx above and below it (fresh launch each), passing when the button's flyout (`ProfileFlyout`, `Panel`, `SortFlyout`, `FilterFlyout`, a Quick Links item) or Search page appears. Coordinates are relative to the title bar's UIA origin, not the window rect (which includes the invisible resize border). Before: Search 32×32, profile 36×36, tools 32 tall; 12 of 21 clicks missed. After `FSTMinTargetSize`: every button ≥ 40×40, no overlapping bounds, 21/21 activate. Markup guard: `HitTargetMarkupTests` |

## Pages

Tab = distinct stops in a 30-press walk (compact/medium/wide). Core pages (Songs, Song Detail, Leaderboards, Rivals, Settings, Search, the profile flyout and first run) also pass every Motion mode.

| Page | Axe C/M/W | Tab | Keys | HC ×4 | Text 225% |
|---|---|---|---|---|---|
| Songs (anonymous / selected) | ✅✅✅ | 9/10/10 | ✅ | ✅ | ✅ (C+M) |
| Songs Filter (web sections, percentile open) | ✅✅✅ (+AOT) | 20/20/20 | ✅ | ✅ | ✅ |
| Song Detail + Paths dialog | ✅✅✅ | 16/17/17 | ✅ | ✅ | ✅ |
| Song Leaderboard | ✅✅✅ | 8/10/10 | ✅ | ✅ | ✅ (C/M/W, also 200%; display 100%/150%, issue #197) |
| Player History (Song Detail Score History, issue #198) | ✅✅✅ | 7/9/9 | UIA (locked console) | ✅ (Night sky, Desert: chart roles) | ✅ (200%: axes scale) |
| Song Band Leaderboard | ✅✅✅ (+live, #196) | 8/10/10 | UIA only (#196) | ✅ | ✅ (+200% C+M) |
| Item Shop (grid, list, filter, states) | ✅✅✅ (+live, #206; shop-offers states #224) | 5/8/8 (grid one stop) | ✅ (`kb-shop-*`) | ✅ | ✅ (200% C+M, #206) |
| Suggestions | ✅✅✅ (AOT crash fixed; filter, empty, end-of-mix, loading, syncing, denied, #205) | 10–15 (20-press, #205) | ✅ (arrows between rows, #205) | ✅ | ✅ (200%; display 100%/150%, #205) |
| Leaderboards + Quick Links | ✅✅✅ (+live, #207) | 20/21/21 | ✅ | ✅ | ✅ (C+M; rows stack, #207) |
| Full Rankings / Rank By menu | ✅✅✅ (+live, #208) | 9–13/12–15/12–15 | ✅ (#208) | ✅ | ✅ (+200% C/M/W) |
| Band Rankings (+ Band Detail column ≥1100) | ✅✅✅ (+AOT, #209) | 9/12/12 | ✅ (#209) | ✅ | ✅ (+200% C/M/W, #209) |
| Rivals / Compete | ✅✅✅ (+live, #200; #213: +200%, display 100%/150%) | 9/10/10 | ✅ `kb-compete-order` | ✅ | ✅ (+200% C+M) |
| All Rivals (+ Rival Detail column ≥1100) | ✅✅✅ (+AOT, +live, #200, #201) | 6/9/15 | UIA only (#200, #201) | ✅ | ✅ (+200%) |
| Rival Detail | ✅✅✅ (+snap/max, #202) | 12/14/14 | ✅ | ✅ | ✅ (200% C/M/W; display 100%/150%, #202) |
| Rivalry | ✅✅✅ (+live, #200, #203) | 8/11/11 | UIA only (#200, #203) | ✅ | ✅ (+200% C+M, #200, #203) |
| Statistics / Player Profile | ✅✅✅ (+live, #199) | 7–8/10–11 | UIA only (#199) | ✅ (#204 chart outlines) | ✅ (tiles scale; +200% C+M; #204 chart gutters) |
| Bands (Band not found, #211) | ✅✅✅ (+live) | 5/8/8 | ✅ | ✅ | ✅ (+200% C/M/W) |
| Player Bands | ✅✅✅ | 8/11/11 | — | ✅ | ✅ |
| Band Detail | ✅✅✅ (+live, #212) | 12/15/15 | ✅ | ✅ | ✅ (+200% C+M) |
| Search | ✅✅✅ (+snap/max, live, #234) | 6–8/7–9/7–9 (#234) | ✅ (#234) | ✅ (#234 Desert) | ✅ (+200% C+M, display 100%/150%, #234) |
| Settings | ✅✅✅ | 30/30/30 | ✅ | ✅ | ✅ |
| Licenses | ✅✅✅ (+dialog, #215) | 21/23/23 (dialog 3) | ✅ (#215 journey) | ✅ | ✅ (+200% C/M/W, display 100%/150%, #215) |
| Profile flyout | ✅✅✅ | 2 | ✅ | ✅ | ✅ |
| Notifications flyout | ✅✅✅ (+live, #229) | 1 (list) | ✅ (#229) | ✅ (#229) | ✅ (#229, C+M) |
| Quick Links menu | ⚠️✅ (issue 8) | 1 (menu) | ✅ | ✅ | ✅ (pane titles wrap, #230) |
| First-run dialog | ✅✅✅ | 4 | ✅ | ✅ | ✅ |
| What's New dialog (launch, Settings replay) | ✅✅✅ (+max/snap, #235) | 2 (notes, Dismiss) | ✅ (`kb-whats-new-*`, #235) | ✅ (#235) | ✅ (200% C+M, #235) |

## Fixed in this pass

- Only the first item of every `ItemsRepeater` was reachable by keyboard (e.g. Settings chart toggles, ranking rows 2+, and every Leaderboards/Rivals card after the first).
- Duplicate sibling names across cards (Axe) were fixed with named `AccessibleGroup` cards. Unnamed view-profile buttons and the unnamed `MenuFlyout` presenters were given names.
- The app gained Narrator notifications for slow loads, result counts, errors and Quick Links jumps. It also gained Main and Search landmarks, Ctrl+digit section accelerators with access keys, and Alt+Left from text fields. The empty TitleBar tab stop was removed.
- Contrast themes now hide the artwork and use the theme's window colour (the `HighContrastChanged` subscription crashed the desktop app). At ≥150% text the title-bar caption is dropped, and stat tiles scale with the text size.
- `/statistics` deep links showed Coming Soon. The NativeAOT Suggestions page crashed on open because `Rows` was an `IReadOnlyList` bound to `ItemsSource`.

## Second pass (FST-win-next, 2026-09-29)

Scope: everything changed since win-a11y (win-shell2, win-detail2, win-next). Evidence: `a11y_matrix.py --scan --tabs 30` on all 31 pages × compact/medium/wide (Debug); the 12 changed pages (Songs selected, Songs Filter, Song Detail, Leaderboards, Full/Band Rankings, All Rivals, Band Detail, Player, Settings, Item Shop, Licenses) at medium under all four contrast themes, text 150% and 225%, Animation effects off and transparency off (96 runs, 0 Axe errors, no focus leaving the window, no repeated stops); `a11y-keyboard.json` at all three sizes (30/30); NativeAOT Release for the new surfaces at medium and wide.

Fixed: the Songs Filter's Global toggles and Item Shop `Expander`s had no UIA name; chart axis labels (Band Rank History, player charts) were exposed, because Raw on their panel does not hide children, and one clipped at the 1440×900 viewport edge failed `BoundingRectangleSizeReasonable`; Esc in the profile flyout's Find Player box (now an `AutoSuggestBox`) no longer closed the flyout; two keyboard journeys ran anonymously although the Songs Filter needs a profile (win-pwa gap 5) and the Paths keyboard journey waited for a removed ID. Issues 3 and 7 below no longer reproduce (Player Bands compact and Leaderboards wide scan clean).

## Third pass (FST-win-unify, 2026-09-29)

Scope: the unified leaderboard row and pager (operator batches 7.7/7.4), Filter Invalid Scores + Over CHOpt Threshold on Songs, contrast roles, and the Android accessibility learnings mirrored to Windows ([android-accessibility.md](android-accessibility.md)). Evidence: `a11y_matrix.py --scan --tabs 30` on the 14 changed pages (Songs selected, Songs Filter, Song Detail, song leaderboard, Player History, song band leaderboard, Shop, Suggestions, Leaderboards, Full/Band Rankings, Player, Player Bands, Settings) × compact/medium/wide: 0 Axe errors, no repeated stops; Songs Filter medium (scroll step missed) and Player Bands compact (focus left the window, issue 6) passed on re-run. `a11y-keyboard.json` 13/13 at medium. Desert and Night sky contrast themes on Songs, Song Detail, song leaderboard, Leaderboards, Suggestions, Player, Shop and the Songs Filter (incl. the new Over CHOpt switch): 0 Axe errors.

Android learnings applied: every leaderboard row (and each score-history row) is one Button stop whose name reads the whole row, with its rank/name/score/pill parts Raw so Narrator scan mode doesn't read them twice; chart legends hide each label (Raw on a panel does not hide its children); the two CHOpt Settings subsection titles are headings (level 3). Already equivalent on Windows: side-by-side cards are named `AccessibleGroup`s (TalkBack reading groups), 48 epx rows (touch targets), pager buttons are Buttons with names. Not applicable: TalkBack's on-screen-only traversal of a half-open fold (Narrator scrolls virtualized lists itself).

## Song Detail validation (issue #195, 2026-10)

Scope: Song Detail only, fixture matrix plus the live public service (SFentonX on "Never Back Down": Leaving Tomorrow in the Shop, two Lead history bars, eight instrument cards, Duos/Trios/Quads). Results per configuration in [song-detail/windows.md](../pages/song-detail/windows.md#validation-issue-195). Axe 0 errors everywhere: compact, medium, wide, snap-left and maximized; light and dark system theme; Desert and Night sky; text 200%; display 100% and 150%; live and fixture. Keyboard journeys `kb-detail-back`, `kb-paths-dialog-esc` (all sizes) and `kb-detail-compact-previews` (compact: every card's row and View Full stop, arrows between rows, Shift+Tab back) pass. Fixed: Tab skipped virtualized cards at compact, Trios/Quads cards clipped (uniform grid), focus hidden under the pinned header (WCAG 2.4.11), High Contrast chart axes/selection and Item Shop surface, chart axis titles over the ticks at 200% text.

## Song band previews validation (issue #264, 2026-10)

Scope: Song Detail's Duos/Trios/Quads previews (issue #64), on `song_band_preview_fixture.py` (`a11y-song-band-preview.json`: demo rows, ten rows per size with in-place and appended selected bands, loading, failure, scrape freeze, invalid response, navigation, keyboard) and live (SFentonX and anonymous on "Where My Wookiees At?"). Results per configuration in [song-detail/windows.md](../pages/song-detail/windows.md#validation-issue-264). Axe 0 errors at compact, medium, wide, maximized and both snaps; Desert, Night sky, light and dark theme, text 200%, display 100% and 150%; live and fixture. Fixed: row names dropped the members' instruments and read accuracy before FC; View Full Leaderboard's name didn't start with its visible label (WCAG 2.5.3, instrument cards too); the accuracy pill wasn't contrast-aware and rows kept the old theme after a contrast switch; the selected band row and the shared accent View Full / View All buttons drew text backplates inside the Highlight fill; at 200% text the team score truncated beside the badges (now `BandScoreFooterPanel`, badges wrap under the score, Song Band Leaderboard rows too). The active band loading ring reads "Busy …", so tests use `fst.song-detail.band-loading.<type>`.

## Leaderboard row columns validation (issue #242, 2026-10-04)

Scope: the shared row-column fitter (issue #37) on every board, checked against the live public service with SFentonX. Results per configuration are in [song-leaderboard/windows.md](../pages/song-leaderboard/windows.md#validation-issue-242-2026-10-04).
- **Live matrix:** `a11y_matrix.py --live --scan --tabs 25` gave 0 Axe errors, no focus leaving the window and no repeated stops on six pages at compact, medium and wide: song board, Leaderboards, Full and Band Rankings, Song Detail and Score History.
- **Modes (0 Axe errors):** Desert, Night sky, text 200%, display 100%/150%, text 200% + display 150% and the light system theme. UIA bounds show every row and the pinned row on shared columns at all sizes, maximized and both snaps.
- **Fixed:**
  - Switching a contrast theme with a board open left the rows' code-set brushes (translucent fill, purple pinned row, gold badge) and the pager's disabled-button aliases in the old theme, under system backplates.
  - Under a contrast theme, the pinned row's FC badge drew WindowText on Highlight.

## Item Shop validation (issue #224, 2026-10-04)

Scope: the Shop Offers control only. Results per configuration are in [shop-offers/windows.md](../controls/shop-offers/windows.md#validation-issue-224-2026-10-04). `a11y_matrix.py --scan --tabs 30 --only shop` gave 0 Axe errors at compact, medium and wide (6/10/10 Tab stops: compact has no List/Grid toggle). At medium it also gave 0 Axe errors under Desert, Night sky, light and dark system theme, text 200%, and display 100% and 150%. No run had focus leaving the window or repeated stops. The live public service (anonymous) was checked at compact, medium, wide, maximized and snap-left, and under Desert, text 200% and display 150%. Fixed: under a contrast theme, WinUI's automatic adjustment had repainted the badge text as WindowText on a backplate inside the Highlight pill (`HighContrastAdjustment=None` while it is on, as `LeaderboardEntryRow` does). The active ProgressRing reads "Busy Loading Item Shop" (WinUI prefix), so tests use `fst.shop.loading`.

## What's New validation (issue #235, 2026-10-04)

Scope: the What's New dialog only. Results per configuration are in [whats-new/windows.md](../controls/whats-new/windows.md#validation-issue-235-2026-10-04). `a11y_matrix.py --scan --tabs 6 --pages journeys/a11y-whats-new.json` gave 0 Axe errors for the launch dialog and the Settings replay. That held at compact, medium, wide, maximized and snap-left, and at medium under Desert, Night sky, light and dark system theme, text 200% and display 100% and 150%. Text 200% also gave 0 at compact. Every run had 2 Tab stops (notes, Dismiss), no focus leaving the window and no repeated stops. The keyboard pages `kb-whats-new-dismiss` and `kb-whats-new-replay` pass at all three sizes. `ui_journey.py journeys/whats-new.json` drives every reachable state.

Fixed: the notes scroller was not a tab stop, so the keyboard could not scroll long notes. It now opens focused and is named after the title. Dismiss and the headings gained automation IDs. Backdrop-click journeys need an unlocked console (`journeys/whats-new-pointer.json`).

## Notifications validation (issue #229, 2026-10-04)

Scope: the title-bar bell and flyout only. Results per configuration are in [notifications/windows.md](../controls/notifications/windows.md#validation-issue-229-2026-10-04). `a11y_matrix.py --scan --pages journeys/a11y-notifications.json --fixture notifications_fixture.py` gave 0 Axe errors for loaded, empty, not generated and failed at compact, medium and wide. Loaded also gave 0 at maximized and snap-left, and loaded and failed gave 0 at medium under Desert, Night sky, light and dark system theme, text 200% and display 100% and 150%. At text 200% the loaded and scrolled-to-end pages also gave 0 at compact. No run had focus leaving the window. The keyboard pages `kb-notifications-rows` and `kb-notifications-esc` pass at all three sizes, and `notifications_journey.py` drives every reachable state. Scanning after Esc (focus back on the bell, tooltip open) shows only open item 8.

Fixed:
- Each row read as an unnamed list item followed by a nested group, and the row IDs never reached UIA. The `ListViewItem` now carries the name and ID (`ContainerContentChanging`).
- State IDs sat on panels, which have no UIA peer, so they now sit on text.
- Under contrast themes the flag pills kept their web colours and the section headers stayed white.
- With nothing focusable (loading, empty, not generated), focus rested on an unnamed "Popup" window, which is now named "Notifications".
- At 200% text the unread `InfoBadge` count outgrew its 16 epx circle and covered the bell glyph. The badge now keeps a fixed text size (`IsTextScaleFactorEnabled="False"`), like the system's own badges.

## Song Band Leaderboard validation (issue #196, 2026-10-03)

Evidence: `a11y_matrix.py --scan` for `song-band-leaderboard` at compact/medium/wide, then at medium under all four contrast themes, text 200% (C+M), text 225%, no animations and no transparency: 0 Axe errors in all 12 runs. The live public service (temp wrapper without `--base-url`) gave 0 Axe errors under Desert, Night sky and text 200%. Both band journeys pass.

Fixed:
- The rows were templated `ListViewItem`s without a name or ID, and an inner named `Group` repeated the row. Every rank, name, score, pill, star and icon part was a separate Narrator scan stop, and `InstrumentIcon`'s inner `Image` leaked as an unnamed image. Now each row is one stop, with a name built in `ContainerContentChanging` that includes each member's instruments and score.
- The accuracy pill kept its navy fill under system text in Desert.
- `.empty` and `.error` sat on a panel and a UserControl, which have no UIA peer.

Constraint: the lane host's console was locked for this pass, so SendInput Tab walks and keyboard journeys could not run. Keyboard order was checked through UIA focusability, and actions were driven through UIA patterns.

## Item Shop validation (issue #206, 2026-10-03)

Scope: the Item Shop only. Results per configuration in [shop/windows.md](../pages/shop/windows.md#validation-issue-206). `a11y_matrix.py --scan --tabs 30` on `shop`, `shop-list`, `shop-filter`, `shop-filter-empty`, `shop-hidden`, `shop-empty`, `shop-error` and `shop-details-unavailable` at compact/medium/wide; Desert and Night sky, light and dark system theme, display 100% and 150%, text 200% (C+M), snap-left and maximized; and `--live` against the public service. 0 Axe errors in every run, no focus outside the window, no repeated stops. `kb-shop-grid`, `kb-shop-grid-open` and `kb-shop-list` pass.

Fixed:
- The tile grid (`ItemsRepeater`, `TabFocusNavigation="Local"`) was one Tab stop per tile: 124 on the live Shop. It is now one stop with arrow keys inside (Fluent `GridView` model; [design/windows.md](../design/windows.md#accessibility) Collections rule updated).
- The List/Grid View toggle stayed on the error, empty and hidden states.
- The toggle was 32 epx next to the 40 epx Filter button.
- The Leaving Tomorrow pill was clipped at 200% text in compact windows.
- "Item Shop Is Hidden" was not a heading.

## Player Profile validation (issue #199, 2026-10-03)

Fixture evidence: `a11y_matrix.py --scan` ran on `player`, `statistics`, `player-lead` (the Lead section, scrolled into view with the `reveal:` step) and `player-empty`. Sizes were compact, medium and wide, then medium under all four contrast themes, text 225%, no animations and no transparency, then text 200% at compact and medium. Every run had 0 Axe errors.

Live public-service evidence used `SFentonX`, with Statistics checked with that player selected. It gave 0 Axe errors at compact, medium, wide, maximized and snapped, and also under Desert, Night sky and text 200%. The 7 player journeys pass. Per-configuration findings are in [player-profile/windows.md](../pages/player-profile/windows.md#validation-issue-199-2026-10-03).

Fixed:
- In stat tiles and percentile rows, the value, label, pill and count texts were exposed beside the tile or row name, so Narrator scan mode read each value twice. They are now Raw.
- Tile hover/press surfaces and the neutral/gold percentile pills used hard-coded brushes, so contrast themes kept the dark navy and gold fills. They now use `FSTCardSurfacePointerOver/Pressed`, `FSTCardStrokePointerOver`, `FSTNeutralPill*` and `FSTGoldPillFill`, which map to system colours under High Contrast.
- When the section repeater recycled a rank-history chart for another instrument, its Older/Newer buttons kept the previous instrument's AutomationIds.

## Bands validation (issue #211, 2026-10-03)

Evidence: `a11y_matrix.py --scan --tabs 20` for `bands` at compact, medium, wide, snap-left and maximized; at medium under all four contrast themes, light and dark app mode, text 225%, display 100% and 150%, no animations and no transparency; and at text 200% at all three sizes. The live public service gave the same results for the five sizes, text 200%, Desert, Night sky, light mode and display 100%/150%. Axe reported 0 errors in every run. Keyboard journeys `kb-bands-not-found-back` and `kb-bands-not-found-back-button` pass at all sizes. Fixed: `fst.bands.screen`/`.not-found` were on panels with no UIA peer, and the failure was not announced on load. Results per configuration: [bands/windows.md](../pages/bands/windows.md#validation-issue-211-2026-10-03).

## Full Rankings validation (issue #208, 2026-10-03)

Evidence: `a11y_matrix.py --fixture tools/windows/rankings_fixture.py --scan --tabs 30` with `journeys/full-rankings.json` (8 states) at compact, medium, wide, maximized, snap-left and snap-right; Desert and Night sky × compact/medium × 6 states; Aquatic, Dusk, light theme, display 100%/150% at medium; text 200% at C/M/W. Keyboard: `journeys/full-rankings-keyboard.json` (pager, menus + Esc, Your page, rows) 12/12 at C/M/W. Live public service (temp wrapper without `--base-url`, SFentonX on Lead and Pro Lead) at all five sizes plus contrast and text 200%. Axe 0 errors except item 8. Results per configuration in [full-rankings/windows.md](../pages/full-rankings/windows.md#validation-issue-208).

Fixed: pager buttons lost focus to the window during the load swap; Your page left focus on its collapsed button and did not reveal the row, and focused rows could sit under the floating footer (WCAG 2.4.11); translucent floating cards, a hard-coded White ring and a system-backplated selected row under contrast themes; names truncated to "…" at 200% text on compact (the songs label now moves under the name and, when that is not enough, the row stacks on two lines, WCAG 1.4.4); missing Retry ID.

## Band Detail validation (issue #212, 2026-10-03)

Evidence: `a11y_matrix.py --scan --tabs 30` for `band-detail` at compact, medium, wide, snap-left and maximized, then at medium under Desert, Night sky, light and dark system theme, display 100% (wide) and 150%, and text 200% (C+M): 0 Axe errors in every run. The live public service (temp wrapper without `--base-url`) gave 0 Axe errors at C/M/W, Desert and text 200%. The keyboard journey `kb-band-detail-stats` passes at all three sizes; wheel scrolling can't run on the locked console, so deep shots use `scrollinto`. Per-configuration results: [band-detail/windows.md](../pages/band-detail/windows.md#validation-issue-212).

Fixed:
- Tab never reached the linked Best Song Rank card: the stat `ItemsRepeater` lacked `TabFocusNavigation="Local"` (Tab stops 10/14/14 → 12/15/15).
- The Rank By `ComboBox` had no visible label; it now has a `Header`, which is also its UIA name.
- The percentile pill kept its purple fill and white text under contrast themes (now ButtonFace/ButtonText with an outline).
- The shared `RankHistoryGraph` (Band Detail, Player Profile) clipped its left tick labels at 200% text and drew gridlines in an 8% white that disappears under contrast themes. Gutters and the date band are now measured from the scaled labels, gridlines/axes/bar outlines use WindowText under contrast themes, and the chart redraws on `ColorValuesChanged`/`TextScaleFactorChanged`. History rows grow with the text.

## Leaderboards validation (issue #207, 2026-10)

Evidence: `a11y_matrix.py --scan --tabs 30` on `leaderboards`, `leaderboards-selected`, `leaderboards-unranked`, `leaderboards-spotlight-failed` and `leaderboards-rank-by-menu` (new pages) at compact/medium/wide; at medium under Desert, Night sky, light and dark system theme, display 100% and 150% and Animation effects off; text 200% at compact and medium; the live public service (SFentonX) the same way. 0 Axe errors on every page except WinUI's popup host (open item 8). Tab order: shell, Rank By, Quick Links, then per card its row group (one stop, arrows between rows) and View All, in reading order; no repeats, focus never left the window. `leaderboards_journey.py` drives every reachable state at all three sizes. Results per configuration in [leaderboards/windows.md](../pages/leaderboards/windows.md#validation-issue-207).

Fixed:
- View All's UIA name ("View All Lead Rankings") didn't contain its visible label "View All Rankings (3)" (WCAG 2.5.3); now "View All Rankings (3), Lead".
- A failed card exposed an empty countdown text element.
- Text 200%: names trimmed to "…" at compact and vanished at medium (rankings rows never drop their songs label). Cards now use fewer, wider columns as text grows, rankings rows move the songs label (then the rating) under the name as in #208, and score rows that still can't fit stack their values under the name (shared row: the song leaderboard and Score History benefit too).

## Difficulty Meter validation (issue #216, 2026-10-03)

Evidence: `a11y_matrix.py --scan --tabs 12` for `song-detail` at compact, medium and wide, then at compact and wide under Desert, Night sky, light theme, text 200%, display 100% and 150% (plus Aquatic at wide): 0 Axe errors and 12 tab stops in every run (the meter isn't a stop). UIA journeys `tools/windows/journeys/difficulty-meter.json` (`--large-catalogue`) cover levels 1–7 and the 99 sentinel. Live public-service screenshots at C/M/W, maximized, snap-left, Desert (switched while the app was open), Night sky, text 200% and 100%/150% scale. Per-configuration results: [difficulty-meter/windows.md](../controls/difficulty-meter/windows.md#validation-issue-216-2026-10-03).

Fixed:
- Desert's WindowText and GrayText bars were only ~1.8:1 apart; under contrast themes, unfilled bars are now GrayText outlines (shape, not colour alone).
- The bars kept their old colours after a contrast-theme switch while the app was open; they now re-apply on `ColorValuesChanged`.
- The unavailable state drew seven empty bars at 40% opacity (the skill says never put `Opacity` on system-colour brushes); it now shows "Difficulty unavailable", and a recycled meter resets its automation ID.

## Score Accuracy validation (issue #220, 2026-10-03)

Evidence: `a11y_matrix.py --pages tools/windows/journeys/score-accuracy.json --fixture tools/windows/score_accuracy_fixture.py --scan --tabs 15` (chart, offscreen, preview, keyboard and resize pages) at compact, medium, wide, maximized and both snaps, then at compact, medium and wide under Desert, Night sky, light and dark theme, display 100% and 150%, and text 200%: 0 Axe errors in every run, with each badge state asserted by name and column alignment. Live public-service screenshots of "Through the Fire and Flames" Lead. Per-configuration results: [score-accuracy/windows.md](../controls/score-accuracy/windows.md#validation-issue-220-2026-10-03).

Fixed:
- A full combo without an accuracy showed no badge; it now shows a gold `FC` and reads "full combo, accuracy unavailable".
- Graded pills were 2 epx narrower per side than the gold FC outline (WinUI paints the background inside the border by default); the tint now fills the outer edge as the web's border-box does.
- At 200% text the gold FC badge drifted ~2 epx left of the column (the skew pivot was a fixed 10 epx); it now pivots on the badge centre.
- At 200% text a row realized while scrolling kept its one-line height after stacking, so its score and badge drew over the next row (live board, compact); rows now fit their columns in `MeasureOverride`.

Open: Shift+Tab back into an `ItemsRepeater` row list focuses the last realized row, not the last-focused one (list-level, all boards).

## Songs Sort validation (issue #218, 2026-10-03)

Evidence: `a11y_matrix.py --only songs-sort --scan --tabs 14` at compact, medium and wide, then at compact and wide under Desert, Night sky, light theme, text 200%, display 100% and 150%: 0 Axe errors and 3 tab stops cycling inside the flyout in every run. Keyboard journeys `kb-songs-order`, `kb-songs-sort-esc` and the new `kb-songs-sort-groups` (Tab between the groups, Down changes direction live, Enter on Reset, Esc returns focus to the button). The `songs_journey.py` `songs-sort-*` scenarios cover every reachable state at C/M/W. Live public-service screenshots at C/M/W, maximized, snap-left and with Item Shop sort. Per-configuration results: [songs-sort/windows.md](../controls/songs-sort/windows.md#validation-issue-218-2026-10-03).

Fixed:
- The two direction rows were loose `RadioButton`s: two extra Tab stops (4 in the flyout) and no group name. They are now a `RadioButtons` group with a "Direction" header (3 stops; arrows move inside), like Sort By.
- Narrator read the Sort button as "Sort Songs" only, and the arrow glyph in its label isn't spoken meaningfully; it now has HelpText with the applied sort ("Year, descending").
- The Sort paused, Shop filter paused, profile paused and score-filter paused InfoBars and the Item Shop section headings had no automation IDs (`fst.songs.sort-paused`, `fst.songs.shop-section.*` from the spec); they have them now.
- The non-default gold Sort/Filter label tint didn't follow a contrast-theme switch while the page was open; it now re-applies on `ColorValuesChanged`.

A run on this shared host left the Desert contrast theme on system-wide with no pending restore, so later modes rendered under it. Check `sysset` state before trusting light-theme/text/scale screenshots, and re-run them after restoring.

Seen, out of scope: with live data (three Shop buckets) at the medium preset, the Songs **Jump** zoomed-out index truncates "Leaving Tomorrow" and "Not In Shop" to "Leavi…" and "Not I…". The Songs Jump index owns that layout, not Sort. Fixed by issue #231: cells are sized to the widest label ([songs-section-index/windows.md](../controls/songs-section-index/windows.md)).

## Artwork Background validation (issue #217, 2026-10-03)

Evidence: `a11y_matrix.py --scan --tabs 30` with `journeys/artwork-background*.json` (animated, Reduce Motion, Disable Animated Artwork, Save Data, dialog and minimized `not-visible`, song cover, no art via `artwork_fixture.py`) at compact, medium, wide, snap-left and maximized; Desert and Night sky, Animation effects off, light and dark theme, text 200% and display 100%/150% at C/M/W. 0 Axe errors in every run. The live public service passed the same ItemStatus checks at all five sizes, under Desert, Night sky, text 200% and display 100%/150%. Per-configuration results: [artwork-background/windows.md](../controls/artwork-background/windows.md#validation-issue-217).

The backdrop stays `AccessibilityView.Raw` (decorative: no Narrator stop, no Tab stop). Its state is exposed only to automation, as ItemStatus on a raw-view peer (`fst.shell.artwork-background`); `uiwin` searches the raw view for `assertstatus`.

Fixed: without art the dim scrim darkened the brand surface to near-black (the web shows the undimmed purple); a late crossfade completion could blank the shown cover after a dialog or occlusion resumed playback.

## Star Rating validation (issue #221, 2026-10-04)

Evidence: `a11y_matrix.py --scan --tabs 20 --fixture tools/windows/star_rating_fixture.py` with `journeys/a11y-star-rating.json` (song leaderboard with 1, 3, 5, 6, 7, 0 and missing stars; profile gold Avg Stars) at compact, medium, wide, maximized and snap-left; Desert, Night sky, Aquatic, light and dark theme, display 100%/150% at compact and wide; text 200% at C/M/W. 0 Axe errors in every run after the fixes; the stars are never a Tab stop. UIA journeys `journeys/star-rating.json` assert each state's `fst.star-rating.<state>` ID, ItemStatus and the row names. Live public-service screenshots at the same sizes and themes. Per-configuration results: [star-rating/windows.md](../controls/star-rating/windows.md#validation-issue-221-2026-10-04).

Fixed:
- Six-star scores were read as "6 stars" or "gold stars"; every site now reads "5 gold stars" (`StarRating.Announcement`), and 7+ draws gold.
- `StarRow` had no automation peer; it is now one `Image` named with the count.
- The gold ring kept its old brush after a contrast-theme switch.
- Profile: the instrument tiles were focusable siblings of the Overview tiles with the same names ("Songs Played: 2", Axe `SiblingUniqueAndFocusable` at wide, display 100%/150%); each instrument section is now a named group.

## Profile Selection validation (issue #226, 2026-10-04)

Evidence: `a11y_matrix.py --scan --tabs 12 --fixture tools/windows/profile_fixture.py` with `journeys/profile-selection*.json` (17 states, reload, unpinned and 4 keyboard pages). Every page ran at medium. Seven pages ran at compact, wide, maximized and both snaps; Desert, Night sky, light and dark theme, and display 100%/150% ran at medium; text 200% at compact. Axe found 0 errors except the item 8 PopupHost finding on player pages reached through the flyout (`viewed`, `view-selected` at text 200%; `reload`). Live public-service screenshots and a recording (SFentonX). Per-configuration results: [profile-selection/windows.md](../controls/profile-selection/windows.md#validation-issue-226-2026-10-04).

Fixed:
- Narrator stayed silent when a profile search settled. The search box now announces "N players", "No players found." or the failure text while the flyout is open.
- Result rows were unnamed record containers; each `ListViewItem` is now named after the player (`fst.profile.result.<accountId>`).
- An open player page kept **Select Profile** after a newer publication was observed elsewhere; it now swaps to the "Published scores changed" notice.

Seen: one Desert `results` capture rendered without the contrast theme; the re-run rendered Desert. Check screenshots, not only the PASS line, after a theme switch.

## CHOpt Paths validation (issue #223, 2026-10-04)

Evidence: `a11y_matrix.py --scan --tabs 12` with `journeys/paths.json` and `paths_fixture.py` (all 12 reachable states) at compact, medium, snap-left, wide and maximized; Desert, Night sky, Aquatic, Dusk, light and dark theme, text 200% and display 100%/150%. Axe was 0 everywhere except open item 8 at wide. The live public service (Everlong) passed the same sizes and modes. Per-configuration results: [chopt-paths/windows.md](../controls/chopt-paths/windows.md#validation-issue-223-2026-10-04).

Fixed:
- The text table used brand hues under contrast themes. It now uses the `FSTPath*` system-colour roles, and re-applies them when a theme is switched while the dialog is open.
- At 200% text the wide table's fixed columns clipped times and six-digit scores. Columns and the stack breakpoint now scale with text.
- The chart and table scrollers weren't Tab stops, so keyboard users couldn't scroll a long chart or table.

Gotcha: a `UserControl` hosted in a `ContentDialog` gets one `Loaded` and then spurious `Unloaded` events while the dialog is still shown (`IsLoaded` stays true). Subscribe to system events for the dialog's lifetime, not on Loaded/Unloaded.

## Rivalry validation (issue #203, 2026-10)

Evidence: `a11y_matrix.py --scan --tabs 30` on `rivalry`, `rivalry-unknown`, `rivalry-empty` and `rivalry-freeze` at compact, medium, wide, maximized and snapped, then under Night sky, Desert, light system theme, text 200% (C+M) and display 100%/150%. The same configurations ran against the live public service (SFentonX against GingerNINZIN_JPN). All runs had 0 Axe errors except fixture medium text 200%, where the 2 findings were the viewport-edge `BoundingRectangleSizeReasonable` artifact (item 3) on a row clipped at the bottom. Results per configuration are in [rivalry/windows.md](../pages/rivalry/windows.md#validation-issue-203-2026-10).

Fixed:
- The sort `ComboBox` had no visible label (now "Sort By").
- The View Profile button overflowed a compact window at text 200%.
- Title sort used the comparison title rather than the displayed title.

The console was locked, so keys were posted. Tab walks, Enter on a row and Alt+Left worked.

## Statistics validation (issue #204, 2026-10)

Ran 11y_matrix.py --scan for statistics and statistics-chart at compact, medium, wide, snap-left, snap-right and maximized, then at compact/medium/wide under light and dark theme, Desert, Night sky, text 200% and display 100%/150%. The live public service (SFentonX) gave the same results at C/M/W, Desert and text 200%. Axe reported 0 errors in every run. Fixed: the Rank History chart under contrast themes (opaque outlined bars, WindowText gridlines) and its axis labels clipped at 200% text (measured gutters). Per-configuration results: [statistics/windows.md](../pages/statistics/windows.md#validation-issue-204).

## Band Rankings validation (issue #209, 2026-10-03)

Evidence: `a11y_matrix.py --scan --tabs 30` on `band-rankings-paged|anonymous|empty|error` (fixture scenarios via each page's `"fixture"` list): compact/medium/wide/snap/maximized, Desert and Night sky, text 200% (C/M/W), display 100%/150% and the light system theme. All 0 Axe errors, no focus leaving the window and no repeated stops. `band-rankings.json` journeys pass 6/6. Per-configuration results are in [band-rankings/windows.md](../pages/band-rankings/windows.md#validation-issue-209-2026-10-03).

Fixed:
- Keyboard paging lost focus to Back, because the pager hid during the load swap.
- Rows showed between the pager buttons under contrast themes.
- A row without a band page misaligned its columns.
- Band names collapsed to "…" at 200% text in compact windows. After merging master, issue #208's rule applies: the songs label moves under the name instead of being dropped.

Driver note: `RadioMenuFlyoutItem`s expose Toggle, not Invoke. `invoke:` falls back to a click that misses the popup, so drive menu radio items with `toggle:` or the keyboard.

## Player Bands validation (issue #210, 2026-10)

Evidence: `a11y_matrix.py --scan --tabs 20` for `player-bands` at compact, medium, wide, snap-left, snap-right and maximized. It was then run at compact and wide under Desert, Night sky, light theme, text 200%, display 100% and 150%: 0 Axe errors in all 18 runs. The live public service (SFentonX, temporary wrapper without `--base-url`) also gave 0 Axe errors at the same five sizes, under Desert, at text 200% and at display 150%. Results per configuration are in [player-bands/windows.md](../pages/player-bands/windows.md#validation-issue-210).

Fixed:
- Cards were clipped and virtualized by `UniformGridLayout`; they now use `LeaderboardsCardGridLayout`.
- Every card part was a separate Narrator scan stop. Each card is now one stop whose name includes each member's instruments.
- The size pill kept a navy fill under system text.
- `.empty` sat on a panel.

Tooling finding: after a UIA `focus:` step on a `SelectorBarItem`, arrow keys don't move between items (programmatic focus). Reach the bar with Tab or Shift+Tab before `key:right` (see `kb-player-bands`).

## Rivals validation (issue #200, 2026-10)

Evidence: `a11y_matrix.py --scan` (new `text-200` mode) for `rivals`, `compete`, `all-rivals`, `rival-detail` and `rivalry` at compact/medium/wide; the four Rivals pages at medium under all four contrast themes, text 200% (C+M), text 225%, no animations and no transparency: 0 Axe errors. Live public service (SFentonX): Night sky and text 200% render correctly, and UIA trees show one stop per row with no unnamed `Image`. Journeys `empty`, `freeze`, `no-player`, `compete` and `populated` pass.

Fixed:
- Rival rows (hub, All Rivals) and Rival Detail/Rivalry song rows exposed every rank, name, pill and score `Text`, the instrument icons and `SongArt`'s inner `Image` under the named row, so Narrator scan mode read each row twice. Now all parts are Raw. Rivalry rows read the song, artist and year plus both ranks and scores (`RivalSongItem.FullAccessibleName`).
- Anonymous leaderboard rivals (live `accountId: ""`) broke three Leaderboard Rivals cards (also fixed by #213; merged). They now read "Unknown User, rank N, …" as non-actionable rows (see [Rivals Windows notes](../pages/rivals/windows.md)).

Same host constraint as #196 (locked console; display scaling fixed at 300%).

## All Rivals validation (issue #201, 2026-10-03)

Evidence: `a11y_matrix.py --scan` for `all-rivals`, `all-rivals-lead`, `-board`, `-empty` and `-freeze` at compact, medium, wide, snap-left, snap-right and maximized. `all-rivals` and `all-rivals-lead` were also run at compact/medium/wide under all four contrast themes, text 200%, light app mode, and display scale 100% and 150%. `journeys/all-rivals-split.json` ran at 150% (wide and maximized). Every run had 0 Axe errors. The live public service (temp wrapper without `--base-url`, SFentonX) also had 0 Axe errors under Night sky, text 200% and the 150% split.

Fixed:
- Single-instrument scopes (Lead Rivals and others) have no subtitle, but the empty subtitle `TextBlock` still took a line. That pushed the instrument icon off the title's centre. It now collapses (`HasSubtitle`), and long chart lists wrap.
- The fixture served every rival's detail under one name, so a split-selection journey could not tell rivals apart. `rivals_fixture.py` now names each detail body after the requested rival.

Per configuration:
- Compact, medium, wide, maximized and snapped: single column below a 1100 epx page width. The lane host runs at 300% (1280 epx work area), so the split appears only under the 100% or 150% scale modes.
- Light app mode: identical to dark, because the app is dark-only by design.
- Contrast themes: system colours, no artwork, and focus is visible. The ahead/behind bars share one colour, but the pills carry the text.
- Text 200%: the header and pills grow, and the subtitle wraps.
- Keyboard: the same locked console as #196, so it was checked through UIA focusability and the Select and Invoke patterns. Every row is one focusable `ListItem` with an `fst.all-rivals.row.<id>` ID and a name such as "X, ahead of you, N songs ahead, M songs behind".

Out of scope: at 300% the shell's default 1280×820 epx window is larger than the work area.

## Quick Links validation (issue #230, 2026-10-04)

Evidence: `a11y_matrix.py --scan` with `journeys/quick-links.json` (every reachable state on Settings) at compact, medium, snap-left, maximized and wide (pane at display 150%/100%, and a short 1440×560 window); Desert, Night sky, light and dark theme, text 200% (combined with `scale-150` for the pane) and display 100%/150%; keyboard journeys `kb-quick-links-menu`/`kb-quick-links-pane`. Axe 0 everywhere except open item 8 while the menu is open. Live public service checked the same way. Per-configuration results: [quick-links/windows.md](../controls/quick-links/windows.md#validation-issue-230-2026-10-04).

Fixed (all in the wide pane, `Controls/QuickLinksPane.xaml`):
- Rows were 36 epx tall; now `FSTMinTargetSize` (40).
- In a short window the list was clipped: Privacy Policy and Reset couldn't be reached and a focused row was off screen. The list now scrolls.
- Arrow keys moved the "current section" selection without jumping (`SingleSelectionFollowsFocus`).
- At 200% text, long titles ("Show Instrument Metadata") were cut mid-word; titles now wrap.

Tooling: `uiwin` `assertstate:<sel>|selected=<true|false>`; `a11y_matrix.py --mode` accepts `+`-joined modes. Gotcha: `shot:…@screen` shows the lock screen on a locked console, so open-menu screenshots need an unlocked session; UIA assertions and window `print` shots still work.

## Song Score Metadata validation (issue #228, 2026-10-04)

Evidence: `a11y_matrix.py --pages tools/windows/journeys/song-score-metadata.json --fixture tools/windows/song_metadata_fixture.py --scan` (every reachable pill state asserted by UIA name and test ID, inline/wrapped placement with `assertlevel:`/`assertbelow:`, keyboard row order, resize) at compact, medium, wide (1340 epx), maximized and both snaps, plus split view (maximized at display 100% and 150%), then under Desert, Night sky, light and dark theme, app contrast, display 100% and 150%, and text 200%: 0 Axe errors. Live public-service screenshots for `SFentonX`. Per-configuration results: [song-score-metadata/windows.md](../controls/song-score-metadata/windows.md#validation-issue-228-2026-10-04).

Fixed:
- Songs list section groups were named `Festival.App.Pages.SongGroup` (the type name), so Axe reported focusable siblings with the same name on any catalogue with more than one section; groups now take their label.
- Pills had no automation IDs and Narrator could reach their inner text separately; each pill is now one raw element with `fst.songs.metadata.<field>.<songId>` and its spoken name.
- Pills had a fixed 22-epx height and clipped at 200% text; they now grow with the text.
- Wide windows never put the pills inline (the 1100-epx threshold sat on the split-view breakpoint), and a resize out of split view kept a stale list width; placement is now measured per page and re-decided on list resize, text-scale and contrast changes.
## Open issues

1. Title bar at ≥150% text: dropping the caption keeps search usable, but the title-bar layout is owned by shell/infra.
2. (Resolved 2026-09-29, win-unify.) Contrast themes now map status chips, emphasis text, pills, Shop borders/badges and destructive buttons to system colours ([design/windows.md](../design/windows.md) contrast roles; Axe 0 errors under Desert and Night sky on Songs, Song Detail, song leaderboard, Leaderboards, Suggestions, Player, Shop and the Songs Filter). Charts keep their brand data hues; since issue #195 the Song Detail score chart draws axes and bar outlines in WindowText and the selected bar in Highlight, and since issue #212 the rank-history chart (Band Detail, Player Profile) does the same for gridlines, axes and bar outlines.
3. (Resolved 2026-09-29, no repro.) Player Bands at compact: the row sitting exactly on the viewport's bottom edge reports a zero-height, not-offscreen UIA rectangle (Axe `BoundingRectangleSizeReasonable`). This is WinUI clipping, not app layout, and it doesn't occur at medium or wide. Issue #259 hit it on the `suggestions-rivals` matrix page at medium with 150% display scale (a row subtitle on the list's top edge after `scrollinto` bottom-aligned the Spotlight card); the page now pins its target 8 epx below the list top with `scrollinset`, and every size and mode scans 0. New scrolled pages follow that setup rule ([testing/windows](windows.md), "Scrolled matrix pages end on a deterministic edge") rather than deferring the finding here.
4. The XAML choice menus (Rank By, Instrument, Band Size, Jump, Sort) share the implicit presenter name "Options". The invoking button names the choice, but per-menu names would read better.
5. Narrator has no scripted driver. Announcements are covered by `LoadAnnouncer` unit tests and the UIA tree; spoken output needs the operator script.
6. The system modes run on a lane host where other lanes' windows share the desktop. If a Tab walk leaves the window (focus theft), re-run it: Search compact did this once and passed on the re-run.
7. (Resolved 2026-09-29, no repro.) The same viewport-edge clipping (item 3) hits Leaderboards at the 1440×900 `wide` preset after the 2026-09-28 header change: 4 `NameText` findings on rank-3 rows at the bottom edge; 1440×880 and 1440×920 scan clean. Issue #219: the Songs Filter flyout at medium with 150% display scale, after `scrollinto` Percentile, leaves the Karaoke score expander as a sliver at the ScrollViewer's top edge; its header `TextBlock` reports a zero-height rectangle (2 findings). Issue #236: Settings scrolled to the feedback rows at medium with 150% display scale leaves the CHOpt Path View description at the top edge (same zero-height `TextBlock`, 2 findings while the `filing`, `sent` and `error` dialogs are open); the dialog itself scans clean. Issue #260 (live service): Global Search for "the" under Desert and Night sky, at compact and medium, leaves the ninth song row's title exactly on the window's bottom edge (2 findings). The contrast border shifts the rows a few pixels; normal, light, dark, text 200% and display 100%/150% scan clean. Every other size, mode and scroll position scans clean.
8. Flyout menus (Quick Links at compact and medium, the Rank By menu at medium): Axe `BoundingRectangleCompletelyObscuresContainer` on WinUI's windowed popup internals (an `InputSiteWindowClass` exactly the size of its `PopupHost` bridge, no app element involved); other sizes scan clean (issue #207). Issue #208 saw the same finding on Full Rankings while the Instrument/Rank By menu or the pager button tooltip (after Last → Previous) was open; issue #219 on the Songs Filter's instrument selector popup. Issue #223 saw it in the wide Paths dialog when keyboard focus on an Instrument Selector button opens its tooltip. Issue #226 saw it on player pages opened from the profile flyout (View Profile, a result at text 200%): the flyout's popup host lingers after it closes. Issue #229 saw it after Esc returned keyboard focus to the Notifications bell, which opens its tooltip. Issue #234 saw it whenever the title-bar search box's suggestion popup is open (every mode). Issue #261 saw it on Song Detail after an Instrument Selector pick in Score History: focus follows the pick and opens the button's tooltip (0 errors before the pick).
9. (Resolved 2026-09-29.) Red Reset buttons use ButtonFace/ButtonText under contrast themes (`FSTDanger*`).

## Global Search validation (issue #234, 2026-10-04)

Evidence: `a11y_matrix.py --pages tools/windows/journeys/a11y-search.json --fixture tools/windows/profile_fixture.py --scan --tabs 30` covers all 11 state pages: closed, suggestions, open-hint, loading, results All/Songs/Players, empty, error, bands-unavailable and navigated. It ran at compact, medium, wide, maximized and snapped, then under Desert, light and dark theme, text 200%, and display 100% and 150%. The Search page scanned with 0 Axe errors throughout; the suggestion popup hits only item 8. The keyboard pages `kb-global-search` and `kb-titlebar-order(-compact)` pass, and live public-service screenshots were taken.

Fixed: Ctrl+E is now reported as the UIA AcceleratorKey of the compact search button, the title-bar box and its inner TextBox, so Narrator announces the shortcut.

Per configuration: [global-search/windows.md](../controls/global-search/windows.md#validation-issue-234-2026-10-04).

## Settings validation (issue #214, 2026-10-03)

Evidence: `a11y_matrix.py --scan --tabs 60 --pages journeys/settings-states.json` (expanded states, a shot per section) at compact and wide under normal, light and dark theme, Desert, Night sky, text 200%, display 100% and 150%, plus snap-right and maximized: 0 Axe errors, 53/55 distinct Tab stops, none outside the window or repeated. `settings-keyboard` (Space/Enter/Esc with focus kept) and the `journeys/settings.py` journeys pass. Fixed: Settings ignored contrast themes in its reorder lists, First Run chips, link-row hover and progress bar, and kept stale brushes when a contrast theme was switched on while the page was open. Per configuration: [settings/windows.md](../pages/settings/windows.md#validation-issue-214-2026-10-03).

## CHOpt Path Default View validation (issue #256, 2026-10-05)

Evidence: `a11y_matrix.py --scan --pages journeys/a11y-settings-path-view.json` at compact, medium, wide, maximized and both snaps. It then ran at compact and wide under Desert, Night sky, light and dark theme, text 200%, display 100%/150% and text 200% with display 150%. Every run had 0 Axe errors. There is no disclosure: Narrator reads the group name "CHOpt Path Default View" and the selected Image or Text radio (SelectionItem). Arrow keys move focus and selection together. The `path-default-view` journey proves the choice persists and sets the view Paths opens in. No app change. Per configuration: [settings/windows.md](../pages/settings/windows.md#validation-chopt-path-default-view-issue-256-2026-10-05).

## Settings Service Info validation (issue #275, 2026-10-06)

Evidence: `a11y_matrix.py --scan --pages journeys/a11y-settings-service-info.json`, with every card state on `service_info_fixture.py`, Loading included (it runs under an automation-only longer request timeout so the scan fits; users keep 3 s):

- compact, medium, wide, maximized and both snaps;
- Desert, Night sky, light and dark theme, display 100%, text 200%, and text 200% with display 100%;
- live public-service screenshots and a recording.

Every run had 0 Axe errors. Fixed: three test IDs sat on elements without a UIA peer (`Border`, `Grid`, `StackPanel`) and are now on the text they identify. The phase row's Narrator name now matches the web's `aria-valuetext` ("Phase. Subphase", "Total not yet known"). Per configuration: [settings/windows.md](../pages/settings/windows.md#validation-service-info-issue-275-2026-10-06).

## App Navigation validation (issue #225, 2026-10-04)

Evidence: `a11y_matrix.py --scan --tabs 30 --pages journeys/a11y-navigation.json` (anonymous, player, band page, Settings, pane open at compact) at compact, medium, wide, snap-left, snap-right and maximized, plus light and dark theme, Desert, Night sky, text 200% and display 100%/150%: 0 Axe errors except the open minimal pane (WinUI popup-host finding, open issue 8). `journeys/navigation.py` covers `songs`, `leaderboards`, `settings`, `player`, `band`, `reselect`, the compact pane and keyboard use (8/8 pass). Per configuration: [app-navigation/windows.md](../controls/app-navigation/windows.md#validation-issue-225-2026-10-04).

Fixed: keyboard focus entering the pane from the title bar (Tab from profile) or the minimal pane opening from the toggle landed on Songs rather than the selected section; NavigationView only does this for a Tab that passes through itself.

## Navigation pane corners validation (issue #255, 2026-10-05)

Evidence: `a11y_matrix.py --scan --tabs 20 --pages journeys/a11y-pane-corners.json` (pane closed, overlay, inline, collapsed rail) ran with fixtures and live (`--live`). It covered compact, medium, wide, maximized and both snap halves, plus light and dark theme, Desert, Night sky, text 200% and display 100%/150%. Every state passes. Axe found 0 errors except on the open overlay (open issue 8), and Tab stops stay in the window without repeats. `navigation.py compact keyboard` passes. No app code changed. Per configuration: [app-navigation/windows.md](../controls/app-navigation/windows.md#pane-corners-validation-issue-255-2026-10-05).

## Modal component validation (issue #239, 2026-10-04)

Evidence: `a11y_matrix.py --scan --pages journeys/modals.json` (all eight `FestivalDialog` callers: Settings Reset, Privacy Policy, Report an Issue, Suggest a Feature, What's New, Licenses, First Run, the Karaoke Paths notice, Paths, and both profile confirmations) with fixtures, plus live public-service runs (`--live`, no profile pages). Every run: Esc closes, focus returns to the invoker, Tab stays inside the dialog (2–7 stops) and Axe found 0 errors.

| Configuration | Result |
| --- | --- |
| Compact, medium, wide (all 11 pages); maximized, snap-left, snap-right | Pass. Compact fixed: Feedback field hints were cut off |
| Light and dark theme | Pass; identical by design (`FestivalDialog` is dark-only) |
| Desert, Night sky | Pass after the fix below. Pixel-check captures: a run can start before the theme reaches the app; prefix `ready` with `wait:15` |
| Text 200% (compact, wide) | Pass after the Feedback hint fix |
| Display 100%, 150% (wide) | Pass |
| Keyboard only | Pass: Enter opens, Tab cycles, Esc closes, focus restored |
| Live service | Pass for every page except Feedback, which the service hides (`/api/features` `feedback:false`) |

Fixed: Feedback field hints were a `TextBox.Description` that clipped at compact width and 200% text; they now wrap. Under contrast themes WinUI drew a Window-coloured text backplate inside the Highlight fill of the default command (Next, Cancel, Submit, OK) and around the selected First Run pip; `DialogChrome.CommandLabelsWithoutBackplate` and `WithoutBackplate` turn it off. Deliberate deviations: the Karaoke notice is an alert (OK / Don't Show Again, no Close); a one-slide First Run shows only Done; Reset defaults to Cancel.

## Feedback Form validation (issue #236, 2026-10-05)

Evidence: `a11y_matrix.py --scan --pages journeys/a11y-feedback.json --fixture tools/windows/feedback_fixture.py` (one page per state: `unavailable`, `editing-empty`, `invalid`, `editing-dirty`, `attachments`, `discard-confirm`, `sending`, `filing`, `sent`, `error`) at compact, medium, wide, maximized and both snaps, then Desert, Night sky, light and dark theme, text 200% and display 100%/150%: 0 Axe errors in the dialog. The only findings are 2 on Settings behind the dialog (open issue 7, medium at display 150%). `journeys/feedback.py` (`unavailable`, `validation`, `submit`, `error`) passes at every size preset. The live public service has `feedback:false`, so only `unavailable` is reachable there. Per configuration: [feedback-form/windows.md](../controls/feedback-form/windows.md#validation-issue-236-2026-10-05).

Fixed (`Controls/FeedbackDialog.cs`):
- Submit didn't say why it was disabled; a validation line (`fst.settings.feedback.validation`) now names the missing field.
- The discard prompt and file picker left keyboard focus on the dialog root; focus now lands on Keep Editing and back on Attach Media.
- Sending, filing, sent and error weren't announced to Narrator.
- Attachment tiles used fixed colours under contrast themes; they now use theme brushes.
- At compact or 200% text, field labels were cut off; they now wrap like the helper text (wrapped by issue #239).
