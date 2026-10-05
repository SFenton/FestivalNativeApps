# iPhone Duo redesign notes
Journey: (1) Songs → Song Detail → Song Leaderboard + shell; (2) Leaderboards → Full Rankings → Player; (3) Statistics → Rivals → Rival Detail/Rivalry; (4) Item Shop, Suggestions, Compete, Settings, sheets/modals.
Stack: SwiftUI (TabView + NavigationStack/NavigationSplitView, system toolbars); package iOS 17; Xcode 27.1 / iOS 27.1 SDK (App Store archive: 27.0 SDK, Duo APIs compiled out). Evidence: live iOS 27.1 sim, SFentonX, every pose scripted through Device Hub since 2026-10-04 (`ios_sim.py pose`, drive `host:` steps).
Stage: 5 (journeys 1–4; pose checks run 2026-10-04)  Next: operator decides P1–P4 below; then Split View (drag from the Multitasking Dock, not yet scripted), Songs outer-landscape inset (P3), App Resizability skill by hand, physical device.

## Decisions (all operator, 2026-10-02 unless noted)
- Journey 1: D1 inner portrait = two populated columns, flat or half-open; D2 size classes (regular × regular) gate list/detail; D3 Search `.high` with Bell/Profile; D4 Song Detail Item Shop/Paths before Quick Links; D5 paged boards keep the tab bar, Next `.high`; D6 keep stack↔split swap, restore list scroll; D7 default bar for single-Close sheets; D8 no table pose; D9 system bar side. Standing (2026-09-28): dual-source shelved; modal Close in the sheet toolbar; rail keeps Bell + Profile.
- Journey 2: J1 instrument/band size and Rank By are separate titled rail items; J2 narrow rows drop songs played/total; J3 Duo split columns get their own width class.
- Observed exceptions: J1 target (system rail 38×38, overflow row 42 pt); full-width `List` row frames under the rail.
- Journey 4: S1 Item Shop even columns on the inner display (4 landscape, 2 portrait); G1 Suggestions two columns at regular width; M1 What's New drops Dismiss beside the vertical bar.
- Journey 3: R1 Find Rival `.high`; R2 Rivals Rank By in content, 44 pt; R3 Statistics 2 columns in inner portrait until an inner capture exists; R4 Find Rival inline field. O1 (b): hinged devices allow every orientation.

## Pending decisions (Lane DUO4, 2026-10-04)
- **P1 R3:** captured (`poses/j3-e/f-statistics-portrait*.png`): two ~300 pt tiles keep Rank History legible (both axes, legend, pager). Recommended: keep 2 columns (close R3).
- **P2 S1 in book pose:** the rail shifts the content centre left, so the 4-column gutter sits at 434 pt and the fold at 476 pt crosses column 3's cards (`j4-b`). T463/T466: scrolling content need not avoid the fold; HIG: keep important elements clear of the centre (Tension §4). Recommended: accept (scrolling cards); option: align the centre gutter to the division region (inactive included).
- **P3 Songs outer landscape:** first row and "#" header start under the pinned Filter field (rows at y 93 vs field 82–126, nav bar to 136), fresh launch and after rotation (`o1-fresh-landscape.png`, `o1-1/3`). `.navigationBarDrawer(.always)` + `List`; cause not isolated. Recommended: fix in the Songs lane (inset the list in compact height).

- **P4 Song Leaderboard in the detail column (~349 pt):** player names wrap mid-word ("SFen-tonX", "Pun-ished-Dakota") because the shared row lets names wrap (`f-f-unfolded-portrait-again.png`). Options: J2-style section-wide fit, one line with tail truncation in narrow columns, or accept. Recommended: one line + tail truncation at compact column width (iPhone unchanged).

## Done / verified (live unless noted)
- J1–J4 built; folded checks and Stage 5 non-pose checks done 2026-10-02 (see design notes).
- Fixed 2026-10-04: inner portrait showed only the detail column (system wrote `.detailOnly`) → split keeps `.all`, 320 pt list, no sidebar toggle; folding from inner portrait crashed in `UITabBarController _tabs_rebuildTabBarItemsAnimated:` → section-set change deferred one run-loop turn (`ShellPresentation.applying`); reproduced before, clean after.

## Stage 5 pose checks (Lane DUO4, 2026-10-04; `~/FestivalShowcase/native-duo/poses/`)
| Check | Result | Evidence |
|---|---|---|
| Inner flat landscape (951×669) | observed pass: D1 two columns (Songs, Full Rankings→Player, Rivals); S1 4 cols; G1 2 cols; Settings readable width; vertical bar trailing | `j1-b`, `j2-b`, `j3-h`, `j4-a/f/g` |
| Inner book landscape | observed pass: split equalised at the fold; Shop: P2 | `j1-c`, `j2-c`, `j4-b` |
| Inner portrait, flat + half-open (669×951) | observed, **fixed** (detail only → two columns); horizontal tab bar; S1 2 cols, G1 2 cols, R3 2 cols | `x-portrait-launch*`, `j1-d`, `j2-d/e`, `j3-d/e`, `j4-c/d/e` |
| Fold/unfold continuity + D6 | observed pass: unfold restores the list to the open song, selection kept; fold keeps the stack (Song Leaderboard, Full Rankings → Compete tab); auto-selected detail drops (by design). Fold from portrait **crashed → fixed** (re-run with Song Leaderboard open: no crash) | `j1-a/b`, `c-1..4`, `iso-*`, `j2-f`, `f-a..f` |
| O1 outer landscape | observed: both landscapes; bar on the camera edge (trailing / leading); page actions, Bell, Profile overflow into `…`; on paged boards the tab bar shrinks to the selected tab (system). Upside down: the system keeps the previous landscape (app allows all). Songs: P3 | `o1-*`, `j2-f` |
| Keyboard, inner landscape | observed pass: field above the keyboard; the keyboard covers the bar's lower tabs (system) | `j4-i`, `kb-a` |
| Hardware keyboard | not run: Device Hub has no Connect Hardware Keyboard; Capture Keyboard leaves the software keyboard up; Toggle Software Keyboard stays disabled | `kb-b/c` |
| Split View (both sides) | pending: entry is a drag from the Multitasking Dock (`j2-system-inner-portrait.tree.txt`); not scripted | — |
| PiP from another app | N/A this pass: no video app with PiP on the simulator; our app has no video | — |
| Earlier (2026-10-02): Reduce Transparency, Increase Contrast, RTL, AX5, software keyboard folded | observed pass/fixed | `native-duo/checks/` |
