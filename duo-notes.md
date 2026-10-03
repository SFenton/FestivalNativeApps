# iPhone Duo redesign notes
Journey: (1) Songs → Song Detail → Song Leaderboard + shell; (2) Leaderboards → Full Rankings → Player; (3) Statistics → Rivals → Rival Detail/Rivalry; (4) Item Shop, Suggestions, Compete, Settings, sheets/modals.
Stack: SwiftUI (TabView + NavigationStack/NavigationSplitView, system toolbars); package iOS 17; Xcode 27.1 / iOS 27.1 SDK (App Store archive: 27.0 SDK, Duo APIs compiled out). Evidence: folded portrait live in the iOS 27.1 sim (SFentonX); Device Hub poses still blocked (no Accessibility grant, re-checked 2026-10-02), so inner/book/landscape poses are hosted renders and unit tests only.
Stage: 5 (journeys 1–4; all decisions made)  Next: what's left for Duo overall — (a) real inner-display captures (flat, book, portrait half-open, fold/unfold continuity incl. D6 scroll restore) once the operator grants Accessibility for Device Hub scripting; (b) Split View on each side, PiP and keyboard overflow, Reduce Transparency, right-to-left, outer landscape/upside-down rotations; (c) Xcode App Resizability skill; (d) physical-device check (no camera features, so camera checks are N/A).

## Decisions (all operator, 2026-10-02 unless noted)
- Journey 1: D1 inner portrait = two populated columns, flat or half-open; D2 size classes (regular × regular) gate list/detail; D3 Search `.high` with Bell/Profile; D4 Song Detail Item Shop/Paths before Quick Links; D5 paged boards keep the tab bar, Next `.high`; D6 keep stack↔split swap, restore list scroll; D7 default bar for single-Close sheets; D8 no table pose; D9 system bar side. Standing (2026-09-28): dual-source shelved; modal Close in the sheet toolbar; rail keeps Bell + Profile.
- Journey 2: J1 instrument/band size and Rank By are separate titled rail items; J2 narrow rows drop songs played/total; J3 Duo split columns get their own width class.
- Observed exceptions: J1 target — system-defined control (rail 38×38, overflow row 42 pt); full-width `List` row frames under the rail are normal list behaviour (no `ScrollView` migration).
- Journey 4: S1 Item Shop even grid columns on the inner display (4 landscape, 2 portrait); G1 Suggestions two-column card grid at regular width; M1 What's New drops its Dismiss bar beside the vertical bar, keeps Close (iPhone unchanged).
- Journey 3: R1 Find Rival `.high` on the Rivals hub, global Search in `…`; R2 Rivals Rank By stays in content with a 44 pt target; R3 Statistics keeps 2 columns in inner portrait until an inner capture exists; R4 Find Rival keeps its inline field.

## Done / verified
- Journey 1: D1–D6 built; folded verified live; inner portrait via hosted renders; fold/unfold not run.
- Journey 2: J1 — sim folded: no top bar; rail Back, `…`, Next; `…` has "Lead" with its artwork and "Total Score". J2 (section-wide #38 fit, `rowInset: 32`) — sim folded: names full, songs kept in VoiceOver. J3 — unit `duoSplitDetailColumnIsCompact` (349/561/book 394 pt), hosted `duoSplitColumnsSeeCompactWidth` (`hig2/duo-j3-split-*.png`). Row frames: measured {0, 466}; a padding fix failed (UIKit sizes the collection view); reverted, now an observed exception.
- Journey 3: R1 — sim folded: rail Back, Find Rival, `…` (`hig2/j3-rivals-r1-folded`). R2 — sim folded: Rank By 98×44 pt. R4 — Find Rival sheet with keyboard keeps title and its rail Close. R3 no change. Inner Rivals split: hosted renders only (`list-detail-rivals-*`).
- Not run: Split View, PiP, keyboard overflow beyond Find Rival, Reduce Transparency, RTL, App Resizability, physical device, inner-display captures.

## Journey 4 (folded captured `hig2/j4-*`; inner via unit tests/hosted renders)
- Compete, Suggestions, Settings, Item Shop rails and the `FestivalModal` sheets: Ready (Filter overflows behind Search per D3) [HIG, T462].
- S1 built (`ShopGridPolicy`) — unit `shopGridUsesEvenColumnsOnTheDuoInnerDisplay` (835 pt → 4, book 4, 637 pt → 2; iPad/folded adaptive); sim folded unchanged (list layout, `hig2/j4-s1-shop-folded.png`).
- G1 built (`SuggestionsLayout`) — unit `suggestionsUseTwoColumnsAtRegularWidth`; sim folded unchanged (one column, `hig2/j4-g1-suggestions-folded.png`).
- M1 built — hosted `whatsNewSheetDropsDismissBesideTheVerticalBar` at 466×678 (`hig2/duo-m1-whats-new-folded.png`); sim folded (`FST_DEBUG_WHATS_NEW=force`): only the rail Close, no Dismiss bar (`hig2/j4-m1-whats-new-folded.png`); iPhone render test still sees Dismiss.
