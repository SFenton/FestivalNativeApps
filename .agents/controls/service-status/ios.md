# Service status — iPhone notes

> **What:** the SwiftUI status views as built and how screens adopt them. **Read when:** rendering a failed read on iOS. Spec: [spec.md](spec.md).

## Components (`apple/Sources/FestivalUI/Common/ServiceStatusView.swift`)

| Type | Use |
|---|---|
| `ServiceStatusView(issue, title:, scope:, retry:)` | Full-page failed state. `title` is the screen's own heading, used unless the issue has a global one |
| `ServiceStatusInline(issue, scope:, retry:)` | One section/card of a multi-section page; `scope` must be unique per section (backoff key) |
| `.serviceStatusOverlay(issue, title:, retry:)` | Opaque cover over existing content while `issue != nil` |
| `ServiceUnavailableView(title:message:retry:)` | Legacy plain-message form; renders through `ServiceStatusView(.other)`. Use only for non-service failures (local sort/filter) |

`ServiceIssue`, `ServiceRetryBackoff` and `ServiceFreezeReason` are pure Core types (`FestivalCore/ServiceIssue.swift`, unit-tested). `ServiceRetryScheduler` holds one process-wide backoff so it survives each failure recreating the view.

## Adopting on a screen

1. Store the issue, not a string: `case failed(ServiceIssue)`; in `catch`, `state = .failed(ServiceIssue(error))`.
2. Render `case let .failed(issue): ServiceStatusView(issue, title: "Rankings unavailable") { Task { await load() } }`.
3. Previews/tests may keep `.failed("Synthetic outage")`: `ServiceIssue` is `ExpressibleByStringLiteral` (`.other`).
4. Keep a loaded page's refresh failure as its existing banner; the status view is for "nothing to show".

Adopted: Songs, Shop, Paths, Solo/Band song leaderboards, Player History, Notifications, Player/Statistics, Suggestions, Full/Band Rankings, Leaderboards cards (inline), Compete (inline), Rivals hub (inline)/All/Detail/Rivalry, Band Detail (+ inline history/songs), Player Bands.

## Screenshots

`python3 tools/ios_sim.py shot --tab songs --env FST_DEBUG_FORCE_FREEZE=1 --wait 5 --out /tmp/freeze.png` — Debug only; `ForcedFreezeTransport` answers each `/api/…` path's first read with a synthetic scrape 503 (`/api/publication` excluded), so every screen shows one freeze and recovers on the auto-retry.

## Open gaps

- Profile search and Find Rival search show the freeze as an inline message (no countdown).
- iOS 17 runtime not installed: the `symbolEffect`/`numericText` paths are compile-checked only there.
