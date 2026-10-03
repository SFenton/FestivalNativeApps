# Android accessibility results

> **What:** the Android accessibility phase: tools, what was checked on which device, findings, fixes and open gaps. **Read when:** changing semantics, touch targets, colours, text sizes or multi-column layouts on Android, or re-running the TalkBack/ATF/large-text passes. Tooling: [android.md](android.md#accessibility-tooling).

## Method

| Check | How | Devices |
|---|---|---|
| Accessibility Test Framework (touch targets ≥ 48 dp, labels, contrast, duplicate/redundant text) | 16 instrumented journeys in `androidTest/.../journeys/` (Songs, Sort/Filter, Song Detail, Paths, song board, Shop, Suggestions, Statistics, Leaderboards, Full Rankings, Rivals hub/detail/rivalry, Compete, Bands, Band Detail, song band board, Settings, Licenses, drawer, profile sheet, global search, notifications, first run, What's New); ATF on every interaction and screen | FST_Phone; FST_Book_Fold `--posture half` |
| TalkBack reading order and speech | `tools/android/talkback_walk.py`: real TalkBack, "next item" key chord (a real touchscreen swipe past text fields), utterances from TalkBack's own log | FST_Phone: 11 screens + 10 sheets/dialogs; FST_Passport_Fold unfolded, FST_TriFold unfolded, FST_Tablet: Songs, Song Detail, Leaderboards, Full Rankings, Settings, Rivals, Compete, Statistics, Suggestions, Item Shop, Band Detail; FST_Book_Fold half-open (Song Detail, Leaderboards, Settings) |
| Large text | 200% font scale plus the largest display size (`wm density` 1.3×: 546 on FST_Phone, 507 on FST_Book_Fold), 16 screens and sheets captured, fixed, recaptured | FST_Phone; FST_Book_Fold half-open |
| Unit/Robolectric | `LargeTextUiTest` (rows at 200%, wrapping, axis style), `StatGridColumnsTest`, `NavigationPolicyTest` (two panes at large text) | JVM |

Status (2026-09-29, FST-and-a11y2): ATF journeys 0 errors (FST-and-next). Walk reports (`<device>-<screen>.md`, `.log` with every spoken fragment) are in the showcase folder `and-a11y2/talkback/`; large-text captures (before `phone-*.png`, after `*-v2`/`-v3`/`-v4`) in `and-a11y2/bigtext/`.

## Findings and fixes

| Finding | Where | Fix |
|---|---|---|
| Leaderboard rows 45 dp tall (ATF touch target) | Song Detail previews, full song board (`ScoreRow`) | Minimum height 48 dp |
| Issue #72 check (iOS #15, nav buttons needing a forgiving tap area): not reproducible | Quick Links, Sort, Filter (floating toolbar), Search, bell, profile (top bar) | None needed: all are M3 `IconButton`s (40 dp layout, 48 dp touch bounds via `minimumInteractiveComponentSize`, no overlap). A Robolectric probe on a w411dp phone tapped each 20 dp off-centre in four directions; 24/24 activated |
| White on `#2D82E6` is 3.86:1 (ATF contrast) | Filled buttons | `BrandTokens.accentBlueFill` `#1A6FD8` (4.9:1) via `festivalFilledButtonColors()` |
| Row wrappers made two stops; summaries read then every child text again | Song boards, Score History, band rows, Item Shop, See All | One stop per row (`clearAndSetSemantics`/hidden inner texts) |
| Decorative pieces read as stops | Chart legend/axis dates, avatar initials (top bar, rail, profile sheet) | Hidden (`clearAndSetSemantics {}`) |
| Rail profile item read "Profile: name, Profile, FP" | Navigation rail | The label carries "Profile: <name>"; the avatar is silent |
| Songs tab read before the page and the other destinations after it | Rail on passport/tri-fold/tablet | The rail is one traversal group |
| Every phone Songs row began "Not selected" | Songs | Only the highlighted two-pane row carries selection state |
| Label read twice (description + visible text) | Quick Links items, Song Detail Item Shop button, Settings "Show" buttons, Compete "See All", Item Shop grid "Leaving Tomorrow", Band Detail tiles/members/history/song rows, Player Bands cards | Visible text hidden where a description replaces it; Compete uses the shared `SeeAllButton` |
| "…Open notification." appended to every notification and the time ran into the message | Notifications | Click label "Open notification" ("Double-tap to open notification"); "Title. Message. Time" |
| Rankings rows read "Rank 2nd, Name" but song boards "#2. Name" | Leaderboards, Full/Band Rankings, Compete | Both open "#2. Name." (selected: "Your rank, #1. Name.") |
| What's New row read title, button, then explanation | Settings | Title + explanation are one stop before the button |
| Drawer profile row read only the name | Drawer | "Profile: <name>"; Deselect reads "Deselect profile" |
| Side-by-side cards read row by row; half-open fold skipped the rest of a tall card | Two-column grids | `readingGroup()`; one column while TalkBack runs (`rememberSingleColumn`) |

### Large text (200% + largest display size)

| Finding | Fix |
|---|---|
| Player names collapsed to "…" in leaderboard rows; Full Rankings songs/rating overlapped | Rows stack at ≥ 1.3× (`isLargeText()`): rank + wrapping name, then score/pill (song boards) or rating/songs (rankings) |
| Titles, artists and names ended in an ellipsis (marquee under Remove animations) | `FestivalMarqueeText` wraps at ≥ 1.3×; plain one-line texts use `oneLineUnlessLarge()` (Shop, top songs, licenses, drawer, Intensity, band tiles) |
| Nav bar labels cut to "Song Sugg Com Stati Setti" | Bar and rail go icon-only at ≥ 1.3×; icons carry the names (rail Profile too since issue #101) |
| Unread badge grew over the bell and avatar (issue #101) | Badge text capped at 1.3×; the count stays in the bell's description |
| Permanent drawer labels broke mid-word (issue #101) | Drawer width scales with the font up to 360 dp; Deselect stacks under the name |
| Songs pinned search placeholder wrapped to an 80 dp field (issue #101) | One line with ellipsis; TalkBack reads the full label |
| Stat tiles broke words ("PLAYE D") | `StatGridColumns.count(width, fontScale)`: tiles widen with the scale; narrow grids may drop to one column (exception to the two-column phone minimum) |
| Rival names squeezed out beside "N shared songs"; tabs broke mid-word | Name wraps at ≥ 1.3× (the shared count was later removed, issue #67); Rivals tabs scroll |
| First-run Next/Done pushed off screen | Pager takes the remaining height; slides scroll |
| Profile sheet "Deselect" one letter per line | Buttons wrap (`FlowRow`) |
| Chart axis "100" clipped to "10" | Axis ticks keep their 100% size (`chartAxisTextStyle()`; decorative, values listed below each chart) |
| Half-open fold: 130 dp list pane, half-width cards wrapping a few letters per line | Two panes need the expanded width in text-scaled dp (`showsTwoPanes(…, fontScale)`); grids, hinge splits and Band Detail use one column (`rememberSingleColumn`), unless the window stays expanded in text-scaled dp |

Accepted: top app bar titles still ellipsize at 200% (Material small top app bar is one line; the page heading below repeats them); the floating pager covers part of a row until scrolled.

ATF warnings left as is: "Tap Vocals" is an instrument name, not an instruction; duplicate speakable text from identical fixture rows and repeated per-section controls, which TalkBack disambiguates by their heading.

## Reading order (TalkBack, verified)

Phone: top app bar (menu/Back, title, page actions, Search, Notifications, profile) → page content in visual order, headings marked → navigation bar tabs → floating toolbar page actions. Wide windows (passport, tri-fold, tablet): top app bar → rail (one group: menu, destinations, profile, Settings) → list pane → detail pane. Quick Links announce the current section. Sheets start at their title (or the drag handle) and end with Close/drag handle.

## Open

- Bottom sheets expose Material's unlabelled sheet area beside the drag handle (ATF accepts it; from `ModalBottomSheet`).
- TalkBack's linear navigation continues from a dialog into the window beneath it (seen after the first-run dialog's Next); Compose `Dialog` is a real dialog window, so this is TalkBack behaviour, not an app focus leak.
- Suggestions filter instrument chips read "Not selected … Check box" (Material `FilterChip` semantics).
