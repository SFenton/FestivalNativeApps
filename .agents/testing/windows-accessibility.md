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
| Item Shop | ✅✅✅ | 6/9/9 | — | ✅ | ✅ |
| Suggestions | ✅✅✅ (AOT crash fixed) | 7/11/11 | ✅ | ✅ | ✅ |
| Leaderboards + Quick Links | ✅✅✅ | 20/21/21 | ✅ | ✅ | ✅ |
| Full Rankings / Rank By menu | ✅✅✅ | 8/11/11 | ✅ | ✅ | ✅ |
| Band Rankings (+ Band Detail column ≥1100) | ✅✅✅ (+AOT) | 8/11/17 | — | ✅ | ✅ |
| Rivals / Compete | ✅✅✅ | 9/10/10 | — | ✅ | ✅ |
| All Rivals (+ Rival Detail column ≥1100) | ✅✅✅ (+AOT) | 6/9/15 | — | ✅ | ✅ |
| Rival Detail | ✅✅✅ (+snap/max, #202) | 12/14/14 | ✅ | ✅ | ✅ (200% C/M/W; display 100%/150%, #202) |
| Rivalry | ✅✅✅ | 8/11/11 | — | ✅ | ✅ |
| Statistics / Player Profile | ✅✅✅ | 7–8/10–11 | ✅ | ✅ | ✅ (tiles scale) |
| Bands | ✅✅✅ | 10/13/13 | — | ✅ | ✅ |
| Player Bands | ✅✅✅ | 8/11/11 | — | ✅ | ✅ |
| Band Detail | ✅✅✅ | 10/14/14 | — | ✅ | ✅ |
| Search | ✅✅✅ | 9/10/10 | ✅ | ✅ | ✅ |
| Settings | ✅✅✅ | 30/30/30 | ✅ | ✅ | ✅ |
| Licenses | ✅✅✅ | 7/9/9 | — | ✅ | ✅ |
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

## Song Band Leaderboard validation (issue #196, 2026-10-03)

Evidence: `a11y_matrix.py --scan` for `song-band-leaderboard` at compact/medium/wide, then at medium under all four contrast themes, text 200% (C+M), text 225%, no animations and no transparency: 0 Axe errors in all 12 runs. The live public service (temp wrapper without `--base-url`) gave 0 Axe errors under Desert, Night sky and text 200%. Both band journeys pass.

Fixed:
- The rows were templated `ListViewItem`s without a name or ID, and an inner named `Group` repeated the row. Every rank, name, score, pill, star and icon part was a separate Narrator scan stop, and `InstrumentIcon`'s inner `Image` leaked as an unnamed image. Now each row is one stop, with a name built in `ContainerContentChanging` that includes each member's instruments and score.
- The accuracy pill kept its navy fill under system text in Desert.
- `.empty` and `.error` sat on a panel and a UserControl, which have no UIA peer.

Constraint: the lane host's console was locked for this pass, so SendInput Tab walks and keyboard journeys could not run. Keyboard order was checked through UIA focusability, and actions were driven through UIA patterns.

## Open issues

1. Title bar at ≥150% text: dropping the caption keeps search usable, but the title-bar layout is owned by shell/infra.
2. (Resolved 2026-09-29, win-unify.) Contrast themes now map status chips, emphasis text, pills, Shop borders/badges and destructive buttons to system colours ([design/windows.md](../design/windows.md) contrast roles; Axe 0 errors under Desert and Night sky on Songs, Song Detail, song leaderboard, Leaderboards, Suggestions, Player, Shop and the Songs Filter). Charts keep their brand data hues; since issue #195 the Song Detail score chart draws axes and bar outlines in WindowText and the selected bar in Highlight.
3. (Resolved 2026-09-29, no repro.) Player Bands at compact: the row sitting exactly on the viewport's bottom edge reports a zero-height, not-offscreen UIA rectangle (Axe `BoundingRectangleSizeReasonable`). This is WinUI clipping, not app layout, and it doesn't occur at medium or wide.
4. The XAML choice menus (Rank By, Instrument, Band Size, Jump, Sort) share the implicit presenter name "Options". The invoking button names the choice, but per-menu names would read better.
5. Narrator has no scripted driver. Announcements are covered by `LoadAnnouncer` unit tests and the UIA tree; spoken output needs the operator script.
6. The system modes run on a lane host where other lanes' windows share the desktop. If a Tab walk leaves the window (focus theft), re-run it: Search compact did this once and passed on the re-run.
7. (Resolved 2026-09-29, no repro.) The same viewport-edge clipping (item 3) hits Leaderboards at the 1440×900 `wide` preset after the 2026-09-28 header change: 4 `NameText` findings on rank-3 rows at the bottom edge; 1440×880 and 1440×920 scan clean.
8. Quick Links menu at compact: Axe `BoundingRectangleCompletelyObscuresContainer` on WinUI's windowed popup internals (an `InputSiteWindowClass` exactly the size of its `PopupHost` bridge, no app element involved); medium scans clean.
9. (Resolved 2026-09-29.) Red Reset buttons use ButtonFace/ButtonText under contrast themes (`FSTDanger*`).
