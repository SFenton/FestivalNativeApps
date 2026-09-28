# Profile selection — iPhone notes

> **What:** the SwiftUI selection sheet and session as built, decisions and open gaps. **Read when:** changing `Features/Profile` or `FestivalSession` identity (Lane P). Spec: [spec.md](spec.md). Player-profile page: [player-profile/ios.md](../../pages/player-profile/ios.md).

## Cold-start persistence bug — fixed

**Symptom (operator, 2026-09-27):** the selected profile did not reliably stay selected across closing/reopening the app or a cold start.

**Root cause:** `FestivalSession.refreshSelectedPlayer()` — the call every relaunch makes to reload an already-persisted identity's scores — compared `payload.publicationId` against `self.publicationId`:

```swift
guard payload.publicationId == publicationId else {
    throw FestivalAPIError.invalidPublication
}
```

but `self.publicationId` had already been advanced, moments earlier in the same call, to `payload.observedPublicationId` by `profile(accountId:)`'s own `observe(publicationId:)` call. So the guard was really comparing the response's own two fields to each other: `payload.publicationId == payload.observedPublicationId`. `payload.publicationId` is the header-verified `X-FST-Publication-Id` (nil when the response is headerless — a real, documented state per [spec.md](spec.md), e.g. before edge pinning is enabled for that read), while `observedPublicationId` is always a concrete generation number. A headerless-but-otherwise-current response therefore **always** failed this tautology, permanently downgrading a valid restored selection to `.failed` on the very next launch, even though nothing was actually stale — the identity itself (`selectedPlayer`) survived (`FestivalSession.init` already decodes and validates it from `UserDefaults` correctly), but its scores could never successfully reload, so the profile looked lost.

**Fix:** removed the redundant check. `observe(publicationId:)` (already called by `profile(accountId:)`) still rejects a regressed generation and resets state on an actual rollover, and `hasCurrentPlayerScores(forCatalogue:)` independently gates whether these scores may be shown against a specific Songs generation (via `SongRelatedPublicationPolicy`, which only ever compares generation counters, never the nullable header-verified field) — so dropping the tautological guard does not weaken either safeguard. `selectPlayer()` (the initial, explicit selection) is untouched and still requires a header-verified `payload.publicationId` match before promoting a viewed player, per spec.

**Regression coverage:** `ProfileSelectionSessionTests.relaunchReloadSurvivesAHeaderlessButOtherwiseCurrentProfileRead` selects a player, constructs a second `FestivalSession` from the same storage (simulating a cold restart), forces the next `/api/player/...` fixture response to omit its publication header while `/api/publication` stays pinned, and asserts `refreshSelectedPlayer()` still reaches `.available` with the correct scores rather than `.failed`. All 9 existing `ProfileSelectionSessionTests` cases (switch/deselect, 403, 202, generation rollover, late-read races) still pass unchanged.

## Debug profile is in-memory only — fixed

**Symptom (operator, 2026-09-27):** lanes share one simulator; `FST_DEBUG_PROFILE=<accountId>:<displayName>` was clobbering whatever real profile another lane's own launch had actually persisted.

**Root cause:** `DebugLaunchRoute.applyProfile(to:)` wrote the debug identity straight into `UserDefaults.standard` (`defaults.set(data, forKey: SelectedPlayerIdentity.storageKey)`) before `FestivalSession` was constructed, so `FestivalSession.init` loaded it exactly like a real persisted selection — a launch meant only for screenshotting overwrote the one shared `UserDefaults.standard` domain every other lane's debug (and real) launches also read from.

**Fix:** `FestivalSession.init` gained an additive `debugSelectedPlayer: SelectedPlayerIdentity?` parameter that seeds `selectedPlayer`/`playerLoadState` directly, entirely bypassing `selectionStorage`. `DebugLaunchRoute.applyProfile(to:)` was replaced with `debugSelectedPlayer()`, which only *builds* a validated `SelectedPlayerIdentity` (via `PlayerSearchResult` + `SelectedPlayerIdentity.init(searchResult:)`) and never touches any `UserDefaults` domain. `FestivalRootView.init()` passes the built identity straight into the new session parameter instead of writing it to `.standard` first. `FST_UI_TEST_CLEAR_PROFILE=1`'s existing real-storage cleanup is untouched — it still runs, but is now irrelevant to a debug-profile launch since nothing debug-related is stored anymore. `FST_DEBUG_ANONYMOUS=1` is unaffected (still only nils out `selectionStorage`, independent of this).

