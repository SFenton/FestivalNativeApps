# Profile selection — iPhone notes

> **What:** the SwiftUI selection sheet and session as built, decisions and open gaps. **Read when:** changing `Features/Profile` or `FestivalSession` identity (Lane P). Spec: [spec.md](spec.md).

## Implemented (partial)

- `FestivalSession` persists only a validated player ID + display name; corrupt stored identity is removed with a visible error. The score index records its observed publication; `hasCurrentPlayerScores(forCatalogue:)` reuses `SongRelatedPublicationPolicy`, so retained older Songs rows show an accessible **paused** state (`fst.songs.profile-paused`, `fst.songs.profile-paused-row.*`).
- `ProfileSelectionSheet` keeps search, viewed and selected player distinct; real loading/empty/403/202 states; confirms switch/deselect; disables selection when publication cannot be verified. The Bands scope shows a read-policy blocker and makes **no** band GET.
- Selected Songs disclosure offers manual Retry for 202 and errors, clearing old score bytes first.
- Profile avatar top-right on every tab root via `festivalRootChrome`; present the sheet through `@Environment(\.openProfile)`, never your own sheet.
- Provisional 16 MB post-transport body cap for player responses — measure real p99 payload size and decode latency before certifying large profiles.

## Native decisions

| Web | iPhone |
|---|---|
| Result opens `/player/:accountId` | In-sheet preview (player route is Wave 1, Lane P) |
| Target row below results, bottom transition | Top segmented scope, full-height system sheet |
| Clears all song filters on deselect | Clears score predicates only; keeps the public Shop choice ([songs-filter](../songs-filter/ios.md)) |

## Gotchas

- `FST_UI_TEST_CLEAR_PROFILE=1` (set by the shared XCUITest launcher) resets only this app's identity; the cold-restore test removes it for its second launch. A failed profile test must not leak identity into anonymous tests.
- Wave 1 fix pending: selected profile must survive app close / cold start ([PROGRESS.md](../../../PROGRESS.md)).

## Open (iPhone)

Player route, live account search (403 on 2026-09-25; re-probe pending), bands, source song-filter reset semantics, guarded tabs, complete focus restoration, sheet redesign (dark glass, Find Player / Find Band).
