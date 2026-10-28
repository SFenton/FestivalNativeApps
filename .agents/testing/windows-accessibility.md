# Windows accessibility results

> **What:** per-page Windows accessibility status (Axe.Windows, keyboard, Narrator, contrast themes, text size, motion/transparency, in-app settings) and open gaps. **Read when:** changing a Windows page or control (each change adds or updates its `a11y_matrix` page; [strategy](strategy.md#accessibility-tests-with-every-change)), or re-running the accessibility pass. Tools and the Narrator script: [windows.md](windows.md#accessibility); design rules: [design/windows.md](../design/windows.md#accessibility).

Evidence: `tools/windows/a11y_matrix.py` against the anonymized fixture (`rivals_fixture.py`) on Debug and NativeAOT Release (`--exe aot`, automation mode), 3840×2160 at 150%. Sizes are `compact` 500×800, `medium` 900×700 and `wide` 1440×900 epx. Committed samples are `windows/reports/screenshots/a11y-*.png`. Legend: ✅ pass · ⚠️ pass with a noted gap · — not applicable.

## Checks

| Check | How |
|---|---|
| Axe | `--scan`: Axe.Windows 2.4.2 over every top-level window of the process; 0 errors at compact, medium and wide (Debug), and at medium on AOT |
| Tab | `--tabs 30`: focus stays in the window, no repeated stop, order title bar → pane → page |
| Keys | `journeys/a11y-keyboard.json` (`assertfocus`): Songs toolbar → rows; Up/Down within row lists; Tab across cards; Esc returns focus from Sort, Filter, Profile, Notifications, Quick Links and Paths; first-run dialog closes on Esc; Ctrl+1…7/Ctrl+comma; Ctrl+E; Alt+Left from a text field; title-bar order at each size. All sizes on Debug, medium on AOT |
| Narrator | Tree audit (names, roles, headings, landmarks, groups); unit-tested load/result/error notifications; `listen:announcements` (issue #269); the Narrator model's reading order and phrases (`narrate:`/`assertread:`/`assertorder:`, issue #271, title bar and every page tool); operator script in [windows.md](windows.md#narrator-manual-script-operator) |
| HC | Aquatic, Desert, Dusk and Night sky at medium on every page: theme colours behind content, no artwork, text legible, focus visible |
| Text | 225% at medium on every page, and at compact on the core pages; 150% on the core pages |
| Motion | Animation effects off, transparency off, in-app Reduce Motion + Disable Animated Artwork + Save Data, and More Contrast + Less Transparency, on the core pages |
| Touch targets | Issue #72 (2026-10-02): UIA bounds of the title-bar Search/bell/profile, Songs Sort/Filter/Jump and Quick Links at compact, then a `ui_journey.py` coordinate `click` at the centre and 18.5 epx above and below it (fresh launch each), passing when the button's flyout (`ProfileFlyout`, `Panel`, `SortFlyout`, `FilterFlyout`, a Quick Links item) or Search page appears. Coordinates are relative to the title bar's UIA origin, not the window rect (which includes the invisible resize border). Before: Search 32×32, profile 36×36, tools 32 tall; 12 of 21 clicks missed. After `FSTMinTargetSize`: every button ≥ 40×40, no overlapping bounds, 21/21 activate. Markup guard: `HitTargetMarkupTests`. Issue #271 (2026-10-06) re-ran this as `journeys/a11y-hit-targets.json`. It checks UIA sizes, a point 18.5 epx above and below each centre (inside the target, `FromPoint`, not non-client) and neighbour overlap. It covers every title-bar and page tool at compact, medium, wide, maximized and both snap halves, in light, dark and `hc-desert` themes, text 200%, and display 100% and 150%. Before the fix: the Full Rankings and Band Rankings pickers and the pinned Paths were 31 epx tall. After any resize, the title bar's stale passthrough regions also left the Search button's edges (and sometimes its centre, or the search box) in the caption. After: every check passes with Axe 0 (allowing one device pixel of rounding: UIA reads a half-pixel-placed 40 epx button at 150% as 59 px, and at 100% the TitleBar's whole-pixel passthrough rect left the button's last pixel row in the caption, which issue #536 fixed: on CI's unlocked 100% display `FromPoint` there hit the "Non Client Input Sink Window" and a press dragged the window, so the title-bar hosts now stretch their passthrough rects to the full title-bar height and the title-bar probes report no `edge_pixel`). Narrator reading order (issue #271 retry, 2026-10-06; locked lane console, so the Narrator model rather than live speech): `journeys/a11y-narration.json` passed 70/70 page×size runs (compact, medium, wide, maximized, both snaps), 36/36 under light + text 200%, Desert + display 150% and dark + display 100%, and 4/4 live (SFentonX). Order: title bar Toggle Navigation → title → Search (button, or group + edit from medium) → bell → profile → page title → page tools → content; the Song Detail pinned Paths is read after the band sections, as its keyboard order. No order or phrase discrepancy. Activation (issue #271 design-review retry, 2026-10-06): `assertat` sends no input, so `journeys/a11y-hit-targets-press.json` presses each probe point for real. It sends a `tapat` touch at every 18.5 epx point above and below the centre, plus a `clickat` mouse press on the title bar. Each press is followed by that control's own result (Search page or box focus, bell sheet, profile search or Statistics, the menu's first item, Paths, the first Quick Link) and a close. A press that lands in the caption or drag region therefore fails. It covers the compact/snap title-bar button, the medium/wide/maximized box, the post-resize and bell-appearing transitions, every page tool at five layouts, the seven Quick Links menus, and live Search (SFentonX). `PressAt` refuses to run on a locked console or when another window covers the point. The lane console was locked, so the run here was the `--pattern-presses` dry run (each press becomes the control's UIA pattern, and every outcome and close is asserted): 68/68 page×size runs pass. Real presses still need an unlocked console. Song Details' Item Shop is never pressed because it opens the browser. Live presses are limited to Search, because the bell and Statistics read player-scoped data |

## Pages

Tab = distinct stops in a 30-press walk (compact/medium/wide). Core pages (Songs, Song Detail, Leaderboards, Rivals, Settings, Search, the profile flyout and first run) also pass every Motion mode.

| Page | Axe C/M/W | Tab | Keys | HC ×4 | Text 225% |
|---|---|---|---|---|---|
| Songs (anonymous / selected) | ✅✅✅ | 9/10/10 | ✅ | ✅ | ✅ (C+M) |
| Songs Filter (web sections, percentile open) | ✅✅✅ (+AOT) | 20/20/20 | ✅ | ✅ | ✅ |
| Songs Filter, no profile (General only, Double Bass open, issue #273) | ✅✅✅ | 7/7/7 | ✅ | ✅ (Night sky, Desert) | ✅ (200%) |
| Song Detail + Paths dialog | ✅✅✅ | 16/17/17 | ✅ | ✅ | ✅ |
| Song Leaderboard | ✅✅✅ | 8/10/10 | ✅ | ✅ | ✅ (C/M/W, also 200%; display 100%/150%, issue #197) |
| Player History (Song Detail Score History, issue #198) | ✅✅✅ | 7/9/9 | UIA (locked console) | ✅ (Night sky, Desert: chart roles) | ✅ (200%: axes scale) |
| Song Band Leaderboard | ✅✅✅ (+live, #196) | 8/10/10 | UIA only (#196) | ✅ | ✅ (+200% C+M) |
| Item Shop (grid, list, filter, states) | ✅✅✅ (+live, #206; shop-offers states #224; CI `shop-offers` #516) | 5/8/8 (grid one stop) | ✅ (`kb-shop-*`) | ✅ | ✅ (200% C+M, #206) |
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
| Notifications panel / bottom sheet (flyout before #638) | ✅✅✅ (+live, #229) | 1 (list) | ✅ (#229) | ✅ (#229) | ✅ (#229, C+M) |
| Quick Links menu | ⚠️✅ (issue 8) | 1 (menu) | ✅ (+profile jumps, `a11y-quick-links-jump.json`, #414) | ✅ | ✅ (pane titles wrap, #230; profile menu 225%, #414) |
| First-run dialog | ✅✅✅ (+demo placeholder/catalogue states, `a11y-first-run-demos.json`, `windows-ui` CI, #420; real-control demos stay out of the control view, `a11y-first-run-real-demos.json`, #498; rival demo rows carry the page row's exact ahead/behind name, no shared count, #522) | 4–5 | ✅ (+Settings replay, #420; Tab skips the inert sort form and chart bars, #498) | ✅ | ✅ (demo clear of title at 225%, rival demos too since the #522 fit-centring fix; body scrolls so the pips stay reachable, #420; auto-scroll held with Reduce Motion and Animation effects off, paused when minimized, hard-edged with transparency effects off, Less Transparency or More Contrast, #498) |
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

## Song board end of list (issue #456, for #293, 2026-10-10)

`journeys/a11y-song-board-end.json` covers the end-of-list spacing #293 changed, with Fixture Player 1 (pinned row), Empty Player (no score) and no player. Down from the first row reaches row 25 with the list at its end. The row then sits 4 epx above the footer's first part (`assertgap`), is clear of it, reads before the pinned row and pager, keeps a 40 epx target, and Tab/Shift+Tab move to the footer and back. The fade reports `end`. All pages passed with 0 Axe errors at compact and medium, at 100% and 225% text. No defect was found. `windows-ui` picks the file up through `ui_ci.generated_runs`; `tests/test_song_leaderboard_a11y_journey.py` pins the steps.
- Reach a far row with single `key:down` steps, not one `keys:` burst. On a locked console the burst is posted and dropped a press, leaving focus one row short.

## Song board states (issue #511, for #197, 2026-10)

`journeys/a11y-song-board-states.json` covers what #197 changed: the pinned row's own UIA ID, an empty board without "0 entries", the contrast-theme footer plate (`hc-desert`) and the trimmed-name tool tip (`app-reduced`). Each page runs only in the mode that shows its state. All passed with 0 Axe errors; details in [song-leaderboard/windows.md](../pages/song-leaderboard/windows.md#accessibility-tests-issue-443). No defect was found.
- A row's name only trims (and gets a tool tip) while the marquee is stopped and the text is not large: at 225% text names wrap. Test the tool tip at medium with `app-reduced`.
- Rows move with Up/Down; Tab leaves the list for the pinned row. Close the tool tip (`focus:` the header, `waitgone:class=ToolTip`) before the Axe scan.
- A paint probe on a hard-edge footer can't see the contrast plate (the mask already hides rows there). Mutation-test such probes with every layer that hides the content removed.

## Leaderboard row columns validation (issue #242, 2026-10-04)

Scope: the shared row-column fitter (issue #37) on every board, checked against the live public service with SFentonX. Results per configuration are in [song-leaderboard/windows.md](../pages/song-leaderboard/windows.md#validation-issue-242-2026-10-04).
- **Live matrix:** `a11y_matrix.py --live --scan --tabs 25` gave 0 Axe errors, no focus leaving the window and no repeated stops on six pages at compact, medium and wide: song board, Leaderboards, Full and Band Rankings, Song Detail and Score History.
- **Modes (0 Axe errors):** Desert, Night sky, text 200%, display 100%/150%, text 200% + display 150% and the light system theme. UIA bounds show every row and the pinned row on shared columns at all sizes, maximized and both snaps.
- **Fixed:**
  - Switching a contrast theme with a board open left the rows' code-set brushes (translucent fill, purple pinned row, gold badge) and the pager's disabled-button aliases in the old theme, under system backplates.
  - Under a contrast theme, the pinned row's FC badge drew WindowText on Highlight.
- **Committed test (issue #409, 2026-10-08):** `journeys/a11y-leaderboard-columns.json` turns this check into fixture pages: the song board, its narrow/season/large-text states and Full Rankings. It checks names, Button role, reading order (rows → pinned row → pager), 40 epx targets and pinned-row column alignment. It passed with 0 Axe errors at compact, medium, wide, maximized and snap-left, and at compact and medium under text 200% and 225%. `fst.song-leaderboard.title` is not an item in `assertorder`'s Narrator reading-order model, so order checks start at the first row.
- **Keyboard order (issue #409, PR #456 review):** `assertorder` checks only Narrator's reading order, and `tabs: 0` skips the matrix tab walk. So the same pages now also drive the keyboard and `assertfocus` each hop: Up/Down between rows (one Tab stop, the Fluent list model), then Tab to the pinned row and pager, and Shift+Tab back.
  - Shift+Tab re-enters a repeater on its last realized row, which depends on scroll, so assert the hops on either side of it rather than that row.
  - **Failed, fixed:** arrowing down the song board, Band Rankings, the song band board or Player Bands scrolled the focused row or card only to the viewport's bottom edge, under the floating pinned row and pager (WCAG 2.4.11; `assertapart` failed at compact and medium). Only Full Rankings had a guard. `BoardFooter.Inset` now applies it to every board, and a `*-focus-clear` page asserts it on each of its five consumers (each fails at compact and medium with the guard removed).
  - **Pinned band row (issue #461, for #306):** `journeys/a11y-song-band-pinned.json` (CI runs `song-band-pinned` and `song-band-pinned-text-225`) covers the song band board's pinned "your band" row: the Jump and Open band Narrator phrases, the 40 epx pin and pager targets, rows → pin → pager reading and Tab order, Tab/Shift+Tab/Enter, the jumped-to "Your band." row clear of the pin, the size switch (Trios empty hides it), no player and Reduce Motion. **Failed, fixed:** at 225% text the centred jump left the row partly under the pin, because `BoardFooter.Inset` skipped aligned requests. It now grows them as well (Solo and Full Rankings jumps share it). `selected_reveal_journey.py --only solo` fails intermittently on master too (1 in 6; a repeater row logs two `play` lines before the rush, which `check_reveal` counts twice). The request the reveal makes comes after the rush, so this change doesn't cause it.
  - **Pinned score row's load gate (issue #457, for #295):** `journeys/a11y-song-pinned-reveal.json` (CI runs `song-pinned-reveal`, `-text-225`, `-reduced`, `-no-animations`) covers the song board's pinned "your score" row as it joins the rows' load gate: absent from UIA, the reading order and Tab under the first-load ring and during a Filter Invalid Scores reload (Tab goes header → Next), then its Narrator phrase, rows → pinned row → pager order, 40 epx target, purple fill and Tab stop with the new rows; still under Reduce Motion and with Animation effects off. Passed with 0 Axe errors. No defect found. A test-design finding: the Windows pinned row is created only when the first page commits, so first-load absence checks can't catch a missing gate. Mutation-test a gate on a reload that keeps the row's data (here the leeway change), not only the first load.
  - **Selected-row reveal (issue #470, for #323):** `journeys/a11y-selected-row-reveal.json` (CI runs `selected-row-reveal`, `-text-225`, `-reduced`, `-no-animations`) opens the solo song board from Song Details' "your score" row and Full Rankings from the Leaderboards card's "your rank" row by keyboard. The revealed row reads "Your rank, …", keeps its purple fill and a 40 epx target clear of the pinned row, reads between its neighbours and before the pinned row and pager, and Down/Up/Tab move from it in place; at 225% text and with motion off too. **Defect found and fixed:** with in-app Reduce Motion or Animation effects off, the solo board's reveal scrolled before the freshly shown repeater had realized its rows, so the board stayed at the top; `SelectedRowReveal` now waits for realization with motion off as well. **Second defect, fixed:** at 225% text with UI Automation queried during the jump (as Narrator does), the solo board ended at the top with no rows visible: `LeaderboardsSongPage` queued a scroll-to-top for the revealing page and centred a row with no arranged position. It now skips the scroll-to-top when a reveal is pending and lays the row out before `StartBringIntoView`, as Full Rankings did since #318. Rule: a motion-off path may skip waits for an animation, never the wait for layout or realization; and drive reveal checks with polling `waitfor` steps, which reproduce a screen reader's UIA load (a plain `wait:` hid this race).
  - **Row height (issue #440, for #90):** `journeys/a11y-leaderboard-row-height.json` checks every board's rows at 48+ epx: overview instrument and band cards with their loading placeholders, Full and Band Rankings, the song board and pinned row, and Song Detail previews. Placeholders sit at the loaded pitch, are raw-view only and are silent to Narrator. Rows read as one Button each in visual order. Passed with 0 Axe errors at compact and medium, and at compact under text 225%. No defect found. At 225% text the first scans failed on test setup: a row clipped at the viewport's bottom edge, and a band row matched in the wrong card because overview row IDs repeat across cards. Both were fixed by pinning the final position with `scrollinset` and waiting for the slow card's View All.
  - **Spotlight loading row (issue #527, for #281):** the same file's `row-height-card-spotlight-loading` (Tap Vocals card) and `row-height-full-rankings-spotlight-loading` pages hold the own-rank read (`rankings_fixture.py --rank-delay 25`, the card page with `--rank-delay-instrument Solo_Vocals`). The raw-view placeholder is 48 epx and as tall as the "your rank" row that replaces it. The ring reads "Busy Loading your rank, ProgressRing", is not focusable and sits between the rows and View All / the pager. Tab skips it. Passed with 0 Axe errors (mid-load and final) at compact and medium, and at compact under text 225%. No defect found. The first runs failed on test setup. The overview reveals its first four cards only after their spotlights load, so delaying every card hid the page. Leaving focus on **Next page** opened its tooltip at the final scan (open issue 8). Both were fixed in the pages.
  - A focus-clear page must prove its target starts below the fold (`waitgone:<card>@2` before the arrows: the driver resolves only on-screen elements) and check every pager button the target can sit under. The pager is centred, so on Player Bands' two-column grid a left-column card sits under Previous, not Next (`cols-player-bands-focus-clear-grid` passed against Next alone with the guard removed).

## Item Shop validation (issue #224, 2026-10-04)

Scope: the Shop Offers control only. Results per configuration are in [shop-offers/windows.md](../controls/shop-offers/windows.md#validation-issue-224-2026-10-04). `a11y_matrix.py --scan --tabs 30 --only shop` gave 0 Axe errors at compact, medium and wide (6/10/10 Tab stops: compact has no List/Grid toggle). At medium it also gave 0 Axe errors under Desert, Night sky, light and dark system theme, text 200%, and display 100% and 150%. No run had focus leaving the window or repeated stops. The live public service (anonymous) was checked at compact, medium, wide, maximized and snap-left, and under Desert, text 200% and display 150%. Fixed: under a contrast theme, WinUI's automatic adjustment had repainted the badge text as WindowText on a backplate inside the Highlight pill (`HighContrastAdjustment=None` while it is on, as `LeaderboardEntryRow` does). The active ProgressRing reads "Busy Loading Item Shop" (WinUI prefix), so tests use `fst.shop.loading`.

## What's New validation (issue #235, 2026-10-04)

Scope: the What's New dialog only. Results per configuration are in [whats-new/windows.md](../controls/whats-new/windows.md#validation-issue-235-2026-10-04). `a11y_matrix.py --scan --tabs 6 --pages journeys/a11y-whats-new.json` gave 0 Axe errors for the launch dialog and the Settings replay. That held at compact, medium, wide, maximized and snap-left, and at medium under Desert, Night sky, light and dark system theme, text 200% and display 100% and 150%. Text 200% also gave 0 at compact. Every run had 2 Tab stops (notes, Dismiss), no focus leaving the window and no repeated stops. The keyboard pages `kb-whats-new-dismiss` and `kb-whats-new-replay` pass at all three sizes. `ui_journey.py journeys/whats-new.json` drives every reachable state.

Fixed: the notes scroller was not a tab stop, so the keyboard could not scroll long notes. It now opens focused and is named after the title. Dismiss and the headings gained automation IDs. Backdrop-click journeys need an unlocked console (`journeys/whats-new-pointer.json`; they aim with epx `clickat:` since issue #531).

Issue #434 (2026-10-08): the `windows-ui` CI job runs `a11y-whats-new.json` (`tools/windows/ui_ci.py` runs `whats-new` at compact/medium and `whats-new-text-225` at compact). The grouped tester and store pages assert heading levels (`assertstate` `heading=2`, `3` or `0` for none), reading order from the version heading through the category headings and bullets to Dismiss, the Raw bullet glyph and a 40×40 Dismiss ([whats-new/windows.md](../controls/whats-new/windows.md#validation-issue-434-2026-10-08-80s-grouped-notes-in-ci)).

## Notifications validation (issue #229, 2026-10-04)

Scope: the title-bar bell and the Notifications panel / bottom sheet (the shared modal docked to the window edge since #638, [modal-shell](../patterns/modal-shell.md) R17; an anchored flyout before it). Results per configuration are in [notifications/windows.md](../controls/notifications/windows.md#validation-issue-229-2026-10-04). `a11y_matrix.py --scan --pages journeys/a11y-notifications.json --fixture notifications_fixture.py` gave 0 Axe errors for loaded, empty, not generated and failed at compact, medium and wide. Loaded also gave 0 at maximized and snap-left, and loaded and failed gave 0 at medium under Desert, Night sky, light and dark system theme, text 200% and display 100% and 150%. At text 200% the loaded and scrolled-to-end pages also gave 0 at compact. No run had focus leaving the window. The keyboard pages `kb-notifications-rows` and `kb-notifications-esc` pass at all three sizes, and `notifications_journey.py` drives every reachable state. Scanning after Esc (focus back on the bell, tooltip open) shows only open item 8.

Fixed:
- Each row read as an unnamed list item followed by a nested group, and the row IDs never reached UIA. The `ListViewItem` now carries the name and ID (`ContainerContentChanging`).
- State IDs sat on panels, which have no UIA peer, so they now sit on text.
- Under contrast themes the flag pills kept their web colours and the section headers stayed white.
- With nothing focusable (loading, empty, not generated), focus rested on an unnamed "Popup" window (pre-#638 flyout). Since #638 focus rests on Close inside the modal window named "Notifications".
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

CI rule (issue #514): `tools/windows/journeys/a11y-difficulty-meter.json` keeps these fixes in the `windows-ui` job. It checks the cell and row names, the reading order, that the meter isn't focusable, normal fills, hollow unfilled bars under Desert and the live Desert on/off recolour. The `invalid` state no page reaches runs in the `difficulty-meter` control lab (`meter-lab-*`): its Text role, name, automation ID, missing child and focus, and that re-binding the same meter to a level and back restores the Image role and `fst.songs.difficulty-meter`. A meter change updates these pages. Paint probes must avoid the 62×20 polygon edges (bar *i* centre is x = 9*i*+4 epx at mid-height). Pages that assert normal colours list every `hc-*` mode in `skip_modes`. Page list: [difficulty-meter/windows.md](../controls/difficulty-meter/windows.md#states-and-reachability).

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

Driver note (issue #439): `assertorder` walks the window's reading order, which leaves out an open `ComboBox`'s options (they sit in the popup). Check option order with `assertbelow:<later>|<earlier>` pairs on `name=<option>&class=ComboBoxItem`, and a missing option with `waitgone:…@1`.

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
- Rival rows (hub, All Rivals) and Rival Detail/Rivalry song rows exposed every rank, name, pill and score `Text`, the instrument icons and `SongArt`'s inner `Image` under the named row, so Narrator scan mode read each row twice. Now all parts are Raw. Since #603 every song row (Rival Detail and Rivalry) reads what it shows: song, artist, chart, both ranks and who leads (`RivalSongItem.AccessibleName`).
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
## Load transition validation (issue #431, 2026-10)

Evidence: `a11y_matrix.py --pages tools/windows/journeys/a11y-load-swap.json --scan` at medium. Normal mode runs the six board surfaces #71 changed: Full Rankings, Band Rankings, song leaderboard, song band leaderboard, Player Bands and the Leaderboards overview's Rank By reload. `--mode text-225` runs Full Rankings and the song band leaderboard. Normal mode with in-app Reduce Motion and `--mode no-animations` run the Full Rankings swap. All of them run against `rankings_fixture.py` with a held page read.

Asserted:
- The spinner's Narrator phrase ("Busy Loading rankings, ProgressRing", "… leaderboard", "… band scores", "… bands", "… leaderboards").
- Stale rows leave UIA while it shows (R2).
- Reading order runs selectors → spinner → pager on a reload; on the first load the pager is hidden (R4), so it ends on the spinner.
- The selectors and pager stay enabled at 40×40 epx with focus on the pressed pager button (R4).
- The new rows' phrases after the swap.
- At 225% text, the spinner stays apart from the pager.
- With reduced motion, the swap still lands with the same focus (R6).

All ten pages pass with 0 Axe errors. The six normal-mode surface pages also scan mid-load. CI (#431 review): `tools/windows/ui_ci.py` runs the file in `windows-ui` as `load-swap` (normal), `load-swap-text-225` and `load-swap-no-animations`, all `--scan` at medium (every page is medium-only). Every page ends focused on a row so the final scan never meets a pager tooltip (open issue 8); `tests/test_ui_ci.py` fails if a page drops out of those runs.

Fixed:
- Song band leaderboard and Player Bands: pressing **Next page** moved keyboard focus to **Previous page** while the page loaded. `BandsPagerViewModel`'s async commands didn't allow concurrent runs. A running `AsyncRelayCommand` reports `CanExecute` false, so the focused button disabled itself and `LeaderboardsPager` handed focus to the first enabled button. The commands now set `AllowConcurrentExecutions` (as `RankingsPagerViewModel` has since #197), and the view models still reject out-of-range pages. Unit test: `BandsPagerTests.Pager_StaysEnabledWhileAPageLoads`.

## Open issues

1. Title bar at ≥150% text: dropping the caption keeps search usable, but the title-bar layout is owned by shell/infra.
2. (Resolved 2026-09-29, win-unify.) Contrast themes now map status chips, emphasis text, pills, Shop borders/badges and destructive buttons to system colours ([design/windows.md](../design/windows.md) contrast roles; Axe 0 errors under Desert and Night sky on Songs, Song Detail, song leaderboard, Leaderboards, Suggestions, Player, Shop and the Songs Filter). Charts keep their brand data hues; since issue #195 the Song Detail score chart draws axes and bar outlines in WindowText and the selected bar in Highlight, and since issue #212 the rank-history chart (Band Detail, Player Profile) does the same for gridlines, axes and bar outlines.
3. (Resolved 2026-09-29, no repro.) Player Bands at compact: the row sitting exactly on the viewport's bottom edge reports a zero-height, not-offscreen UIA rectangle (Axe `BoundingRectangleSizeReasonable`). This is WinUI clipping, not app layout, and it doesn't occur at medium or wide. Issue #259 hit it on the `suggestions-rivals` matrix page at medium with 150% display scale (a row subtitle on the list's top edge after `scrollinto` bottom-aligned the Spotlight card); the page now pins its target 8 epx below the list top with `scrollinset`, and every size and mode scans 0. New scrolled pages follow that setup rule ([testing/windows](windows.md), "Scrolled matrix pages end on a deterministic edge") rather than deferring the finding here.
4. The XAML choice menus (Rank By, Instrument, Band Size, Jump, Sort) share the implicit presenter name "Options". The invoking button names the choice, but per-menu names would read better.
5. Narrator has no scripted driver, and lane consoles are locked, so live Narrator can't run there. Announcements are asserted with `listen:announcements`, and reading order and phrases with the Narrator model (`narrate:`/`assertread:`/`assertorder:`, [windows.md](windows.md) "Narrator model"; issue #271 `journeys/a11y-narration.json`). Narrator's own speech (verbosity, scan mode, pronunciation) still needs an operator to run the script (items 20–21 cover #271) in an unlocked session.
6. The system modes run on a lane host where other lanes' windows share the desktop. If a Tab walk leaves the window (focus theft), re-run it: Search compact did this once and passed on the re-run.
7. (Resolved 2026-09-29, no repro.) The same viewport-edge clipping (item 3) hits Leaderboards at the 1440×900 `wide` preset after the 2026-09-28 header change: 4 `NameText` findings on rank-3 rows at the bottom edge; 1440×880 and 1440×920 scan clean. Issue #219: the Songs Filter flyout at medium with 150% display scale, after `scrollinto` Percentile, leaves the Karaoke score expander as a sliver at the ScrollViewer's top edge; its header `TextBlock` reports a zero-height rectangle (2 findings). Issue #236: Settings scrolled to the feedback rows at medium with 150% display scale leaves the CHOpt Path View description at the top edge (same zero-height `TextBlock`, 2 findings while the `filing`, `sent` and `error` dialogs are open); the dialog itself scans clean. Issue #260 (live service): Global Search for "the" under Desert and Night sky, at compact and medium, leaves the ninth song row's title exactly on the window's bottom edge (2 findings). The contrast border shifts the rows a few pixels; normal, light, dark, text 200% and display 100%/150% scan clean. Every other size, mode and scroll position scans clean.
8. (Resolved for flyouts and suggestion lists 2026-10-09, issue #534; tooltips remain.) WinUI 3 desktop popups are windowed by default: each opens a `PopupWindowSiteBridge` ("PopupHost") whose `InputSiteWindowClass` child is exactly the bridge's size, which Axe reports twice as `BoundingRectangleCompletelyObscuresContainer`, with no app element involved. Every app `Flyout`/`MenuFlyout` now sets `ShouldConstrainToRootBounds="True"` (XAML, or the initializer in code such as `QuickLinksMenuButton`), and every `AutoSuggestBox` sets `controls:PopupHosting.InWindow="True"`, which constrains the template's `SuggestionsPopup` (the template sets it `False`) on `Loaded`, before its first open: WinUI refuses the change once a popup has opened windowed. In-window popups can't extend past the window, so a menu taller than the window scrolls inside it. `PopupHostingMarkupTests` (Core tests) fails on an unconstrained flyout or a suggestion box without the property, and `ui_ci.py` gates the header flyouts (`popups`, `popups-text-225`: Rank By on Leaderboards and Full Rankings, Quick Links, the profile flyout and the Notifications panel) with no allowance. **Tooltips stay windowed:** WinUI's `ToolTip` always creates a windowed popup (`ToolTip_Partial.cpp`, `CreatePopup` calls `SetIsWindowed()` whenever the platform supports windowed popups) and has no public opt-out, and the bridge lingers after Esc closes the tip. Keyboard focus on a button with a tooltip opens it, so a page that asserts focus on such a button then moves focus to a control without a tooltip before the final scan, as the load-swap pages do (#431): `kb-songs-order` (back on Jump), `kb-notifications-esc` (Esc back to the bell), the `cols-*-focus-clear` pages (Tab to **Next page**) the `qla-*-menu` and `qlj-profile-menu` pages (Esc back to Quick Links; `qlj-profile-menu` scanned 2 errors once #548 lifted its quarantine) and the `press-songs`/`press-quick-links-*` hit-target pages (Esc back to Jump or Quick Links after the last press; 2 errors each in `windows-ui` before) return to a row, tile or switch (agent decision, #534; the guards in `tests/test_a11y.py`, `tests/test_quick_links_landing_a11y.py`, `tests/test_quick_links_jump_journey.py` and `tests/test_hit_targets_journey.py` pin those endings). The `qls-song-detail-menu` pages (`a11y-quick-links-scroll.json`, #668) assert focus back on Quick Links after Esc, then move it to the tooltip-free **Paths** button and wait for the tip to close before the scan (2 errors each in the `releases/2610.12` `windows-ui` run before, #671; `tests/test_quick_links_scroll_journey.py`). Keyboard tooltips stay: removing them would lose the shortcut hint. History: Quick Links at compact and medium, the Rank By menu at medium: `BoundingRectangleCompletelyObscuresContainer` on WinUI's windowed popup internals (an `InputSiteWindowClass` exactly the size of its `PopupHost` bridge, no app element involved); other sizes scan clean (issue #207). Issue #208 saw the same finding on Full Rankings while the Instrument/Rank By menu or the pager button tooltip (after Last → Previous) was open; issue #219 on the Songs Filter's instrument selector popup. Issue #223 saw it in the wide Paths dialog when keyboard focus on an Instrument Selector button opens its tooltip. Issue #226 saw it on player pages opened from the profile flyout (View Profile, a result at text 200%): the flyout's popup host lingers after it closes. Issue #229 saw it after Esc returned keyboard focus to the Notifications bell, which opens its tooltip. Issue #234 saw it whenever the title-bar search box's suggestion popup is open (every mode). Issue #261 saw it on Song Detail after an Instrument Selector pick in Score History: focus follows the pick and opens the button's tooltip (0 errors before the pick). Issue #431 saw it on Player Bands after **Next page** kept focus, which opens the pager button's tooltip. Issue #571 saw it at wide (225% text, `pane-inline`/`pane-collapsed`) on fresh launches: the compact title-bar search button's tooltip, opened at the launch's compact size, stayed open after the resize to wide collapsed the button. That one was an app defect, fixed with `Controls/CollapsedToolTip` and a focus hand-off ([platforms/windows.md](../platforms/windows.md#gotchas)); `a11y-search.json` `search-swap-*` guard it, and `a11y-instrument-selector.json` `instrument-selector-swap-compact`/`-full` (and `-narrow`/`-widen`, which also cover the compact arrows, #574) guard the Instrument Selector's own swap (a keyboard-opened circle or centre tooltip, then the resize: tooltip gone, focus on the replacement, Axe 0; the old keyboard-state hand-off reopened a "Lead" tooltip on the replacement), and `a11y-settings-swap.json` `settings-split-swap-wide`/`-narrow` guard the Settings list/detail switch (focus moves from the Item Shop switch to its chevron row and back, on screen, Axe 0). Issue #571 also saw it at wide 225% text on `search-suggestions`: the title-bar box's Ctrl+E hint opened over the suggestion list after typing had started, also an app defect, fixed with `Controls/TypingToolTip`. Issue #571 then saw it at wide 225% text on `qlj-profile-pane`: the same box's *hover* tooltip, opened by a cursor an earlier run's title-bar presses had left where the box lands after the resize. That was a harness defect, fixed by parking the cursor on every `resize:` ([windows.md](windows.md#accessibility)); a pointer resting on the box should show its tooltip. The load-swap journeys end focused on a row before the final scan. The page key `"axe_allow": ["framework-popup"]` (`a11y_matrix.AXE_ALLOW`, predicate `uiwin.framework_popup_finding`; first used by the `windows-ui` Quick Links landing runs, #416) drops exactly this finding; every other finding still fails. Since #534 no gated page uses it: the `qla-*-menu` pages dropped it, and a flyout or menu must scan clean without it. A tooltip page uses it only when no tooltip-free control can take focus before the scan, with a page `note` saying why: `a11y-history-swap` (the post-pick circle tooltip) and `instrument-selector-lab-compact` (#571: the UIA toggle focuses the Lead circle, and WinUI opens a tooltip for UIA-sourced focus on purpose, `ToolTipService::OnOwnerGotFocus`, and does not close it on Esc; every control in the control lab has a tooltip). `mm-suggestions-scroll` (`a11y-modal-motion.json`) reported 4 Axe errors in one `windows-ui` run (PR #544) and was quarantined under #534; with popups in-window it scanned 0 in 3 consecutive local runs at compact, medium and wide (2026-10-09), so the quarantine was lifted.
9. (Resolved 2026-09-29.) Red Reset buttons use ButtonFace/ButtonText under contrast themes (`FSTDanger*`).
10. WinUI's `ProgressRing` template part `LottiePlayer` (an `AnimatedVisualPlayer`) reports Axe `IsControlElementTrueRequired` for about the first second after the ring appears, then settles into an ordinary image (issue #431, seen on Band Rankings and the song band leaderboard mid-load). This is framework start-up with no app element involved, and Narrator still reads the ring by name. Mid-load scans `wait:1` after the spinner appears, and their fixtures hold the read for 10 s so the scan still lands mid-load. The hold starts when the app launches: 6 s ran out before the first-load `assertorder` on the faster `windows-ui` runner (#431 review), and in `SpinnerOut` (opacity 0) the ring reports `IsOffscreen`, so Narrator's order skips it. A first-load hold must outlast launch, driver start-up and every wait before the last mid-load check; give the reload's new-row `waitfor` more than the hold. A swap hold starts at the selector change and must outlast every check before the mid-load scan **plus the scan itself** (up to about 4 s on the runner): if the read answers mid-scan, the ring goes inactive while Axe reads it (its name loses WinUI's "Busy" prefix) and both the ring and `LottiePlayer` fail `IsControlElementTrueRequired`, so the Paths mid-swap scans (`paths-swap`, `paths-swap-keyboard-wide`) run `paths_fixture.py --slow-seconds 10` (#676; pinned in `test_paths_fixture.py`).

## Global Search validation (issue #234, 2026-10-04)

Evidence: `a11y_matrix.py --pages tools/windows/journeys/a11y-search.json --fixture tools/windows/profile_fixture.py --scan --tabs 30` covers all 11 state pages: closed, suggestions, open-hint, loading, results All/Songs/Players/Bands, empty, error and navigated (issue #320 replaced bands-unavailable with results-bands). It ran at compact, medium, wide, maximized and snapped, then under Desert, light and dark theme, text 200%, and display 100% and 150%. The Search page scanned with 0 Axe errors throughout; the suggestion popup hits only item 8. The keyboard pages `kb-global-search` and `kb-titlebar-order(-compact)` pass, and live public-service screenshots were taken.

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

Every run had 0 Axe errors. Fixed: three test IDs sat on elements without a UIA peer (`Border`, `Grid`, `StackPanel`) and are now on the text they identify. The phase row's Narrator name now matches the web's `aria-valuetext` ("Phase. Subphase", "Total not yet known"). Narrator now hears each newly accepted attempt count once (a UIA notification, proven with `listen:announcements`); lower, kept-back reads stay silent. Per configuration: [settings/windows.md](../pages/settings/windows.md#validation-service-info-issue-275-2026-10-06).

## App Navigation validation (issue #225, 2026-10-04)

Evidence: `a11y_matrix.py --scan --tabs 30 --pages journeys/a11y-navigation.json` (anonymous, player, band page, Settings, pane open at compact) at compact, medium, wide, snap-left, snap-right and maximized, plus light and dark theme, Desert, Night sky, text 200% and display 100%/150%: 0 Axe errors except the open minimal pane (WinUI popup-host finding, open issue 8). `journeys/navigation.py` covers `songs`, `leaderboards`, `settings`, `player`, `band`, `reselect`, the compact pane and keyboard use (8/8 pass). Per configuration: [app-navigation/windows.md](../controls/app-navigation/windows.md#validation-issue-225-2026-10-04).

Fixed: keyboard focus entering the pane from the title bar (Tab from profile) or the minimal pane opening from the toggle landed on Songs rather than the selected section; NavigationView only does this for a Tab that passes through itself.

## Navigation pane corners validation (issue #255, 2026-10-05)

Evidence: `a11y_matrix.py --scan --tabs 20 --pages journeys/a11y-pane-corners.json` (pane closed, overlay, inline, collapsed rail) ran with fixtures and live (`--live`). It covered compact, medium, wide, maximized and both snap halves, plus light and dark theme, Desert, Night sky, text 200% and display 100%/150%. Every state passes. Axe found 0 errors except on the open overlay (open issue 8), and Tab stops stay in the window without repeats. `navigation.py compact keyboard` passes. No app code changed. Per configuration: [app-navigation/windows.md](../controls/app-navigation/windows.md#pane-corners-validation-issue-255-2026-10-05).

## Modal component validation (issue #239, 2026-10-04)

Evidence: `a11y_matrix.py --scan --pages journeys/a11y-modals.json` (all eight `FestivalDialog` callers: Settings Reset, Privacy Policy, Report an Issue, Suggest a Feature, What's New, Licenses, First Run, the Karaoke Paths notice, Paths, and both profile confirmations) with fixtures, plus live public-service runs (`--live`, no profile pages). Every run: Esc closes, focus returns to the invoker, Tab stays inside the dialog (2–7 stops) and Axe found 0 errors.

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

## Modal accessibility tests (issue #400, 2026-10-08)

`journeys/modals.json` became `journeys/a11y-modals.json`. The `windows-ui` workflow (`.github/workflows/windows-ui.yml`) builds the Debug app, sets the runner display to 1920×1080 (`tools/windows/ci_display.ps1`) and runs `tools/windows/ui_ci.py`, which runs this file through `a11y_matrix.py --scan --tabs 30` at default text (compact, medium) and at `--mode text-225` (compact). Each `FestivalDialog` page first waits for its title and body text to be on screen (`waitfor`), then asserts:
- the Narrator phrase of every command (for example "Cancel, button", "Submit, button, unavailable", "Back, button, unavailable");
- the reading order: the title (What's New: its list), the body, the commands, and Close last (modal-shell R2);
- Close and every alert command at least 40×40 epx, with hit probes 18.5 epx left, right, up and down from the centre (the #271 probe);
- that Tab from the last body control reaches Close.

`tests/test_modal_journeys.py` maps every `FestivalDialog.Create` caller to its pages and fails when one has none, drops a check or leaves the `windows-ui` runs; `tests/test_ui_ci.py` checks the runs and the workflow. Fixed (design review of #468): `ContentDialog` commands were WinUI's 32 epx tall, under the 40 epx Windows target; `DialogChrome.CommandTargets` now raises Primary, Secondary and Close to `FSTMinTargetSize` (40 epx) for every `FestivalDialog` ([modal-shell](../patterns/modal-shell.md) agent decision #400). Microsoft Learn, Targeting: "In general, set your touch target size to 7.5mm square range (40x40 pixels …)."

| Configuration | Result |
| --- | --- |
| Compact, medium, wide (all 11 pages, `--scan --tabs 30`) | Pass, Axe 0 |
| Text 200% (compact, all 11 pages) | Pass, Axe 0. Probes in the scrolled Feedback body first `scrollinto` the control |

Fixed (test only): the First Run page still asserted the template `CloseButton` ID, but #244 gave that Close `fst.first-run.close`. No app defect was found.

## Modal legibility accessibility tests (issue #518, for #239, 2026-10-12)

The #400 runs above cover the modal shell's names, roles, reading order, targets and keyboard. `journeys/a11y-modal-legibility.json` adds checks for #239's two rendering fixes. `ui_ci.py` runs it as `modal-legibility-desert` (compact, medium), `modal-legibility-night-sky` (compact) and `modal-legibility-text-225` (compact), all with `--scan --tabs 30`. Every page is limited to its `modes`, so default text has no run here; `modals` already covers it.
- **No contrast backplate.** Under Desert and Night sky, `assertpaint` probes a 24×10 epx area around the label of the First Run Next and the Reset dialog's Cancel and Reset. The probe passes when the area contains the button's own fill colour (`@fill`, sampled at the left padding). The First Run pips are probed too: the selected pill must be Highlight (Desert #903909, Night sky #D6B4FD), its dot HighlightText and an unselected dot WindowText. At this host's 300% scale the pips sit below the fold, so the page first runs `scrollto:id=fst.first-run.body,100`.
- **Hints wrap.** At 225% text, `assertmarquee …|wrapped|60` checks that the Report an Issue hints for Title, Description and Expected Behavior are wrapping TextBlocks at least 60 epx tall. The Title hint also sits below its header, the edit fields read their hint as HelpText, Tab moves from Expected Behavior to Attach Media, and Esc restores focus to the Settings row.

Negative controls: with `CommandLabelsWithoutBackplate`/`WithoutBackplate` removed, the label probe failed with "0 px within 16 of #903909" (Desert) and "… of #D6B4FD" (Night sky), and the selected pip dot turned WindowText. With the hint as a string `Description`, the hint wait failed ("no on-screen element … class=TextBlock").

| Configuration | Result |
| --- | --- |
| Desert (compact, medium), Night sky (compact), text 225% (compact) at this host's 300% scale | Pass, Axe 0 |
| The same with `+scale-100` (the runner's 100% scale) | Pass, Axe 0 |

No app defect was found.

## Song leaderboard accessibility tests (issue #443, 2026-10-08)

Backfills CI tests for the #93 Windows change (rows fade above the floating pinned row and pager; paging keeps the header, pinned row and pager). New `journeys/a11y-song-leaderboard.json` (fixture `--song-leaderboard-paging`, Fixture Player 1 selected) and the song-board pages of `a11y-board-footer-fade.json` are now `windows-ui` runs in `tools/windows/ui_ci.py`. They assert:
- the pinned row's and pager's Narrator phrases and states: "Your rank, 1st. Open your statistics. …, button", "First page, button, unavailable", "Page 1 of 4, text", then "Page 2 of 4, text", "Previous page, button" and "Your rank, 1st. Jump to your position. …" after a page change;
- the four pager buttons and the pinned row are at least 40×40 epx, and the pinned row doesn't overlap the pager;
- the reading order is header → rows → pinned row → First → Previous → page text → Next → Last, and it holds while the next page loads, with the rows gone and the ring named "Loading leaderboard";
- the keyboard (Tab) order, separately from the reading order, with `key:tab` / `key:shift+tab` and `assertfocus` at each stop (`song-board-paging-keyboard`, added after the design review of #505):
  - page 1 at rest: header → first row → pinned row → Next → Last (First and Previous are disabled), and back to the header through a row;
  - while the next page loads: Shift+Tab goes from Next to the pinned row and then the header, with no row or disabled First/Previous in between, and Tab returns to Next. These steps run before the ring's "Loading leaderboard" read, so they can only pass mid-load;
  - page 2: from Next, Shift+Tab reaches Previous → First → pinned row → a row → header, and Tab walks back through every pager button to Last;
- a keyboard page change (Enter on Next, focused directly so it stays a separate check) keeps focus on Next during and after the load;
- the footer-fade layer is out of the control view but fades rows over 40 epx, with a hard edge under More Contrast and Less Transparency.

Every page is Axe-scanned. `song-board-footer` and the footer-fade pages also get the dispatcher's 30-press Tab walk (no stop outside the window, no repeat). `song-board-paging-keyboard` sets `tabs: 0` because the ordered traversal above replaces that walk. The paging page ends by focusing the header: the keyboard tooltip on a pager button ("Next page (Ctrl+Right)") otherwise leaves a `PopupHost` input site that Axe reports as `BoundingRectangleCompletelyObscuresContainer` (open item 8, a framework finding). `tests/test_song_leaderboard_a11y_journey.py` pins the checks, the traversal and the runs.

| Configuration | Result |
| --- | --- |
| Compact, medium (`song-leaderboard`, both pages) | Pass, Axe 0. The `song-board-footer` Tab walk makes 10–12 stops (title bar, header, list, pinned row, enabled pager buttons, Back), none outside the window or repeated. The ordered traversal passes at rest, mid-load and on page 2 |
| Text 225% (compact, both pages) | Pass, Axe 0, traversal included |
| In-app Reduce Motion (medium, paging) | Pass, Axe 0, traversal included |
| Footer fade rest, mid, end, More Contrast, Less Transparency (compact, medium; compact at 225%) | Pass, Axe 0 |

No accessibility defect was found.

## Full Rankings pinned row accessibility tests (issue #466, 2026-10-11)

Backfills CI tests for the #318 Windows change: the selected player's row stays pinned above the pager on Full Rankings, even on their own page. Before this, its journeys (`full-rankings.json`, `full-rankings-keyboard.json`) weren't `windows-ui` runs. Only `grouped-full-rankings` checked the order and one Tab. New `journeys/a11y-full-rankings.json` (`rankings_fixture.py`) is now a set of `windows-ui` runs in `tools/windows/ui_ci.py`. They assert:
- on the player's own page (Fixture Player 2, #2): the pinned row reads "Your rank, 2nd. Open your statistics. Fixture Player 2. Total Score …, button"; the pager reads "First page, button, unavailable", "Previous page, button, unavailable", "Page 1 of 48, text", "Next page, button" and "Last page, button";
- the pinned row and four pager buttons are at least 40×40 epx, and the pinned row doesn't overlap the pager;
- the reading order is title (Level 1 heading) → the player's own row in the list → pinned row → First → Previous → page text → Next → Last, and the fade layer stays out of the control view while fading rows over 40 epx;
- the Tab order on the player's page: row → pinned row → Next → Last, Shift+Tab back to the pinned row, and Enter on it opens the profile;
- off the player's page (Fixture Rank 40): the pinned row reads "Jump to your position". Enter jumps to page 2 and keeps focus on the pinned row, which now reads "Open your statistics". The pager reads "Page 2 of 48" with First and Previous available, the order is row 40 → pinned row → pager, and Tab and Shift+Tab move between the pinned row and First.

`fr-pinned-own-page` also gets the dispatcher's 30-press Tab walk. The two keyboard pages set `tabs: 0` because their ordered traversal replaces it. `tests/test_ui_ci.py` pins the runs and the key checks.

| Configuration | Result |
| --- | --- |
| Compact, medium (`full-rankings-pinned`, all 3 pages) | Pass, Axe 0 |
| Text 225% (compact, all 3 pages) | Pass, Axe 0; the pinned row's two lines grow without clipping above the pager |
| In-app Reduce Motion (medium, jump) | Pass, Axe 0 |

No accessibility defect was found.

## Full Rankings pinned row load gate accessibility tests (issue #524, 2026-10-11)

Backfills CI tests for the #270 Windows change (PR #320): Full Rankings' pinned "your rank" row joined the rows' load gate (`LoadSwapGate`) for Rank By and instrument reloads, but stays beside the spinner on a page-only reload. Before this, only the feature journey `full-rankings-swap.json` (presence checks) covered it. New `journeys/a11y-full-rankings-swap.json` (`rankings_fixture.py --rankings-delay`, Fixture Rank 40 selected, off page 1) is a set of `windows-ui` runs in `tools/windows/ui_ci.py`. They assert:
- `fr-swap-rank-by`: after Rank By → FC Rate, the pinned row and pager leave UIA; Narrator reads "Busy Loading rankings, ProgressRing" in title → Rank By → ring order; Tab from Rank By goes to the title bar's Back (no hidden pinned row or pager stop) and Shift+Tab returns. The new row then reads "Your rank, 40th. Jump to your position. Fixture Rank 40. FC Rate …, button", is focusable, invokable, 40×40 epx and apart from Next, in rows → pinned row → pager order. An instrument switch repeats the hide and return; Tab and Shift+Tab then move row → pinned row → Next and back. Mid-load and settled Axe scans;
- `fr-swap-page-keeps-pin`: a page-only reload (Enter on Next) keeps the pinned row readable ("… Total Score …, button"), focusable and 40×40 epx beside the ring, in Rank By → ring → pinned row → pager order and clear of the ring; Shift+Tab from Next reaches it mid-load. Page 2 then scrolls to row 40, and the pinned row reads "Open your statistics" in row 40 → pinned row → pager order;
- `fr-swap-motion-reduced` (in-app Reduce Motion) and `fr-swap-motion-system` (Windows Animation effects off): the row still hides under the ring, then returns with the FC Rate value and holds still (`assertmotion`).

The pages set `tabs: 0` because their ordered traversals replace the walk. `tests/test_ui_ci.py` pins the runs and the key checks.

| Configuration | Result |
| --- | --- |
| Compact, medium (`full-rankings-swap`, 2 pages) | Pass, Axe 0 |
| Text 225% (compact, 2 pages) | Pass, Axe 0 |
| In-app Reduce Motion (medium, 3 pages) | Pass, Axe 0 |
| Animation effects off (medium, 3 pages) | Pass, Axe 0 |

No accessibility defect was found.

## Leaderboards card your-rank row accessibility tests (issue #493, 2026-10-11)

Backfills CI tests for the #370 Windows change (PR #403): a Leaderboards card's separate "your rank" row, for a player ranked outside the card's top ten, now opens Full Rankings on the player's page and reveals their row instead of opening the profile. Until now only `selected_reveal_journey.py --only rankings-card` (fade timing) and `LeaderboardsViewModelTests` covered it. New `journeys/a11y-leaderboards-card-jump.json` (`rankings_fixture.py`) is now a set of `windows-ui` runs in `tools/windows/ui_ci.py`. They assert:
- `card-jump-row` (Fixture Rank 40): the Lead card's row reads "Your rank, 40th. Jump to your position. Fixture Rank 40. Total Score …, button" (Button, Invoke, focusable), is at least 40×40 epx, doesn't overlap View All Rankings (40 epx tall), and reads after the card's Lead group and before View All;
- `card-jump-row-keyboard`: Shift+Tab from View All reaches the row, Tab goes back. Enter opens Full Rankings on "Page 2 of 48" with row 40 on screen; the pinned row then reads "Open your statistics", and the order is title → row 40 → pinned row → pager. Alt+Left returns to Leaderboards with focus on the card's row;
- `card-in-place-row` (Fixture Player 2, inside the top ten): no separate row; the highlighted in-list row reads "Your rank, 2nd. …, button" without a jump, is 40 epx tall, and Enter opens the profile.

`card-jump-row` also gets the dispatcher's 30-press Tab walk. At compact the card is taller than the window, so the pages scroll View All into view and check the row against the card's group rather than its heading.

| Configuration | Result |
| --- | --- |
| Compact, medium (`leaderboards-card-jump`, all 3 pages) | Pass, Axe 0 |
| Text 225% (compact, all 3 pages) | Pass, Axe 0 |
| In-app Reduce Motion (compact, medium; all 3 pages) | **Failed, fixed:** Enter opened page 2 but left the list at the top (rows 26–34), so the player's row stayed off screen. Under Reduce Motion `SelectedRowReveal` scrolled at once, before the newly shown list had a layout, so `StartBringIntoView` did nothing. It now waits, as the motion path already did, for the list to realize the selected (or first) row, then scrolls at once with no hold or rush (load-transition R6). Pass, Axe 0 after the fix; `selected_reveal_journey.py` gained `rankings-card-reduce-motion` |

## Search All section titles accessibility tests (issue #483, 2026-10-11)

Backfills CI tests for the #348 Windows change: in the All scope, Search titles each shown section "Songs", "Players" and "Bands" (`FSTSectionHeaderStyle`, Level 2, fading in with the rows). Before this, only the `search.json` feature journey (not a `windows-ui` run) checked all three titles; `search-all-hides-empty-players` checked the Songs title alone. New pages in `journeys/a11y-search.json` (`profile_fixture.py`, `q=fixture`) are explicit `windows-ui` runs in `tools/windows/ui_ci.py` (`search-sections`, `-text-225`, `-reduced-motion`). They assert:
- `search-all-sections`: All is selected; each title reads "Songs, text", "Players, text", "Bands, text", is a Level 2 heading and isn't keyboard focusable; the reading order is All → Songs title → song rows, then each later title before its own rows (revealed by UIA scrolling, so it holds at 225% text); each title sits above its rows without overlapping them (`assertapart`, `assertbelow`), and the next title sits below the previous list;
- `search-all-sections-keyboard` (`tabs: 0`): Tab walks field → All → first song → first player → first band card and Shift+Tab walks back, never stopping on a title;
- `search-results-songs`, `-players`, `-bands` (generated runs): the scope is selected, no section title is shown and its rows follow the scope bar (issue #299).

`tests/test_ui_ci.py` pins the runs, that the file's other pages keep their generated runs, and the key checks.

| Configuration | Result |
| --- | --- |
| Compact, medium (both pages; single-scope pages) | Pass, Axe 0 |
| Text 225% (compact, both pages; single-scope pages compact, medium) | Pass, Axe 0 |
| In-app Reduce Motion (medium, both pages) | Pass, Axe 0; the titles appear with their rows |

No accessibility defect was found. Harness rule: `assertbelow`, `assertapart` and `assertorder` need both elements on screen, so each later title's checks follow the `reveal:` of its first row (at 225% text the Bands title starts below the fold).

## Song Band Leaderboard accessibility tests (issue #510, 2026-10-11)

Backfills CI tests for the #196 Windows change: each band card on a song's Duos/Trios/Quads board is one Narrator stop named in visual order, the empty and failure states name themselves, and the accuracy pill follows contrast themes. Before this, `windows-ui` checked the header (`a11y-song-leaderboard-header.json`), the pin (`a11y-song-band-pinned.json`), the rank rail and a partial row phrase in the load swap, but not the full row phrase, the row's role, its parts staying out of the control view, the empty state or the pill. New `journeys/a11y-song-band-leaderboard.json` (`rivals_fixture.py`, `Band_Duets`; `Band_Trios` empty; `missing-song` failure) is a set of `windows-ui` runs in `tools/windows/ui_ci.py` (`song-band-board`, `-text-225`). They assert:
- `sbl-rows`: rows 1 and 2 read "Rank 1. Band 1 Member A, Lead, 94,500 points. Band 1 Member B, Bass, 94,000 points. Team score 94,500 points, full combo, 96.5% accuracy, 5 stars, list item" (row 2 without "full combo"); the row is a `ListItem` with Invoke, focusable and at least 40 epx tall; its `.rank`, `.accuracy` and the star row exist in the raw view only, and no member name, instrument, `.members` or star `Image` is in the control view; reading order header → size switcher → row 1; Down/Up move between rows, Enter opens Band Detail and Back returns to the row;
- `sbl-empty`: "No band scores found, text" is a Level 2 heading, not focusable, after the switcher (Trios selected) and before its message; no list, pager or entry total is left;
- `sbl-error`: "Failed to load band leaderboard, text" is a Level 2 heading, then "Retry, button" (40×40 epx, Invoke); Tab and Shift+Tab move between the Trios switcher item and Retry;
- `sbl-accuracy-pill-contrast` (medium, default theme only; it switches Desert on and off in the running app): the pill paints navy `#223047`, then ButtonFace `#FFFAEF` with a ButtonText `#202020` edge under Desert, then navy again (`assertpaint` on the raw `.accuracy` ID).

`tests/test_ui_ci.py` pins the runs and the key checks. `tabs: 0` on every page: the rows' ordered keyboard steps replace the walk.

| Configuration | Result |
| --- | --- |
| Compact, medium (`song-band-board`, all 4 pages; the pill page at medium) | Pass, Axe 0 |
| Text 225% (compact, rows, empty, error) | Pass, Axe 0 |
| Regression check: `StarRow` fix reverted | `sbl-rows` fails: "element id=fst.star-rating.white-5 is still on screen" |

**Failed, fixed:** every band card (and every Raw `StarRow` host: leaderboard rows, Song Detail band previews, Band Detail gold stars, Songs rows; Suggestions and Songs metadata stars, which aren't Raw, keep their `Image`) exposed its stars as a second control-view `Image "5 stars"` inside the one-stop row, so scan mode read the rating twice. `StarRowPeer.IsControlElementCore` returned `true` regardless of the host's `AccessibilityView="Raw"`; it and `IsContentElementCore` now follow `AutomationProperties.AccessibilityView`. Rule: a custom `AutomationPeer` that overrides `IsControlElementCore`/`IsContentElementCore` must honour the owner's `AccessibilityView`, or Raw in XAML silently stops working. `journeys/star-rating.json` now finds leaderboard stars with `raw=`.

## Suggestions accessibility tests (issue #513, 2026-10-12)

Backfills CI tests for the #205 Windows change (PR #128): named filter `Expander`s, one Tab stop per card with arrow keys across rows, neutral contrast pills, and state titles as headings. Until now only `suggestions_journey.py` and the generated `suggestions` matrix page covered it, outside the `windows-ui` job. New `journeys/a11y-suggestions.json` (`suggestions_fixture_server.py`, seed 1) runs in `tools/windows/ui_ci.py` as `suggestions` (compact, medium) and `suggestions-text-225` (compact). It asserts:
- `suggestions-cards`: Filter reads "collapsed" and is at least 40 epx tall; the first card title is a Level 2 heading; a row reads its full name as a focusable button, is at least 40×40 and doesn't overlap the next row; Filter reads before the list, and card names read in order (each card is a list item named by its title, its rows read whole); the dispatcher's 30-press Tab walk stays in the app;
- `suggestions-keyboard`: Down/Up move between rows within a card and across cards without scrolling the list; Tab goes to the next card's first row, Shift+Tab back and then to Filter; Enter opens the flyout on Instruments, and Esc returns focus to Filter, which reads "collapsed";
- `suggestions-filter`: Filter reads "expanded"; the title is a Level 2 heading and Instrument-Specific Level 3; Instruments and General read their names, state and help text and are at least 40 epx tall, as is Reset; the order is title → Instruments → General → Reset, and Instrument-Specific → picker → Reset (picker arrows 40×40); Enter expands Instruments and Tab lands on "Lead, toggle switch, on" (40×40), then Bass; Space toggles Lead and enables Reset; General expands and reads its switches;
- `suggestions-syncing` and `suggestions-no-results`: each state title is a Level 2 heading after Filter; no-results turns every type off in the flyout, and Esc leaves focus on Filter with no list;
- `suggestions-rival-pill-contrast` (medium): in normal mode the rival pill keeps its brand fill; after a live switch to Desert it paints the ButtonFace fill and ButtonText outline, and the brand fill returns after switching back.

`tests/test_ui_ci.py` pins the runs and the key checks; `SuggestionsAccessibilityMarkupTests` guards the fixes in markup.

| Configuration | Result |
| --- | --- |
| Compact, medium (all pages; rival contrast at medium) | **Failed, fixed** (two defects, below). Pass, Axe 0 after the fixes |
| Text 225% (compact, all pages but rival contrast) | **Failed, fixed:** the flyout ran off the window, so Reset was off screen. Pass, Axe 0 after the fix |
| Desert contrast, switched live (medium) | **Failed, fixed:** the rival pill kept its brand fill (#D9E3F0 sampled). Pass after the fix |

Defects fixed:
- **Live contrast switch:** `SuggestionSongRow` set its brushes once, so a page left open across a contrast switch kept the brand rival pill, separator, chevron and subtitle colour. It now re-resolves them and rebuilds its metadata on `ContrastTheme.Changed` (as `LeaderboardEntryRow` and `MetadataPill` do; [metadata-pills](../patterns/metadata-pills.md)).
- **Unnamed Tab stop:** the three filter `ItemsControl`s were Tab stops, so after expanding a section Tab first landed on an unnamed pane. They are now `IsTabStop="False"`, as on Songs and Shop.
- **Reset off screen:** the filter form didn't fit the space below its button. `OnFilterOpening` now clamps its height and width to the window, as Songs and Shop do.

Harness rules: the flyout's expanded sections push later controls below the fold at 225% text, so each `assertorder`, `focus` or `expand` past the fold follows a `reveal:` (UIA scroll, no input). `assertread` phrases never include the heading level, so headings use `assertstate:…|heading=N`. A card's own Group and title TextBlock are not in the Narrator order (the card list item is named by its title).

## Delayed and loaded-later content accessibility tests (issue #521, for #260, 2026-10-12)

Backfills CI tests for the #260 Windows change (PR #274): Suggestions cards loaded after the first ten fade in on arrival (`FadeIn.Restagger(list, batchStart)` from `CardsAdded`), and Global Search song rows that waited behind the spinner for a slow player search fade in when it clears. The `fade_trace` perf-log journeys (`suggestions_journey.py fade`, `search_journey.py fade-delayed-results`) check the fades themselves, but they're outside `windows-ui`, and no CI page reached a later batch or a delayed result. New pages are explicit `windows-ui` runs in `tools/windows/ui_ci.py`:
- `a11y-suggestions.json` `suggestions-load-more` (seed 1; batch 2 is cards 11–16): card 12 "Dominate Rival A2" exists only once batch 2 has loaded, and its title is a Level 2 heading; its first row reads its full name as a focusable button of at least 40×40; card 11's title is a heading, and "New on Pro Lead" (card 10, the last card of batch 1) reads before "Protect Your Lead vs Rival B2" (card 11). A change to seed 1's mix (#656 named-rival cards) re-pins every seed-1 card id and title in `suggestions_journey.py` (`RIVAL_CARD`, `TWELFTH_CARD`), `a11y-suggestions.json` and `a11y-wide-columns.json` together (#661);
- `suggestions-load-more-keyboard` (`tabs: 0`): Down from card 10's last row lands on card 11's first row and Up returns; Tab walks cards 11–16 one stop each into card 17's row (batch 3, loaded by the walk), and Shift+Tab steps back;
- `a11y-search.json` `search-delayed-results` (`profile_fixture.py`, whose new `SLOW_SONG_PREFIX` "puls" answers player searches after 4 s while "Fixture Pulse" matches at once): while the spinner runs, it reads "Busy Searching, ProgressRing", no song row or section title is shown, and focus stays in the field; afterwards "Songs, text" is a Level 2 heading that isn't focusable, read between All and "Fixture Pulse by Synthetic Quartet, list item" (40×40, clear of the title); no Players section or empty state shows; and Tab goes field → All → row, with Shift+Tab back.

The Suggestions pages run in the full `suggestions` and `suggestions-text-225` runs, then in `suggestions-load-more-reduced-motion` (in-app Reduce Motion) and `-no-animations` (Windows Animation effects off), both at medium. The Search page runs as `search-delayed-results` (compact, medium), `-text-225` (compact) and `-reduced-motion` (medium). `tests/test_ui_ci.py` pins the runs and the key checks, and `tests/test_profile_selection.py` pins the slow song search.

| Configuration | Result |
| --- | --- |
| Compact, medium (all three pages; Tab walk 30 on `suggestions-load-more`) | Pass, Axe 0 |
| Text 225% (compact, all three pages) | Pass, Axe 0 |
| In-app Reduce Motion (medium, all three pages) | Pass, Axe 0; the cards and rows appear in place |
| Animation effects off (medium, Suggestions pages) | Pass, Axe 0 |

No accessibility defect was found. Fixed (test only): the first draft of the keyboard page ended its Shift+Tab on a list offset where card 18 sat exactly on the viewport's bottom edge, which gave 6 Axe `BoundingRectangleSizeReasonable` findings ([item 3](#open-issues)). Both Suggestions pages now end on `scrollinset:…|8` before the scan. Harness note: `assertmotion:…|still` can't prove that a 400 ms batch fade didn't play (its captures are 1.2 s apart, and the batch loads with the realization cache before any scripted scroll), so Reduce Motion fade evidence belongs to the perf-log `fade-play … motion=0` lines, not a matrix page.

## Item Shop offers accessibility tests (issue #516, 2026-10-12)

Backfills CI tests for the #224 Windows change (PR #168): Shop tiles named by title, artist · year and state, the List/Grid toggle (wide windows only, same height as Filter), contrast-safe captions and Leaving pill, and only the active ring exposed as "Busy Loading Item Shop". Until now `shop_journey.py` checked these only for visibility, and the generated `shop`/`shop-list` pages checked the Axe scan. New `journeys/a11y-shop-offers.json` (default fixture plus `shop_fixture.py` modes) runs in `tools/windows/ui_ci.py` as `shop-offers` (compact, medium), `shop-offers-text-225` (compact, medium) and `shop-offers-reduced` (medium, app Reduce Motion, the toggle page). It asserts:
- `shop-offers-grid-read` (medium, wide): tile phrases "Fixture Orbit, Synthetic Quartet · 2026, Leaving Tomorrow, button" and "…, New, button", focusable and invokable; "Item Shop" heading 1; order title → count → Sort → Filter → toggle → tiles; the toggle reads "List View, button", is at least 40 epx tall, is level with Filter and hit-testable at its top and bottom edges (not covered by a tile); tiles 40×40 and apart; no loading ring in UIA;
- `shop-offers-grid-compact`: no toggle; same tile phrases and order;
- `shop-offers-view-toggle` (medium): Enter switches to the list and Space back, focus stays on the toggle, its name flips "Grid View" ↔ "List View", it stays level with Filter, the reveal ring leaves UIA, and Tab then lands on the first tile;
- `shop-offers-text-wrap` (medium, 225% text only): the wrapped toggle keeps its name and 40 epx target, stays in order after Filter, and overlaps neither Sort, Filter nor a tile;
- `shop-offers-loading`: a slow read shows one ring reading "Busy Loading Item Shop, ProgressRing" with no toggle, Filter or grid, and it leaves UIA once the tiles land;
- `shop-offers-empty`, `-failed`, `-hidden`: no toggle, Sort or Filter; the empty title reads as text, Retry is 40 epx, and "Item Shop Is Hidden" is heading 2;
- `shop-offers-contrast-live` (medium, default text): the Leaving pill paints #C62828, after a live switch to Desert it paints Highlight (#903909) with no WindowText backplate and the caption plate paints Window, and the red returns after switching back.

`tests/test_ui_ci.py` pins the runs and key checks; `WrapLineLayoutTests` guards the wrap rule.

| Configuration | Result |
| --- | --- |
| Compact, medium, wide (all pages; contrast at medium) | **Failed, fixed** (two defects, below). Pass, Axe 0 after the fixes |
| Text 225% (compact, medium) | Pass, Axe 0 |
| App Reduce Motion (medium, toggle page) | Pass, Axe 0 |

Defects fixed:
- **List View under the tiles:** at default text in medium and wide windows the toggle sat a line below Filter, and at medium the tile grid covered it. `WrapPanel` measured one line, but layout rounding handed arrange a fraction of a pixel less, so arrange broke the line that measure had kept and drew the toggle outside the reserved height. Measure and arrange now share `WrapLineLayout.Lines` with a 1 epx tolerance ([page-tools-and-nav-chrome](../patterns/page-tools-and-nav-chrome.md) R11). The fix also reaches the other `WrapPanel` consumers: the Rivals page and rows, profile/Statistics title actions, Song Detail and notification rows.
- **Live contrast switch:** the Leaving pill and the pulse ring took their brushes once, so a page left open across a contrast switch kept the brand red pill (with a Window backplate on its text) and the brand outline. `ShopPulseRing` now repaints on `ContrastTheme.Changed` (Songs rows and first-run demos too), and `ShopPage` re-applies `ApplyBadge` to realized tiles and rows ([shop-offer-status](../patterns/shop-offer-status.md) R6).

Harness rules: the ProgressRing peer prefixes its busy state, so assert ring names as "Busy Loading …" (a `waitgone:name=Loading …` passes trivially). Pages that assert the toggle level with Filter skip `text-225`, where it wraps by design (R11).

## Leaderboard row columns accessibility tests (issue #519, 2026-10-11)

Backfills a CI test for the #242 Windows change: `LeaderboardEntryRow` sets its surface, text and badge brushes in code and re-applies them on `ContrastTheme.Changed`; the selected row's FC badge paints HighlightText under contrast; the pager's disabled brushes are theme dictionaries. The column fitting itself (#37) was already covered by `journeys/a11y-leaderboard-columns.json` (#409: names, 40 epx targets, rows → pinned row → pager order, keyboard, focus not obscured, text 200%/225%), and `a11y-pager-dim.json` covers a cold-launch contrast pager, but nothing switched contrast with a board open. New page `cols-song-board-contrast-switch` (medium, default theme only; it switches Desert on and off in the running app) in the same file runs in the generated `a11y-leaderboard-columns-normal` `windows-ui` run. It asserts:
- before the switch, row 3 isn't Window `#FFFAEF`, row 2 (the selected player) isn't Highlight `#903909`, and its FC badge is gold `#FFD700`;
- under Desert, row 3 paints Window, row 2 and the pinned row Highlight, both FC badges HighlightText `#FFF5E3` with no WindowText `#3D3D3D` or gold left, and the disabled First page a WindowText edge with GrayText `#676767` glyph; row 3, the pinned row and First page ("…, button, unavailable") read whole; rows and the pinned row stay at least 40 epx tall and Next page 40×40; order rows → pinned row → First page → Next page; Axe scans the Desert board;
- after switching back, the default brushes return.

`tests/test_ui_ci.py` (`test_leaderboard_columns_contrast_switch_runs_in_the_normal_pass`) and `test_a11y.test_leaderboard_column_pages` pin the page.

| Configuration | Result |
| --- | --- |
| `a11y-leaderboard-columns-normal`, `-text-225`, `-text-200` (existing pages) | **Failed, fixed** (stale expectation, below). Pass, Axe 0 after the fix |
| `cols-song-board-contrast-switch`, medium, Desert switched live | Pass, Axe 0 |
| Regression check: `ContrastTheme.Changed` subscription removed | Fails: row 3 keeps the card surface under Desert (0 px of `#FFFAEF`, centre `#464A53`) |

No app accessibility defect was found. **Failed, fixed (test):** since #606 the season pill names the current season "current season 9", but the column pages still expected "season 9", so `cols-song-board` failed. The expectations now say "current season 9"; Fixture Player 2's board row still reads the board's 98% (only the selected player's pinned row reads the profile's 97.9%).

## Songs Filter without a profile (issue #432, 2026-10-08)

Accessibility tests for #77. The no-profile Filter pages moved into `journeys/a11y-songs-filter.json` (`songs-filter-anonymous`, `songs-filter-anonymous-year`, `kb-songs-filter-anonymous`), which `tools/windows/ui_ci.py` runs in `windows-ui` at default text (compact, medium) and 225% text (compact); `tests/test_ui_ci.py` keeps both runs. They assert Narrator phrases, reading order, 40×40 epx targets, the toggle and expand states, the applied "Filters applied" status and the keyboard walk ([songs-filter windows](../controls/songs-filter/windows.md#accessibility-tests-issue-432-no-profile)).

Fixed: the flyout **Reset** footer and the Year/Duration **Select All / Clear All** links were 31–32 epx tall, under the 40 epx target; they and the Sort, Item Shop and Suggestions Reset footers now use `FSTMinTargetSize` (`HitTargetMarkupTests`). Fixed (tooling): the FstUia Narrator model skipped the offscreen, empty-bounds `Popup` window that hosts flyout content, so `assertorder` could not see a flyout; it now walks through that host.

| Configuration | Result |
| --- | --- |
| Compact, medium (3 pages, `--scan --tabs 30`) | Pass, Axe 0 |
| Text 225% (compact, 3 pages) | Pass, Axe 0 |

## Songs section push (issue #452, 2026-10-08)

Accessibility tests for #288's Windows section push. `journeys/a11y-songs-section-push.json` (`push-band`, `push-band-reverse`) runs on the large fixture catalogue; `tools/windows/ui_ci.py` runs it in `windows-ui` at default text (compact, medium) and 225% text (compact), both with `--scan`, and `tests/test_ui_ci.py` keeps both runs and the key steps. A Jump pick of M then `scrollinset:` puts the M title 16 epx below the list top (`push-band` scrolls down to it from 96 epx, `push-band-reverse` up from the pinned title), inside the 40 epx push band, where `IncomingHeader` draws a copy over it. The pages assert:
- the copy is drawn (`assertname:raw=fst.songs.section-header.incoming|M`) but isn't in the control view, so Narrator and scan mode never meet the title twice;
- the pinned bar still reads "L, text" as a level-2 heading, and the transparent in-list title reads "M, text" as a level-2 heading;
- Narrator's order is Jump → bar → M title;
- at 96 epx the copy is gone again;
- Jump keeps its name and 40×40 epx target.

The push follows the scroll with no animation of its own, so Reduce Motion has nothing to stop. Keyboard (`push-band-keyboard`, design review of #510): the Jump grid is driven by keys to M, focus is put on the first M row in the band, and arrow keys move it onto the focusable M group header (still in the band, copy drawn, focus rectangle visible over the transparent title) and out to the last L row, then back; `assertfocus:` proves focus is always on the real row or header, never the copy, and Tab from Jump re-enters the list on the remembered row. Harness finding: a UIA Scroll-pattern set (`scrollinset:`, `scrollto:`) while a grouped `ListView` item has focus can move focus to an offscreen group header and drop the list's Tab entry, at any inset and with or without the push; a mouse-wheel or keyboard scroll keeps both, so it isn't a user-facing defect. Keyboard pages therefore scroll with focus outside the list, then `focus:` a visible item. No app defect was found; the copy gained only its raw-view test ID. Check: with the copy's `AccessibilityView="Raw"` removed, `push-band` fails (`waitgone:id=fst.songs.section-header.incoming`). Fixed (test only): an Axe `BoundingRectangleSizeReasonable` on a row title clipped to zero height at the viewport bottom (item 3) appeared at one exact medium-size position, so the pages reach the band from a Jump pick of M rather than L. The past-the-band pin is 96 epx (#685, release run 40710196605): at 120 epx `push-band-reverse` compact scanned with `fixture-song-58`'s top exactly on the list's bottom edge (M title +424 epx, list 544.5 epx tall), zero-height, while `push-band-back`'s identical position happened to report it offscreen. Measured edge collisions for M-title insets are 82/112 epx (a row bottom on the top edge) and 120.5/124.5 epx (a row top on the bottom edge) across compact, medium and 225% text; 96 is at least 14 epx from each, and 16 epx (the band) stays clear too. Re-measure before changing either inset.

| Configuration | Result |
| --- | --- |
| Compact, medium (3 pages, `--scan`) | Pass, Axe 0 |
| Text 225% (compact, 3 pages) | Pass, Axe 0 |

## Songs scrolling (issue #520, 2026-10-11)

Accessibility tests for #247's Windows Songs scroll fix (the pinned title re-read after a non-animated jump's last view change). `journeys/a11y-songs-scroll.json` runs on the large fixture catalogue; `tools/windows/ui_ci.py` runs it in `windows-ui` at default text (`songs-scroll`: compact, medium), 225% text (`songs-scroll-text-225`: compact) and Windows Animation effects off (`songs-scroll-no-animations`: compact, where keyboard End/Home are non-animated jumps), all `--scan`; `tests/test_ui_ci.py` keeps the three runs and the key steps. The pages assert:
- `songs-scroll-far-jumps`: UIA Scroll-pattern jumps (Narrator and scroll-bar moves) to 100, 25, 75 and 50%, each landing in a letter range disjoint from the previous one, so a stale pinned title fails; the title stays a level-2 Text heading, Narrator reads Jump → title → list, and Jump keeps its name and 40×40 epx. Before its scan it pins `fixture-song-49` (Lumen Theory, the last L row) 8 epx below the list top and checks the title reads L (#618: the 50% position left a row title zero-height on the bottom edge in CI `no-animations`).
- `songs-scroll-fling-back`: bottom → top → 3% → top ends at `scroll=0` with the title reading "#, text" before the first row.
- `songs-scroll-keyboard`: End moves focus to the last row (`fixture-song-105`, 40 epx) with the title in X–Z; Home returns focus to the first row and the title to "#, text".

Ranges, not exact letters, because the letter at a scroll percent depends on window size and text scale (medium: 25% D, 50% K, 75% R, 100% Y). Check: with both re-reads removed (`OnScrollerViewChanged` settle and `RecheckHeaderAfterLayout`), `songs-scroll-far-jumps` fails ("#" pinned after the jump) at compact and medium; with only #247's settle removed it still passes, since #248's after-layout re-read covers the same case. No accessibility defect was found, so no app code changed. The live-only `songs-scroll-a11y.json` (anonymous or SFentonX, no name checks) stays a host check.

| Configuration | Result |
| --- | --- |
| Compact, medium (3 pages, `--scan`) | Pass, Axe 0 |
| Text 225% (compact, 3 pages) | Pass, Axe 0 |
| Animation effects off (compact, 3 pages) | Pass, Axe 0 |

## Feedback Form validation (issue #236, 2026-10-05)

Evidence: `a11y_matrix.py --scan --pages journeys/a11y-feedback.json --fixture tools/windows/feedback_fixture.py` (one page per state: `unavailable`, `editing-empty`, `invalid`, `editing-dirty`, `attachments`, `discard-confirm`, `sending`, `filing`, `sent`, `error`) at compact, medium, wide, maximized and both snaps, then Desert, Night sky, light and dark theme, text 200% and display 100%/150%: 0 Axe errors in the dialog. The only findings are 2 on Settings behind the dialog (open issue 7, medium at display 150%). `journeys/feedback.py` (`unavailable`, `validation`, `submit`, `error`) passes at every size preset. The live public service has `feedback:false`, so only `unavailable` is reachable there. Per configuration: [feedback-form/windows.md](../controls/feedback-form/windows.md#validation-issue-236-2026-10-05).

Fixed (`Controls/FeedbackDialog.cs`):
- Submit didn't say why it was disabled; a validation line (`fst.settings.feedback.validation`) now names the missing field.
- The discard prompt and file picker left keyboard focus on the dialog root; focus now lands on Keep Editing and back on Attach Media.
- Sending, filing, sent and error weren't announced to Narrator.
- Attachment tiles used fixed colours under contrast themes; they now use theme brushes.
- At compact or 200% text, field labels were cut off; they now wrap like the helper text (wrapped by issue #239).