**Regression coverage:** `ShellNavigationPolicyTests.debugProfileSelectsInMemoryWithoutTouchingUserDefaults` builds the debug identity, asserts a fresh `UserDefaults` suite never receives it, constructs a `FestivalSession(debugSelectedPlayer:)` from that same suite and confirms `session.selectedPlayer` is set while the suite is still untouched afterward. Verified live: `FST_DEBUG_PROFILE=e408c4613c8f4da5907090b390bda80c:Creeper --tab statistics` renders the selected "This Is Me" state correctly with no write side effect.

## Player profile page

`AppRoute.player`/`.playerBands` are implemented (see [player-profile/ios.md](../../pages/player-profile/ios.md)); the sheet's search results and its "View Profile" action now dismiss the sheet and push the real route onto the presenting tab (see "Sheet redesign" below — this supersedes that section's earlier in-sheet-push decision).

## Sheet redesign (native, dark glass)

Per `.agents/design/apple/liquid-glass.md`'s "sections inside sheets" rule (native `Form` + `FestivalSectionHeader` + tinted `listRowBackground`, never a nested glass card):

- White Title Case section headers: "Selected Profile", "Find a Profile" (was grey system uppercase).
- Segmented Players/Bands scope kept as a real `Picker(.segmented)` (an `NSSegmentedControl` under the existing macOS `NSHostingView` render tests) rather than switched to `.searchScopes`, to keep those tests introspecting a real control.
- Search field: a styled pill (leading magnifying glass, rounded capsule, trailing clear button) whose placeholder switches "Find Player" / "Find Band" with the scope. **Not** a literal `.searchable` — that field is system-placed chrome the existing off-window `NSHostingView` snapshot tests (`ProfileSelectionSheetRenderTests.swift`) cannot reliably introspect; the styled `TextField` matches `.searchable`'s shape while staying a directly hosted, testable control. Documented in `ProfileSelectionSheet`'s own doc comment for whoever revisits this.
- Bands scope now keeps the search field visible (disabled) with an honest gating explanation below it, instead of hiding the field outright — matches the requirement that the prompt itself says "Find Band". Updated `profileBandScopeKeepsUnsafeSearchBlocked` to assert `isEnabled` toggles rather than the field disappearing.
- The "Enter at least two characters…" hint now centers in the remaining sheet space (`containerRelativeFrame(.vertical) { length, _ in max(length * 0.55, 180) }`) instead of sitting as a small inline row.
- **Navigation choice — dismiss-then-push (updated 2026-09-28):** a result row and the selected-profile summary's "View Profile" now call a shared `openPlayer(accountId:displayName:)` that calls `dismiss()` then a passed-in `openRoute(route)` closure. The sheet no longer owns any navigation state: `@State private var path`/`.navigationDestination(for: AppRoute.self)` were removed, and its `NavigationStack` only supplies the "Profiles" title and Close button. An earlier draft pushed `AppRoute.player` inside the sheet's own `NavigationStack` instead (simpler, no cross-file seam) but was the wrong UX: the pushed screen's Select/Switch/Deselect actions change app-wide state, and doing that one level inside a still-presented sheet reads as "still searching," with an extra manual dismiss afterward.
- **A custom `@Entry` environment action does not reach this sheet's content (found 2026-09-28) — plain closure parameter instead.** The first attempt added `OpenRouteAction`/`EnvironmentValues.openRoute` in `FestivalRootView.swift`, set via `.environment(\.openRoute, …)` on the same view chain as the working `\.openProfile`/`\.openDrawer`, and read via `@Environment(\.openRoute)` inside `ProfileSelectionSheet`. It silently never fired: `tools/ios_sim.py drive` proved this by swapping the handler body for `drawerPresented = true` (a `FestivalRootView` `@State` with a visible, already-proven side effect) and separately by reading the pre-existing `\.openDrawer` the same way from inside this sheet — **neither ever ran**, confirmed by both screenshots and `tree:` dumps showing no drawer content after the tap, across several fresh (`--rebuild`) driver builds. `\.openProfile`/`\.openDrawer` are read correctly everywhere else in the app (ordinary pushed/tab-root screens), so the failure is specific to reading a custom environment value from *inside* `.sheet(isPresented:)`-presented content in this SwiftUI setup, not to `openRoute` itself or to anything sheet-adjacent like `festivalSheet()` (ruled out by inspection — it only sets presentation styling). The fix: `ProfileSelectionSheet` now takes `openRoute: (AppRoute) -> Void = { _ in }` as a plain stored/init property, and `FestivalRootView`'s `.sheet` content closure passes `{ route in paths[selected, default: []].append(route) }` directly — ordinary Swift closure capture, the same mechanism `FestivalDrawer`'s already-working `onIntent: handleDrawer` uses, with no environment involved. Verified live via `tools/ios_sim.py drive`: the sheet's `fst.profile.view-selected` button now reliably dismisses and lands on the pushed player screen (Quick Links, global rank, avatar all visible). **Worth flagging to other lanes:** if a future sheet needs to read a value the presenter injected via `.environment()`, prefer a direct init parameter over an environment key until this is understood — it may be a broader SwiftUI/OS quirk in this project's toolchain, not unique to this one case.

