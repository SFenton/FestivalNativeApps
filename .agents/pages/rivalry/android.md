# Rivalry — Android notes

> **What:** Android state of `/rivals/:rivalId/rivalry`. **Read when:** changing `RivalryScreen` in `android/`. Full Rivals notes: [../rivals/android.md](../rivals/android.md).

- Shares Rival Detail's view model type and cached read (same scope and live-fallback flag on the route), then shows one category (`mode`; unknown keys show the key as title and the empty state, as on the web).
- Native sort menu (`RivalrySort`: Default, Closest Gap, Your Biggest Leads, Their Biggest Leads, Title); the web has none and the service `sort` stays `closest`.
- Full head-to-head rows (You | rank and score gap pills | Them), 1–2 columns split at a separating hinge.
- No Quick Links ([quick-links](../../patterns/quick-links.md) R8, owner #545): one link per song only repeated the list. Top-app-bar actions are Sort, then View Profile. The web keeps its mobile per-song links (`rivalrySongQuickLinkId`); do not port them back. Guards: `QuickLinksPageSweepUiTest.rivalryHasNoQuickLinks*`, `RivalsUiTest.rivalryOffersNoQuickLinks`, `PlayerAccessibilityJourneyTest.rivalsHubDetailAndRivalry`.
- Sort menu items carry `Role.RadioButton` + `selected` inside a `selectableGroup` menu (`fst.rivalry.sort.menu`, popup tags exposed): the leading `RadioButton(onClick = null)` alone adds no semantics. Row labels speak the rank gap from `RivalHeadToHead.leaderPhrase` ("you lead by 1 rank"), not the signed, abbreviated pill text.

## Validation (issue #110, 2026-10-03)

Live public service, SFentonX vs. GingerNINZIN_JPN (Lead, Closest Battles, 5 songs), dark scheme, animator scale 0 unless noted. Material 3 skill guidance checked: window classes (Compact < 600, Medium 600–839, Expanded 840+), feed layout 1/2 columns with hinge avoidance, stock `DropdownMenu` (48 dp items, 280 dp max width), "TalkBack/semantics (Compose), focus order, touch targets (~48dp)".

| Configuration | Found | Result |
|---|---|---|
| FST_Phone portrait/landscape, fs 1.0/2.0 | Sort items had no selected state for TalkBack and no resource IDs in the popup; row label read "you lead by +1 ranks" | Items checkable/checked in the UI tree; label "you lead by 1 rank"; last row clears the floating toolbar |
| FST_Tablet landscape/portrait, fs 1.0/2.0 | — | Pass (two columns in landscape; one column in portrait and at 200%; Title sort reorders) |
| FST_Resizable phone/foldable/tablet/desktop, fs 2.0 | — | Pass (desktop keeps two columns at 200% because width ÷ fontScale ≥ 840 dp) |
| FST_Book_Fold folded/half/unfolded, fs 1.0/2.0 | — | Pass (half-open splits the two columns at the hinge; flat and 200% use one column) |
| FST_Passport_Fold folded/half/unfolded, portrait/landscape, fs 1.0/2.0 | — | Pass (folded landscape shows one row above the bar: shell compact-height layout) |
| FST_TriFold folded/partial/unfolded, fs 1.0/2.0 | — | Pass (folded 200% wraps names without spaces mid-word; nothing clipped) |
| Light theme | App stays dark | Documented dark-only deviation ([design](../../design/android.md)) |
| Reduced motion (scale 0) | Overflowing names ellipsize instead of scrolling; rows appear without the stagger | Pass; the full name stays in the row's TalkBack label |
| TalkBack (FST_Phone) | Page: Search, Notifications (10 unread), Profile, "vs. <rival>" heading, description, one stop per row (title, chart, both ranks, who leads by how many ranks, score difference), tabs, then Sort: <choice>, View <rival>'s Profile (no Quick Links stop since #545). Sort menu: "Selected. Default. Radio button. 1 of 5" … | Pass after the fix (before: no selected state). The floating toolbar reads after the tab bar, as on every page (shell order) |
| Connected ATF journeys | `RivalsDeviceJourneyTest#hubDetailAndRivalry`, `PlayerAccessibilityJourneyTest#rivalsHubDetailAndRivalry` | Pass on FST_Phone and FST_Book_Fold half-open; the journey now also checks Rivalry rows against the hinge and the sort menu's selected state |

Robolectric (`RivalsUiTest`) covers loaded, sort selection, unknown mode, known category without songs, failure + Retry and the absence of Quick Links; `RivalsCoreTest` covers `leaderPhrase`.

Deliberate deviations kept: native sort menu (the web keeps category order); no Quick Links (web: per-song links on mobile; owner #545); View Profile as an icon action; dark scheme only; one column at large text unless width ÷ fontScale ≥ 840 dp.
