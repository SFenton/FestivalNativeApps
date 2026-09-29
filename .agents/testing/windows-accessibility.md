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

## Pages

Tab = distinct stops in a 30-press walk (compact/medium/wide). Core pages (Songs, Song Detail, Leaderboards, Rivals, Settings, Search, the profile flyout and first run) also pass every Motion mode.

| Page | Axe C/M/W | Tab | Keys | HC ×4 | Text 225% |
|---|---|---|---|---|---|
| Songs (anonymous / selected) | ✅✅✅ | 9/10/10 | ✅ | ✅ | ✅ (C+M) |
| Song Detail + Paths dialog | ✅✅✅ | 16/17/17 | ✅ | ✅ | ✅ |
| Song Leaderboard | ✅✅✅ | 8/10/10 | ✅ | ✅ | ✅ |
| Player History | ✅✅✅ | 7/9/9 | — | ✅ | ✅ |
| Song Band Leaderboard | ✅✅✅ | 8/10/10 | — | ✅ | ✅ |
| Item Shop | ✅✅✅ | 6/9/9 | — | ✅ | ✅ |
| Suggestions | ✅✅✅ (AOT crash fixed) | 7/11/11 | ✅ | ✅ | ✅ |
| Leaderboards + Quick Links | ✅✅✅ | 20/21/21 | ✅ | ✅ | ✅ |
| Full Rankings / Rank By menu | ✅✅✅ | 8/11/11 | ✅ | ✅ | ✅ |
| Band Rankings | ✅✅✅ | 8/11/11 | — | ✅ | ✅ |
| Rivals / Compete | ✅✅✅ | 9/10/10 | — | ✅ | ✅ |
| All Rivals | ✅✅✅ | 6/9/9 | — | ✅ | ✅ |
| Rival Detail | ✅✅✅ | 12/14/14 | — | ✅ | ✅ |
| Rivalry | ✅✅✅ | 8/11/11 | — | ✅ | ✅ |
| Statistics / Player Profile | ✅✅✅ | 7–8/10–11 | ✅ | ✅ | ✅ (tiles scale) |
| Bands | ✅✅✅ | 10/13/13 | — | ✅ | ✅ |
| Player Bands | ⚠️✅✅ (issue 3) | 9/12/12 | — | ✅ | ✅ |
| Band Detail | ✅✅✅ | 10/14/14 | — | ✅ | ✅ |
| Search | ✅✅✅ | 9/10/10 | ✅ | ✅ | ✅ |
| Settings | ✅✅✅ | 30/30/30 | ✅ | ✅ | ✅ |
| Licenses | ✅✅✅ | 7/9/9 | — | ✅ | ✅ |
| Profile flyout | ✅✅✅ | 2 | ✅ | ✅ | ✅ |
| Notifications flyout | ✅✅✅ | 1 (list) | ✅ | ✅ | ✅ |
| Quick Links menu | ✅✅ (C/M) | 1 (menu) | ✅ | ✅ | ✅ |
| First-run dialog | ✅✅✅ | 4 | ✅ | ✅ | ✅ |

## Fixed in this pass

- Only the first item of every `ItemsRepeater` was reachable by keyboard (e.g. Settings chart toggles, ranking rows 2+, and every Leaderboards/Rivals card after the first).
- Duplicate sibling names across cards (Axe) were fixed with named `AccessibleGroup` cards. Unnamed view-profile buttons and the unnamed `MenuFlyout` presenters were given names.
- The app gained Narrator notifications for slow loads, result counts, errors and Quick Links jumps. It also gained Main and Search landmarks, Ctrl+digit section accelerators with access keys, and Alt+Left from text fields. The empty TitleBar tab stop was removed.
- Contrast themes now hide the artwork and use the theme's window colour (the `HighContrastChanged` subscription crashed the desktop app). At ≥150% text the title-bar caption is dropped, and stat tiles scale with the text size.
- `/statistics` deep links showed Coming Soon. The NativeAOT Suggestions page crashed on open because `Rows` was an `IReadOnlyList` bound to `ItemsSource`.

## Open issues

1. Title bar at ≥150% text: dropping the caption keeps search usable, but the title-bar layout is owned by shell/infra.
2. Contrast themes keep brand hues for the status rings (FC gold, scored green, no score red), the Shop borders and the percentile/FC chips. The chips get HC text backplates, and the meaning is in each row's UIA name. Mapping these to system colours is a design decision (TODO(orchestrator)).
3. Player Bands at compact: the row sitting exactly on the viewport's bottom edge reports a zero-height, not-offscreen UIA rectangle (Axe `BoundingRectangleSizeReasonable`). This is WinUI clipping, not app layout, and it doesn't occur at medium or wide.
4. The XAML choice menus (Rank By, Instrument, Band Size, Jump, Sort) share the implicit presenter name "Options". The invoking button names the choice, but per-menu names would read better.
5. Narrator has no scripted driver. Announcements are covered by `LoadAnnouncer` unit tests and the UIA tree; spoken output needs the operator script.
6. The system modes run on a lane host where other lanes' windows share the desktop. If a Tab walk leaves the window (focus theft), re-run it: Search compact did this once and passed on the re-run.
7. The same viewport-edge clipping (item 3) hits Leaderboards at the 1440×900 `wide` preset after the 2026-09-28 header change: 4 `NameText` findings on rank-3 rows at the bottom edge; 1440×880 and 1440×920 scan clean.
