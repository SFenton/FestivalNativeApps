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
| Player History | ✅✅✅ | 7/9/9 | — | ✅ | ✅ |
| Song Band Leaderboard | ✅✅✅ (+live, #196) | 8/10/10 | UIA only (#196) | ✅ | ✅ (+200% C+M) |
| Item Shop | ✅✅✅ | 6/10/10 | — | ✅ | ✅ |
| Suggestions | ✅✅✅ (AOT crash fixed) | 7/11/11 | ✅ | ✅ | ✅ |
| Leaderboards + Quick Links | ✅✅✅ (+live, #207) | 20/21/21 | ✅ | ✅ | ✅ (C+M; rows stack, #207) |
| Full Rankings / Rank By menu | ✅✅✅ (+live, #208) | 9–13/12–15/12–15 | ✅ (#208) | ✅ | ✅ (+200% C/M/W) |
| Band Rankings (+ Band Detail column ≥1100) | ✅✅✅ (+AOT) | 8/11/17 | — | ✅ | ✅ |
| Rivals / Compete | ✅✅✅ (#213: +200%, display 100%/150%) | 9/10/10 | ✅ `kb-compete-order` | ✅ | ✅ |
| All Rivals (+ Rival Detail column ≥1100) | ✅✅✅ (+AOT) | 6/9/15 | — | ✅ | ✅ |
| Rival Detail | ✅✅✅ (+snap/max, #202) | 12/14/14 | ✅ | ✅ | ✅ (200% C/M/W; display 100%/150%, #202) |
| Rivalry | ✅✅✅ | 8/11/11 | — | ✅ | ✅ |
| Statistics / Player Profile | ✅✅✅ | 7–8/10–11 | ✅ | ✅ | ✅ (tiles scale) |
| Bands | ✅✅✅ | 10/13/13 | — | ✅ | ✅ |
| Player Bands | ✅✅✅ | 8/11/11 | — | ✅ | ✅ |
| Band Detail | ✅✅✅ (+live, #212) | 12/15/15 | ✅ | ✅ | ✅ (+200% C+M) |
| Search | ✅✅✅ | 9/10/10 | ✅ | ✅ | ✅ |
| Settings | ✅✅✅ | 30/30/30 | ✅ | ✅ | ✅ |
| Licenses | ✅✅✅ (+dialog, #215) | 21/23/23 (dialog 3) | ✅ (#215 journey) | ✅ | ✅ (+200% C/M/W, display 100%/150%, #215) |
| Profile flyout | ✅✅✅ | 2 | ✅ | ✅ | ✅ |
| Notifications flyout | ✅✅✅ | 1 (list) | ✅ | ✅ | ✅ |
| Quick Links menu | ⚠️✅ (issue 8) | 1 (menu) | ✅ | ✅ | ✅ |
| First-run dialog | ✅✅✅ | 4 | ✅ | ✅ | ✅ |

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

## Item Shop validation (issue #224, 2026-10-04)

Scope: the Shop Offers control only. Results per configuration are in [shop-offers/windows.md](../controls/shop-offers/windows.md#validation-issue-224-2026-10-04). `a11y_matrix.py --scan --tabs 30 --only shop` gave 0 Axe errors at compact, medium and wide (6/10/10 Tab stops: compact has no List/Grid toggle). At medium it also gave 0 Axe errors under Desert, Night sky, light and dark system theme, text 200%, and display 100% and 150%. No run had focus leaving the window or repeated stops. The live public service (anonymous) was checked at compact, medium, wide, maximized and snap-left, and under Desert, text 200% and display 150%. Fixed: under a contrast theme, WinUI's automatic adjustment had repainted the badge text as WindowText on a backplate inside the Highlight pill (`HighContrastAdjustment=None` while it is on, as `LeaderboardEntryRow` does). The active ProgressRing reads "Busy Loading Item Shop" (WinUI prefix), so tests use `fst.shop.loading`.

## Song Band Leaderboard validation (issue #196, 2026-10-03)

Evidence: `a11y_matrix.py --scan` for `song-band-leaderboard` at compact/medium/wide, then at medium under all four contrast themes, text 200% (C+M), text 225%, no animations and no transparency: 0 Axe errors in all 12 runs. The live public service (temp wrapper without `--base-url`) gave 0 Axe errors under Desert, Night sky and text 200%. Both band journeys pass.

Fixed:
- The rows were templated `ListViewItem`s without a name or ID, and an inner named `Group` repeated the row. Every rank, name, score, pill, star and icon part was a separate Narrator scan stop, and `InstrumentIcon`'s inner `Image` leaked as an unnamed image. Now each row is one stop, with a name built in `ContainerContentChanging` that includes each member's instruments and score.
- The accuracy pill kept its navy fill under system text in Desert.
- `.empty` and `.error` sat on a panel and a UserControl, which have no UIA peer.

Constraint: the lane host's console was locked for this pass, so SendInput Tab walks and keyboard journeys could not run. Keyboard order was checked through UIA focusability, and actions were driven through UIA patterns.

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

Seen, out of scope: with live data (three Shop buckets) at the medium preset, the Songs **Jump** zoomed-out index truncates "Leaving Tomorrow" and "Not In Shop" to "Leavi…" and "Not I…". The Songs Jump index owns that layout, not Sort.

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

## Open issues

1. Title bar at ≥150% text: dropping the caption keeps search usable, but the title-bar layout is owned by shell/infra.
2. (Resolved 2026-09-29, win-unify.) Contrast themes now map status chips, emphasis text, pills, Shop borders/badges and destructive buttons to system colours ([design/windows.md](../design/windows.md) contrast roles; Axe 0 errors under Desert and Night sky on Songs, Song Detail, song leaderboard, Leaderboards, Suggestions, Player, Shop and the Songs Filter). Charts keep their brand data hues; since issue #195 the Song Detail score chart draws axes and bar outlines in WindowText and the selected bar in Highlight, and since issue #212 the rank-history chart (Band Detail, Player Profile) does the same for gridlines, axes and bar outlines.
3. (Resolved 2026-09-29, no repro.) Player Bands at compact: the row sitting exactly on the viewport's bottom edge reports a zero-height, not-offscreen UIA rectangle (Axe `BoundingRectangleSizeReasonable`). This is WinUI clipping, not app layout, and it doesn't occur at medium or wide.
4. The XAML choice menus (Rank By, Instrument, Band Size, Jump, Sort) share the implicit presenter name "Options". The invoking button names the choice, but per-menu names would read better.
5. Narrator has no scripted driver. Announcements are covered by `LoadAnnouncer` unit tests and the UIA tree; spoken output needs the operator script.
6. The system modes run on a lane host where other lanes' windows share the desktop. If a Tab walk leaves the window (focus theft), re-run it: Search compact did this once and passed on the re-run.
7. (Resolved 2026-09-29, no repro.) The same viewport-edge clipping (item 3) hits Leaderboards at the 1440×900 `wide` preset after the 2026-09-28 header change: 4 `NameText` findings on rank-3 rows at the bottom edge; 1440×880 and 1440×920 scan clean. Issue #219: the Songs Filter flyout at medium with 150% display scale, after `scrollinto` Percentile, leaves the Karaoke score expander as a sliver at the ScrollViewer's top edge; its header `TextBlock` reports a zero-height rectangle (2 findings). Every other size, mode and scroll position scans clean.
8. Flyout menus (Quick Links at compact and medium, the Rank By menu at medium): Axe `BoundingRectangleCompletelyObscuresContainer` on WinUI's windowed popup internals (an `InputSiteWindowClass` exactly the size of its `PopupHost` bridge, no app element involved); other sizes scan clean (issue #207). Issue #208 saw the same finding on Full Rankings while the Instrument/Rank By menu or the pager button tooltip (after Last → Previous) was open; issue #219 on the Songs Filter's instrument selector popup. Issue #223 saw it in the wide Paths dialog when keyboard focus on an Instrument Selector button opens its tooltip. Issue #226 saw it on player pages opened from the profile flyout (View Profile, a result at text 200%): the flyout's popup host lingers after it closes.
9. (Resolved 2026-09-29.) Red Reset buttons use ButtonFace/ButtonText under contrast themes (`FSTDanger*`).

## Settings validation (issue #214, 2026-10-03)

Evidence: `a11y_matrix.py --scan --tabs 60 --pages journeys/settings-states.json` (expanded states, a shot per section) at compact and wide under normal, light and dark theme, Desert, Night sky, text 200%, display 100% and 150%, plus snap-right and maximized: 0 Axe errors, 53/55 distinct Tab stops, none outside the window or repeated. `settings-keyboard` (Space/Enter/Esc with focus kept) and the `journeys/settings.py` journeys pass. Fixed: Settings ignored contrast themes in its reorder lists, First Run chips, link-row hover and progress bar, and kept stale brushes when a contrast theme was switched on while the page was open. Per configuration: [settings/windows.md](../pages/settings/windows.md#validation-issue-214-2026-10-03).
