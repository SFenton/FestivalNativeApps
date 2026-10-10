# Quick Links

> **What:** the ordered per-page section navigator, including its entry point, jump ownership, icons, and accessible current state. **Read when:** adding section navigation to a page or changing a section list.

Status: **current**, 2026-10-05. Provenance: #6, #11, #12, #15, #286, #303, #313, #389, #392, #416, #545.

## Intent

Quick Links presents sections in page order and moves directly to the selected section without losing context. It uses the platform's native chooser while maintaining one shared ordering, landing, and current-section contract.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/hooks/ui/usePageQuickLinks.ts` (`usePageQuickLinks`, `DEFAULT_QUICK_LINK_SCROLL_OFFSET = 32`) | Orders anchors, tracks the active section, and owns a jump through arrival. |
| `FortniteFestivalWeb/src/components/page/PageQuickLinks.tsx` (`PageQuickLinksRail`, `PageQuickLinksModal`) | Shows the ordered, current-marked section chooser. |

## Rules

1. **R1. One controller per scroll container.** Pages declare stable web-compatible section IDs and hand their ordered list, frames, jump, and active state to the canonical controller; do not build a second menu, sheet, rail, or tracker.
2. **R2. Keep on-page order.** Parent sections precede nested sections and every presentation preserves that order. Apple menus must use `.menuOrder(.fixed)` (#6, #11). Every Quick Links page has a test comparing the rendered section order with the open chooser; on Android these are `QuickLinksPageOrderUiTest` and `QuickLinksPageSweepUiTest`, and Songs is covered for every bucketed sort (#158).
3. **R3. Hide inert navigation.** Show an entry point only with at least two current sections; remove unavailable sections rather than offering a no-op choice. **Owner-approved variant (#545, Rivalry):** a page that is one flat list of entries, such as Rivalry (a Rival Detail category's View All), has no sections, so it offers no Quick Links at all. A chooser with one entry per row only repeats the list. See the variant below.
4. **R4. Land and mark together.** Use the shared 32-unit landing/active line and jump ownership from [section-jump-landing](section-jump-landing.md); selected items remain current through arrival and near-end clamping.
5. **R5. Use native presentation.** **Approved variants:** Apple uses the tab-bar accessory sheet or toolbar menu (#92 follow-up); Android uses a compact bottom sheet and wider dropdown menu (operator 2026-09-28); Windows uses `QuickLinksMenuButton` or a wide pane. Material 3: "Material Android is Compose-first."
6. **R6. Preserve accessibility and hit targets.** The entry exposes the current section; the selected row has a current/selected state; rows have names and section jumps announce their destination. Apple touch controls meet HIG Accessibility's 44x44 pt default minimum; Android menu actions use 48 dp; Windows page tools, their menu items and the pane rows use 40 epx (menu items through the app-wide `FSTMenuItemMinHeight` style, [page-tools-and-nav-chrome](page-tools-and-nav-chrome.md) R10, #416). Tests: Apple hosted `QuickLinksAccessibilityTests` (in `apple-ci`: chooser and entry (#389); rotor order on Compete, Song Detail and Profile, nested rows, wrapping (#392)) and the iPhone journeys `QuickLinksAccessibilityJourneyTests` (Settings sheet audit, #389) and `QuickLinksOrderJourneyTests.testQuickLinksSheetIsAccessible*` (nested Profile sheet, hit size, AX5 audit, #392); Windows `a11y-quick-links-landing.json` (in `windows-ui`: names, order, 40 epx items and rows, landings, #416) and `HitTargetMarkupTests`; Android `@DeviceCi` ATF journey `ProfileQuickLinksAccessibilityJourneyTest` (in `android-device`: the Profile entry's name, role and 48 dp target; chooser rows in page order on screen and as TalkBack reads them, the current row's selected state; the partial sheet's lower rows reached through the drag handle's Expand action; the Top Songs jump landing and holding 32 dp below the bar at 1.0x and 2.0x; and the closed shell drawer out of the reading order, #501).
7. **R7. Normalize artwork icons.** Instrument artwork is pre-sized so its *visible* disc matches the adjacent system symbols, and scales with text; it never renders at its 144 pt intrinsic size (#303). The full-bleed artwork's dark outer ring disappears on dark surfaces, so an equal frame reads smaller than the symbols: Apple sizes per chooser (`QuickLinkLabel.Presentation`): 24 pt in the iPhone sheet list beside 20 pt symbols, 17 pt in iOS menus (iPad, Duo) beside 13.5 pt menu symbols, and 16 pt in macOS menus. It follows the row symbols' Dynamic Type curve, which holds from xxxLarge to AX3 while text keeps growing (#313). HIG Icons: "Adjust dimensions for visual weight so they look consistent, rather than forcing equal geometry."
8. **R8. Owner-approved: no Quick Links on Rivalry (owner, #545).** The Rivalry page (a Rival Detail category's View All, web `RivalryPage`) offers no Quick Links on the native apps: one link per song only repeats the list. Sections stay the unit of navigation, so the other Rivals pages keep theirs (Rivals hub and Leaderboard Rivals cards, Rival Detail categories, Compete groups). See [the variant](#owner-approved-variant-no-quick-links-on-rivalry-545).

### Owner-approved variant: no Quick Links on Rivalry (#545)

Owner (#545): "Some Rivals subpages have QL that have entries for each song. Those pages don't need ql". This departs from the web `RivalryPage`, which builds one mobile Quick Link per song (`rivalrySongQuickLinkId`), so it is scoped to the native Rivalry page; the web stays as it is. Do not restore per-song Rivalry Quick Links to match the web, and do not apply this variant to pages whose Quick Links jump to real sections.

- **Android (2026-10-09).** `RivalryScreen` (`ui/rivals/RivalPages.kt`) builds no `QuickLinksController`; its top-app-bar actions are Sort, then View Profile. The per-song builder (`RivalQuickLinks.rivalry`/`songId`) is gone. Guards: `QuickLinksPageSweepUiTest.rivalryHasNoQuickLinksOnPhone`/`rivalryHasNoQuickLinksInWideWindow`, `RivalsUiTest.rivalryOffersNoQuickLinks`, and the ATF journey `PlayerAccessibilityJourneyTest.rivalsHubDetailAndRivalry` (Rival Detail keeps the entry; Rivalry's TalkBack order has Sort, then View Profile, no Quick Links stop; 48 dp targets).
- **Windows.** `RivalryPage` never had Quick Links (the precedent).
- **Apple** adopts the variant in its own lane (shared `RivalryScreen` on iPhone, iPad, Mac and Duo).

### Owner-approved variant: no per-entry Quick Links on Rivalry (#545)

Owner (#545): "Some Rivals subpages have QL that have entries for each song. Those pages don't need ql". The web `pages/rivals/RivalryPage.tsx` builds one mobile Quick Link per song (`rivalrySongQuickLinkId`). The native Rivalry pages drop them: no entry point (toolbar menu, iPhone tab-bar accessory, Android action, Windows pane), no "Quick Links" rotor and no Go-menu section commands. Do not restore per-song links to match the web.

- **Scope.** Only Rivalry (`/rivals/:rivalId/rivalry?mode=`). Rivals pages whose Quick Links jump to real sections keep the base rules: the Rivals hub cards, Rival Detail's categories and the Leaderboards Rivals tab. All Rivals already had none. The web is unchanged.
- **Apple (2026-10-09).** `Features/Rivals/RivalryScreen.swift` has no `QuickLinksController`, `.quickLinks` container or `.quickLinkSection` rows, so iPhone, iPad, Mac and Duo show only View Profile. Guards: hosted `RivalsRenderTests.rivalryOffersViewProfileButNoQuickLinks` (rows read in order, no rotor or entry, the accessory reads View Profile then Notifications as 44 pt buttons) and `rivalDetailKeepsCategoryQuickLinks`; iPhone journey `QuickLinksOrderJourneyTests.testRivalryOffersNoQuickLinks`.
- **Windows.** `RivalryPage` never had Quick Links (the precedent).
- **Android.** Still offers per-song Quick Links (`RivalQuickLinks.rivalry`, `ui/rivals/RivalPages.kt`); it adopts the variant in its own lane.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Ordered model and tracker | `apple/Sources/FestivalCore/QuickLinks.swift` `QuickLinks` | `android/app/src/main/java/com/festivalscoretracker/android/core/quicklinks/QuickLinks.kt` `QuickLinks` | `windows/Festival.Core/Domain/QuickLinks.cs` `QuickLinks` |
| Page controller and jump | `apple/Sources/FestivalUI/Common/QuickLinks/QuickLinksController.swift` `QuickLinksController` | `android/app/src/main/java/com/festivalscoretracker/android/ui/quicklinks/QuickLinksUi.kt` `QuickLinksController` | `windows/Festival.App/Controls/QuickLinksHost.cs` `QuickLinksHost` |
| Native chooser | `apple/Sources/FestivalUI/Common/QuickLinks/QuickLinksToolbar.swift` `QuickLinksMenu` | `android/app/src/main/java/com/festivalscoretracker/android/ui/quicklinks/QuickLinksUi.kt` `QuickLinksAction` | `windows/Festival.App/Controls/QuickLinksMenuButton.cs` `QuickLinksMenuButton` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| None confirmed | — | — |

## Guards (`tools/pattern_guard.py`)

- `quick-links/apple-menu`
- `quick-links/android-controller`
- `quick-links/windows-menu-button`
