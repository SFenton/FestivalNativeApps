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

## Player profile page

`AppRoute.player`/`.playerBands` are implemented (see [player-profile/ios.md](../../pages/player-profile/ios.md)); the sheet's search results and its "View Profile" action now push the real route instead of the old in-sheet preview.

## Sheet redesign (native, dark glass)

Per `.agents/design/apple/liquid-glass.md`'s "sections inside sheets" rule (native `Form` + `FestivalSectionHeader` + tinted `listRowBackground`, never a nested glass card):

- White Title Case section headers: "Selected Profile", "Find a Profile" (was grey system uppercase).
- Segmented Players/Bands scope kept as a real `Picker(.segmented)` (an `NSSegmentedControl` under the existing macOS `NSHostingView` render tests) rather than switched to `.searchScopes`, to keep those tests introspecting a real control.
- Search field: a styled pill (leading magnifying glass, rounded capsule, trailing clear button) whose placeholder switches "Find Player" / "Find Band" with the scope. **Not** a literal `.searchable` — that field is system-placed chrome the existing off-window `NSHostingView` snapshot tests (`ProfileSelectionSheetRenderTests.swift`) cannot reliably introspect; the styled `TextField` matches `.searchable`'s shape while staying a directly hosted, testable control. Documented in `ProfileSelectionSheet`'s own doc comment for whoever revisits this.
- Bands scope now keeps the search field visible (disabled) with an honest gating explanation below it, instead of hiding the field outright — matches the requirement that the prompt itself says "Find Band". Updated `profileBandScopeKeepsUnsafeSearchBlocked` to assert `isEnabled` toggles rather than the field disappearing.
- The "Enter at least two characters…" hint now centers in the remaining sheet space (`containerRelativeFrame(.vertical) { length, _ in max(length * 0.55, 180) }`) instead of sitting as a small inline row.
- Navigation choice — **push inside the sheet's own `NavigationStack`**, not dismiss-then-push onto the presenting tab: a result row and the selected-profile summary's new "View Profile" link both push `AppRoute.player` through the existing `AppRouteDestination` (already visible within `FestivalUI`, no seam change needed). Dismissing the sheet and pushing onto the *presenting tab's* own path instead would need `FestivalRootView` (Lane A, owns the sheet presentation and per-tab paths) to expose a new callback/environment action — flagged as a follow-up, not done here. Because the pushed screen already offers Select/Switch/Deselect, closing the sheet from there returns straight to the tab it was opened from (same pattern as Contacts/Messages "New Message" search).

Screenshots: `/tmp/laneP/sheet-anon.png` (`FST_DEBUG_SHEET=profile`) shows the redesigned sheet with a real selected identity, segmented scope, styled search pill and centered hint in one shot.

## Implemented (carried over)

- `FestivalSession` persists only a validated player ID + display name; corrupt stored identity is removed with a visible error. The score index records its observed publication; `hasCurrentPlayerScores(forCatalogue:)` reuses `SongRelatedPublicationPolicy`, so retained older Songs rows show an accessible **paused** state (`fst.songs.profile-paused`, `fst.songs.profile-paused-row.*`).
- Selected Songs disclosure offers manual Retry for 202 and errors, clearing old score bytes first.
- Profile avatar top-right on every tab root via `festivalRootChrome`; present the sheet through `@Environment(\.openProfile)`, never your own sheet.
- Provisional 16 MB post-transport body cap for player responses — measure real p99 payload size and decode latency before certifying large profiles.

## Gotchas

- `FST_UI_TEST_CLEAR_PROFILE=1` (set by the shared XCUITest launcher) resets only this app's identity; the cold-restore test removes it for its second launch. A failed profile test must not leak identity into anonymous tests.
- `FST_DEBUG_PROFILE=<accountId>:<displayName>` (Lane A, `FestivalRootView.DebugLaunchRoute`) pre-selects a player before the session loads — the tool of record for screenshotting a selected state; prefer it over hand-writing `UserDefaults`.

## Open (iPhone)

Live account search re-probe, band selection (blocked pending a mutation-free read policy), source song-filter reset semantics on switch (vs. deselect), guarded-tab focus restoration, hosted/XCUITest coverage for the player-profile page and the redesigned sheet (Wave 1 is unit + visual smoke only, per `PROGRESS.md` §3).
