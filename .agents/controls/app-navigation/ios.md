# App navigation — iPhone notes

> **What:** the iPhone shell as built and planned. **Read when:** changing the iPhone tab shell or toolbar profile action (Lane A owns `App/Shell`, orchestrator owns `AppRoute`). Rules: [spec.md](spec.md); chrome: [design/apple/iphone.md](../../design/apple/iphone.md).

- `TabView` (Liquid Glass on iOS 26+, `.tabItem` fallback) with tabs from `FestivalTabPolicy` mirroring web `BottomNav`: Songs · Suggestions* · Leaderboards / Compete* · Statistics* · Settings (*with a profile), then a trailing **Search** tab (issue #92, [global-search](../global-search/ios.md)). The search tab counts toward the five-tab limit, so compact phone tabs drop Statistics (`FestivalTabPolicy.fittingSearchTab`; the drawer pushes it). Each section keeps its own `AppRoute` path; re-tap pops to root; Statistics resets on leave. `AppRoute` models all 24 web routes; unported pages show placeholders.
- `festivalRootChrome(session:)` on every tab root: leading hamburger drawer (`App/Shell/FestivalDrawer.swift`, mirrors the web Sidebar) and trailing profile avatar, via root-owned `openDrawer` / `openProfile` environment actions ([liquid-glass.md](../../design/apple/liquid-glass.md)).
- The profile avatar opens the selection sheet without changing the active section ([profile-selection/ios.md](../profile-selection/ios.md)). Debug: `FST_DEBUG_DRAWER`, `FST_DEBUG_SHEET=profile`, `FST_DEBUG_PROFILE`, `FST_DEBUG_ANONYMOUS`.
- A verified generation change currently **clears** retained `Song`-valued routes with a persistent visible explanation (they pin the older catalogue). TODO: carry song IDs and re-resolve against the new catalogue.
- **Selecting or deselecting a profile never navigates** (operator, 2026-09-28): no path is cleared and pages refresh in place. When the tab set changes, `FestivalTabPolicy.adapt` keeps the active tab if still visible; a slot swap (Leaderboards ↔ Compete, Rivals → Compete) carries the nested path, so selecting from Leaderboards › Player stays on that page; a vanished tab moves to its nearest visible predecessor (Statistics → Leaderboards, Suggestions → Songs).
- Open: drawer swipe / VoiceOver dismissal and tab re-tap are untested on device; band tab rules are unit-tested only ([PROGRESS.md](../../../PROGRESS.md)).

## Toolbar order rule (tab roots)

Profile avatar must be the **rightmost** item, with the bell just before it (web header parity).
Since issue #92 the trailing side is **two Liquid Glass groups**: page tools (page actions in page order, then Quick Links) and account (bell when a profile is selected, then avatar), split by one `ToolbarSpacer(.fixed)` in horizontal bars. Songs reads Sort · Filter · Quick Links | bell · avatar. HIG Toolbars (`apple-hig/references/hig/toolbars.md`): "Trailing: important always-available items"; "generally use no more than three groups". `RootChromeTrailingGroups` encodes the split (`RootChromeTrailingGroupsTests`); pages without tools show one account group. The Duo vertical bar adds no fixed spacer ([duo.md](../../design/apple/duo.md) "Toolbar rules").
SwiftUI lays out items from an outer `.toolbar` modifier (the root chrome) *before* the page's own items, so:

- A tab root **with** its own trailing actions ends its `.toolbar { … }` with `FestivalRootTrailingItems(session: session)` and applies `.festivalProvidesRootTrailingItems()`; the chrome then adds only the drawer button. Also add the section to `FestivalRootView.rootProvidesTrailingItems` (or pass `festivalRootChrome(…, providesTrailingItems: true)` where the page applies its own chrome, like Songs): the preference alone arrives an update late, so the first pass adds and removes a second bell/avatar.
- Use `placement: .festivalPageAction` (`.topBarTrailing` on iOS, `.primaryAction` elsewhere) for page actions on tab roots **and pushed pages**. iOS pins `.primaryAction` to the far trailing edge, after every `.topBarTrailing` item, whichever modifier added it.
- Tab roots **without** their own actions do nothing; `festivalRootChrome` adds the bell + avatar itself.

## Toolbar order rule (pushed pages)

Pushed pages never show the root chrome; `FestivalTabStack` applies `.pageTrailingItems()` (`PageTrailingItems`) to every destination, which adds the bell (selected profile) and the avatar from an *outer* modifier as the **only** `.primaryAction` items, after a `ToolbarSpacer(.fixed, placement: .primaryAction)` (iOS 26+): `[Back] … [page actions + Quick Links] | [bell · avatar]`. Before issue #85 the outer items used `.primaryAction` alongside the page's and the avatar sat mid-capsule; page actions now use `.festivalPageAction`. `PushedPageAvatarPlacementTests` fails if any page outside the Mac shell uses `.primaryAction` again. A pushed root screen that ends with `FestivalRootTrailingItems` sets `FestivalRootTrailingProvidedKey`, and the outer items step aside.

## Search tab, no dock

Issue #92 removed the header Search button and the tab-bar accessory dock (`FloatingPageControls`, `.festivalTabAccessory`). Global search is the trailing Search tab (`RootTab.search`, `RootTabTransition`); page tools are top-bar items; Songs has the pinned "Filter Songs" field. Narrow bars (< 390 pt) and accessibility text sizes fold Songs' Sort and Filter into one menu (`SongsToolbarFold`). The horizontal tab bar minimizes on scroll (`RootTabBarBehavior`). Details: [nav-accessories.md](../../design/apple/nav-accessories.md), [global-search](../global-search/ios.md).

## Drawer

Mirrors the web sidebar: Songs, Suggestions*, Statistics*, Rivals*, Leaderboards, Item Shop (*player; a visible tab switches, otherwise pushes), current destination highlighted (`DrawerMenu.isCurrent`); footer pinned at the bottom: the profile row (name → profile, Deselect) or Select Profile, then Settings. No Bands or Licenses rows (operator, 2026-09-28).

The player row uses `DrawerRow`'s metrics (`.body`, primary text, avatar in the 26 pt symbol column, 14 pt gap) and shows only the name: no "Selected Player" caption (issue #16, 2026-10-01). VoiceOver still reads "‹name›, Selected Player" (`DrawerMenu.selectedPlayerAccessibilityLabel`).

### Drawer corners

Issue #17 (2026-10-01): the panel follows the display corners with public API only. On iOS 26+ `DrawerCorners.panelShape` is `ConcentricRectangle(corners: .concentric(minimum: .fixed(26)), isUniform: false)` at the window root, so each corner is the display/window corner radius minus its distance from that corner. The system supplies the hardware shape per device, per Duo display and per rotation. Corners far from a display corner, such as the trailing corners or a Duo hinge-side corner, use the 26 pt minimum, which is the 14 pt row highlight plus the 12 pt content inset. That keeps the panel concentric with its own rows. The scrim cut-out (`DrawerPlacement.cutoutPadding`) has the same layout frame as the panel so both resolve the same radii. iOS 17–25 has no public API for the display radius and keeps a fixed 44 pt. Never read `_displayCornerRadius` (private API; App Review).

Measured (`FST_DEBUG_DRAWER_RADII=1` shows the panel frame and `GeometryProxy.concentricCornerRadii` on iOS 27): iPhone 18 Pro leading corners 54 pt (display ≈62 pt − 8 pt margin); iPhone 17e, the iPhone 13 display geometry, 39.3 pt (≈47.3 − 8). Display radii were taken from the simulator framebuffer masks: 18/17 Pro ≈62.6 pt, 13/17e ≈47.8 pt, Duo outer 8 hinge side / ≈58 outer side, Duo inner ≈53.

