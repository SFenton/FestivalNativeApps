# App navigation — iPhone notes

> **What:** the iPhone shell as built and planned. **Read when:** changing the iPhone tab shell or toolbar profile action (Lane A owns `App/Shell`, orchestrator owns `AppRoute`). Rules: [spec.md](spec.md); chrome: [design/apple/iphone.md](../../design/apple/iphone.md).

- `TabView` (Liquid Glass on iOS 26+, `.tabItem` fallback) with tabs from `FestivalTabPolicy` mirroring web `BottomNav`: Songs · Suggestions* · Leaderboards / Compete* · Statistics* · Settings (*with a profile). Each section keeps its own `AppRoute` path; re-tap pops to root; Statistics resets on leave. `AppRoute` models all 24 web routes; unported pages show placeholders.
- `festivalRootChrome(session:)` on every tab root: leading hamburger drawer (`App/Shell/FestivalDrawer.swift`, mirrors the web Sidebar) and trailing profile avatar, via root-owned `openDrawer` / `openProfile` environment actions ([liquid-glass.md](../../design/apple/liquid-glass.md)).
- The profile avatar opens the selection sheet without changing the active section ([profile-selection/ios.md](../profile-selection/ios.md)). Debug: `FST_DEBUG_DRAWER`, `FST_DEBUG_SHEET=profile`, `FST_DEBUG_PROFILE`, `FST_DEBUG_ANONYMOUS`.
- A verified generation change currently **clears** retained `Song`-valued routes with a persistent visible explanation (they pin the older catalogue). TODO: carry song IDs and re-resolve against the new catalogue.
- **Selecting or deselecting a profile never navigates** (operator, 2026-09-28): no path is cleared and pages refresh in place. When the tab set changes, `FestivalTabPolicy.adapt` keeps the active tab if still visible; a slot swap (Leaderboards ↔ Compete, Rivals → Compete) carries the nested path, so selecting from Leaderboards › Player stays on that page; a vanished tab moves to its nearest visible predecessor (Statistics → Leaderboards, Suggestions → Songs).
- Open: drawer swipe / VoiceOver dismissal and tab re-tap are untested on device; band tab rules are unit-tested only ([PROGRESS.md](../../../PROGRESS.md)).

## Toolbar order rule (tab roots)

Profile avatar must be the **rightmost** item, with the bell beside it in one glass capsule (web header parity).
SwiftUI lays out items from an outer `.toolbar` modifier (the root chrome) *before* the page's own items, so:

- A tab root **with** its own trailing actions ends its `.toolbar { … }` with `FestivalRootTrailingItems(session: session)` and applies `.festivalProvidesRootTrailingItems()`; the chrome then adds only the drawer button. Also add the section to `FestivalRootView.rootProvidesTrailingItems` (or pass `festivalRootChrome(…, providesTrailingItems: true)` where the page applies its own chrome, like Songs): the preference alone arrives an update late, so the first pass adds and removes a second bell/avatar.
- Use `placement: .topBarTrailing` (iOS only — wrap in `#if os(iOS)`, `.primaryAction` on macOS) for page actions on tab roots. `.primaryAction` is pinned to the far trailing edge and would land after the avatar.
- Tab roots **without** their own actions do nothing; `festivalRootChrome` adds the bell + avatar itself.
- Pushed pages never show the chrome, so `.primaryAction` is fine there.

## Tab-bar bottom accessory

`FestivalRootView` applies `.festivalTabAccessoryHost()` to the iPhone `TabView` (`Common/TabAccessory/TabAccessory.swift`) on iOS 26.1+: global Search on every page, then the visible page's action registered with `.festivalTabAccessory(token:isEnabled:)`. The tab bar minimizes on scroll. Elsewhere `FestivalRootTrailingItems` and pushed pages show a toolbar Search button. Details: [nav-accessories.md](../../design/apple/nav-accessories.md), [global-search](../global-search/ios.md).
