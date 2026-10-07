# iPhone Duo redesign notes
Journey: (1) Songs → Song Detail → Song Leaderboard + shell; (2) Leaderboards → Full Rankings → Player; (3) Statistics → Rivals → Rival Detail/Rivalry; (4) Item Shop, Suggestions, Compete, Settings, sheets/modals; (5) sweep: Bands, Notifications, What's New, first run, Settings sub-pages, Paths.
Stack: SwiftUI (TabView + NavigationStack/NavigationSplitView, system toolbars); package iOS 17; Xcode 27.1 / iOS 27.1 SDK (App Store archive: 27.0 SDK, Duo APIs compiled out). Evidence: live iOS 27.1 sim, SFentonX, every pose scripted through Device Hub (`ios_sim.py pose`, drive `host:` steps); shots `~/FestivalShowcase/native-duo/{poses,final}/`.
Stage: 5 (journeys 1–5)  Next: operator/device only — the split redesign lane owns all list/detail layout; App Resizability skill in Xcode chat; hardware keyboard on a physical iPhone Duo; review the delegated decisions.

## Decisions (operator, 2026-10-02 unless noted)
- **Superseded by the operator's split redesign (2026-10-04):** D1 (inner-portrait two columns), J3 (split-column width class), P4 (narrow detail-column rows) and Split View; all list/detail and split layout moved to the redesign lane.
- Journey 1: ~~D1 inner portrait = two populated columns~~ (superseded); D2 size classes (regular × regular) gate list/detail; D3 Search `.high` with Bell/Profile; D4 Song Detail Item Shop/Paths before Quick Links; D5 paged boards keep the tab bar (~~Next `.high` in the rail~~ superseded by #345: the pager stays in content); D6 keep stack↔split swap, restore list scroll; D7 default bar for single-Close sheets; D8 no table pose; D9 system bar side. Standing (2026-09-28): dual-source shelved; modal Close in the sheet toolbar; rail keeps Bell + Profile.
- Journey 2: J1 instrument/band size and Rank By are separate titled rail items; J2 narrow rows drop songs played/total; ~~J3 Duo split columns get their own width class~~ (superseded). Journey 3: R1 Find Rival `.high`; R2 Rivals Rank By in content, 44 pt; R4 inline Find Rival field. Journey 4: S1 even Shop columns inside (4 landscape, 2 portrait); G1 Suggestions two columns at regular width; M1 What's New drops Dismiss beside the vertical bar. O1 (b): hinged devices allow every orientation.
- Observed exceptions: J1 target (system rail 38×38, overflow row 42 pt); full-width `List` row frames under the rail.

## Delegated decisions for later review (orchestrator default, operator delegated 2026-10-04)
- **P1** keep 2 Statistics columns in inner portrait (closes R3): ~300 pt tiles keep Rank History legible.
- **P2** accept Shop cards scrolling under the fold in book pose (centre gutter ~42 pt left of the fold): scrolling content need not avoid the fold [T463/T466]; not realigned to the division region.
- **P3** fix Songs in outer landscape by insetting the list in compact height: built as a measured top padding (`SongsDrawerOverlap`), not a search-placement change.
- ~~P4~~ superseded by the split redesign (2026-10-04); stopped unbuilt (note: the shared row is already one line since #292).
- **S5** Songs list-column title truncates to "S…" in inner portrait: handed to the split redesign lane (list-column chrome).
- **S6** Bands capped at the readable width (680 pt) at regular width, like Settings and Licenses.
- **S7** What's New opens as a centered sheet on the inner display (cover stays on iPhone, folded Duo, iPad) [T462/T466: inner sheets centered; don't stretch the iPhone page].
- **S8** rail overflow of Bell/Profile on inner-landscape pushed pages (Bands: Back + `…`) accepted as system compression with six tabs.
- **K1** hardware keyboard left pending (see checks); Split View superseded.
- **S9** first-run slides scroll with a 120 pt demo in compact height (outer landscape hid the title and text under Next). Verified: no overlap, but the ~128 pt page shows the demo first and the text after a scroll; option kept: text above the demo in compact height.
- **S10** Paths instrument name wraps only between words (folded "Lea/d").

## Done / verified (live unless noted)
- J1–J4 built and pose-checked (2026-10-02/04); inner portrait two columns and fold crash fixed (2026-10-04).
- P3 fixed (first row y 136 in both landscapes, scrolled and back; portrait unchanged). Paths instrument selector no longer splits "Lead" mid-word folded. Inner portrait page tools restored (the #92/#300 tab-bar accessory hid Item Shop/Paths/Sort/Filter there; now compact width only). Bands readable width (S6), What's New sheet inside (S7), first-run compact height (S9): see checks.

## Stage 5 pose checks (`~/FestivalShowcase/native-duo/{poses,final}/`)
| Check | Result | Evidence |
|---|---|---|
| Inner landscape flat/book, inner portrait, fold/unfold + D6, O1 outer landscape | pass (DUO4); P3 fixed | `poses/`, `final/p3-*` |
| Sweep: Song Detail, Paths, Notifications | pass all four poses; Paths "Lea/d" fixed folded; inner sheets centered, horizontal bars | `final/sw-*-paths`, `sw-*-notifications` |
| Sweep: Bands | pass four poses; S6 readable width (verified); S8 overflow | `final/sw-*-bands*` |
| Sweep: What's New | pass four poses (M1 holds); S7 sheet inside (verified) | `final/sw-*-whatsnew*` |
| Sweep: first run | folded, inner portrait/landscape pass; outer landscape hid title/text under Next → S9 fixed (verified) | `final/sw-*-firstrun*` |
| Sweep: Licenses, Privacy Policy | not run: the inner-display drive cannot scroll (XCUITest swipes miss the inner panel; `scrollTo` fails), stopped at wrap-up | — |
| Hardware keyboard | pending: Device Hub has no Connect Hardware Keyboard; its Toggle Software Keyboard reads disabled (AX state is stale until the menu opens in the active app; `host:control Capture Keyboard` first is the next try); phone shortcuts (⌘F/⌘K, ⌘1–9, ⌘[, ⌘R) exist in code, not verified | — |
| Split View (both sides) | superseded by the split redesign (2026-10-04); `systemDrag` driver step added for the Multitasking Dock drag, not run | — |
| PiP from another app | N/A: no PiP video app on the simulator; our app has no video | — |
| Earlier (2026-10-02): Reduce Transparency, Increase Contrast, RTL, AX5, software keyboard | pass/fixed | `checks/` |
