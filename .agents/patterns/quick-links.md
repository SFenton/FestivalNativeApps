# Quick Links

> **What:** the ordered per-page section navigator, including its entry point, jump ownership, icons, and accessible current state. **Read when:** adding section navigation to a page or changing a section list.

Status: **current**, 2026-10-05. Provenance: #6, #11, #12, #15, #286, #303, #313, #389, #392, #416.

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
3. **R3. Hide inert navigation.** Show an entry point only with at least two current sections; remove unavailable sections rather than offering a no-op choice.
4. **R4. Land and mark together.** Use the shared 32-unit landing/active line and jump ownership from [section-jump-landing](section-jump-landing.md); selected items remain current through arrival and near-end clamping.
5. **R5. Use native presentation.** **Approved variants:** Apple uses the tab-bar accessory sheet or toolbar menu (#92 follow-up); Android uses a compact bottom sheet and wider dropdown menu (operator 2026-09-28); Windows uses `QuickLinksMenuButton` or a wide pane. Material 3: "Material Android is Compose-first."
6. **R6. Preserve accessibility and hit targets.** The entry exposes the current section; the selected row has a current/selected state; rows have names and section jumps announce their destination. Apple touch controls meet HIG Accessibility's 44x44 pt default minimum; Android menu actions use 48 dp; Windows page tools, their menu items and the pane rows use 40 epx (menu items through the app-wide `FSTMenuItemMinHeight` style, [page-tools-and-nav-chrome](page-tools-and-nav-chrome.md) R10, #416). Tests: Apple hosted `QuickLinksAccessibilityTests` (in `apple-ci`: chooser and entry (#389); rotor order on Compete, Song Detail and Profile, nested rows, wrapping (#392)) and the iPhone journeys `QuickLinksAccessibilityJourneyTests` (Settings sheet audit, #389) and `QuickLinksOrderJourneyTests.testQuickLinksSheetIsAccessible*` (nested Profile sheet, hit size, AX5 audit, #392); Windows `a11y-quick-links-landing.json` (in `windows-ui`: names, order, 40 epx items and rows, landings, #416) and `HitTargetMarkupTests`.
7. **R7. Normalize artwork icons.** Instrument artwork is pre-sized so its *visible* disc matches the adjacent system symbols, and scales with text; it never renders at its 144 pt intrinsic size (#303). The full-bleed artwork's dark outer ring disappears on dark surfaces, so an equal frame reads smaller than the symbols: Apple sizes per chooser (`QuickLinkLabel.Presentation`): 24 pt in the iPhone sheet list beside 20 pt symbols, 17 pt in iOS menus (iPad, Duo) beside 13.5 pt menu symbols, and 16 pt in macOS menus. It follows the row symbols' Dynamic Type curve, which holds from xxxLarge to AX3 while text keeps growing (#313). HIG Icons: "Adjust dimensions for visual weight so they look consistent, rather than forcing equal geometry."

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