Screenshots: `/tmp/laneP/sheet-anon.png` (`FST_DEBUG_SHEET=profile`) shows the redesigned sheet with a real selected identity, segmented scope, styled search pill and centered hint in one shot.

## Implemented (carried over)

- `FestivalSession` persists only a validated player ID + display name; corrupt stored identity is removed with a visible error. The score index records its observed publication; `hasCurrentPlayerScores(forCatalogue:)` reuses `SongRelatedPublicationPolicy`, so retained older Songs rows show an accessible **paused** state (`fst.songs.profile-paused`, `fst.songs.profile-paused-row.*`).
- Selected Songs disclosure offers manual Retry for 202 and errors, clearing old score bytes first.
- Profile avatar top-right on every tab root via `festivalRootChrome`; present the sheet through `@Environment(\.openProfile)`, never your own sheet.
- Provisional 16 MB post-transport body cap for player responses — measure real p99 payload size and decode latency before certifying large profiles.

## Gotchas

- **Wrong-account push (fixed 2026-09-28):** search results used to share one `Form` row (a `LazyVStack`), and on iOS one tap fired every result's Button, so the *last* result's profile landed on top. Results now render through `PlayerSearchResultRows`, one row each. The rule is in [architecture.md](../../platforms/apple/architecture.md#list-rows-hold-one-action), and `ProfileJourneyTests` guards it on-device.

- `FST_UI_TEST_CLEAR_PROFILE=1` (set by the shared XCUITest launcher) resets only this app's identity; the cold-restore test removes it for its second launch. A failed profile test must not leak identity into anonymous tests.
- `FST_DEBUG_PROFILE=<accountId>:<displayName>` (`FestivalRootView.DebugLaunchRoute`) selects a player **in memory only** before the session loads — the tool of record for screenshotting a selected state; prefer it over hand-writing `UserDefaults`. It never persists (see "Debug profile is in-memory only" above), so it is safe to run alongside other lanes' launches on the shared simulator.

## Open (iPhone)

Live account search re-probe, band selection (blocked pending a mutation-free read policy), source song-filter reset semantics on switch (vs. deselect), guarded-tab focus restoration, hosted/XCUITest coverage for the player-profile page and the redesigned sheet (Wave 1 is unit + visual smoke only, per `PROGRESS.md` §3). The root cause of custom `@Entry` environment values not reaching `.sheet` content (see above) was found empirically, not diagnosed to a specific SwiftUI mechanism — worth a real investigation (minimal repro, SDK version check) before any other lane relies on the same pattern.
