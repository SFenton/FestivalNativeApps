# iPhone Duo redesign notes
Journey: (1) Songs → Song Detail → Song Leaderboard + shell; (2) Leaderboards → Full Rankings → Player; (3) Statistics → Rivals → Rival Detail/Rivalry; (4) Item Shop, Suggestions, Compete, Settings, sheets/modals (Stages 1–3).
Stack: SwiftUI (TabView + NavigationStack/NavigationSplitView, system toolbars); package iOS 17; Xcode 27.1 / iOS 27.1 SDK (App Store archive: 27.0 SDK, Duo APIs compiled out). Evidence: folded portrait live in the iOS 27.1 sim (SFentonX); Device Hub poses still blocked (no Accessibility grant, re-checked 2026-10-02), so inner/book/landscape poses are hosted renders and unit tests only.
Stage: 5 (journeys 1–3), 3 (journey 4)  Next: operator answers S1, G1, M1; grant Accessibility for Device Hub to capture inner poses.

## Decisions (all operator, 2026-10-02 unless noted)
- Journey 1: D1 inner portrait = two populated columns, flat or half-open; D2 size classes (regular × regular) gate list/detail; D3 Search `.high` with Bell/Profile; D4 Song Detail Item Shop/Paths before Quick Links; D5 paged boards keep the tab bar, Next `.high`; D6 keep stack↔split swap, restore list scroll; D7 default bar for single-Close sheets; D8 no table pose; D9 system bar side. Standing (2026-09-28): dual-source shelved; modal Close in the sheet toolbar; rail keeps Bell + Profile.
- Journey 2: J1 instrument/band size and Rank By are separate titled rail items; J2 narrow rows drop songs played/total; J3 Duo split columns get their own width class.
- Observed exceptions: J1 target — system-defined control (rail 38×38, overflow row 42 pt); full-width `List` row frames under the rail are normal list behaviour (no `ScrollView` migration).
- Journey 3: R1 Find Rival `.high` on the Rivals hub, global Search in `…`; R2 Rivals Rank By stays in content with a 44 pt target; R3 Statistics keeps 2 columns in inner portrait until an inner capture exists; R4 Find Rival keeps its inline field.

## Done / verified
- Journey 1: D1–D6 built; folded verified live; inner portrait via hosted renders; fold/unfold not run.
- Journey 2: J1 — sim folded: no top bar; rail Back, `…`, Next; `…` has "Lead" with its artwork and "Total Score". J2 (section-wide #38 fit, `rowInset: 32`) — sim folded: names full, songs kept in VoiceOver. J3 — unit `duoSplitDetailColumnIsCompact` (349/561/book 394 pt), hosted `duoSplitColumnsSeeCompactWidth` (`hig2/duo-j3-split-*.png`). Row frames: measured {0, 466}; a padding fix failed (UIKit sizes the collection view); reverted, now an observed exception.
- Journey 3: R1 — sim folded: rail Back, Find Rival, `…` (`hig2/j3-rivals-r1-folded`). R2 — sim folded: Rank By 98×44 pt. R4 — Find Rival sheet with keyboard keeps title and its rail Close. R3 no change. Inner Rivals split: hosted renders only (`list-detail-rivals-*`).
- Not run: Split View, PiP, keyboard overflow beyond Find Rival, Reduce Transparency, RTL, App Resizability, physical device, inner-display captures.

## Journey 4 findings (folded captured `hig2/j4-*`; inner code-only)
- Compete, Suggestions, Settings roots: Ready — rail Search, Bell, Profile, `…` (Quick Links, Filter); content inside the safe area [HIG, T462].
- Item Shop (pushed): Ready — rail Back, Search, `…` (Filter in `…` per D3); folded uses the list layout [HIG, T462].
- Filter sheets (Shop, Suggestions), Notifications, Profile, Global Search, Paths: Ready — `FestivalModal` with the system Close (D7) [HIG, T462].
- Settings inner display: Ready — readable width (680 pt) [HIG Layout].
- First-run guide: Ready — Next/Skip are content controls; Back/Close in the sheet bar [HIG].
- Item Shop grid inner display: Decision — adaptive 210 pt grid = 3 columns in landscape (~835 pt), so the middle column straddles a book-pose fold; 2 in portrait [HIG "even grid column counts", T463].
- Suggestions inner display: Decision — one full-width column of category cards (~835 pt landscape) [T466 "Don't ship a stretched iPhone app"].
- What's New sheet: Decision — custom bottom Dismiss bar duplicates the toolbar Close [T462 managed bars].
- Compliance fixes: none found beyond the decisions. N/A: camera, multiwindow, scene accessories, `ArrangementView`, table pose.
- Pending S1 Item Shop inner grid: keep adaptive (3 columns in landscape), or an even count (4 columns of ~200 pt in landscape, 2 in portrait). Recommended: even count.
- Pending G1 Suggestions inner display: two-column card grid at regular width (as Leaderboards/Profile), a readable-width single column (as Settings), or keep. Recommended: two-column grid.
- Pending M1 What's New: keep both Dismiss and Close, drop the Dismiss bar on the vertical bar only, or drop it everywhere. Recommended: drop it on the vertical bar only (iPhone keeps its design).
