# Service status (`fst.service-status.*`) — spec

> **What:** platform-neutral behavior of the shared failed-read status: scrape freeze with automatic retry, generic outage, offline, syncing, not found and other errors. **Read when:** showing any failed public read on any platform. Platform notes: [ios.md](ios.md), [windows.md](windows.md).

Source: the web has no freeze UX; its client throws a generic `API <status>` error (`FortniteFestivalWeb/src/api/client.ts:119-120`). Freeze semantics come from the service ([service safety → freeze](../../platforms/service-safety.md#public-read-freeze)).

## Issue vocabulary

Every screen converts a thrown read error into one issue; screens never interpret HTTP codes themselves.

| Issue | Wire trigger | Heading | Behavior |
|---|---|---|---|
| `scrapeInProgress(retryAfter)` | 503 with a score-update `X-FST-Public-Read-Freeze-Reason`, for a read not already verified in the current publication (a verified one is served from the client's same-publication copy instead, [empty-error-states](../../patterns/empty-error-states.md) R9) | "Scores are updating" | Auto-retry countdown + "Retry Now" |
| `unavailable(retryAfter)` | 503 without one, or a non-lifecycle freeze reason | screen title ("… unavailable") | Manual Retry; message names `Retry-After` seconds when sent |
| `syncing` | 202 on an endpoint without a syncing envelope | "Still syncing" | Manual Retry |
| `notFound` | 404 not normalized to an empty result | screen title | Manual Retry |
| `offline` | device cannot reach the service | "You're offline" | Manual Retry only. Online-only: never implies cached data |
| `other(message)` | anything else | screen title | Readable message, manual Retry |

## States

| State | Rule |
|---|---|
| scrape-freeze-countdown | Countdown starts at `Retry-After` (30 s from the service; 30 s default), shows `m:ss`, and offers "Retry Now" |
| scrape-freeze-retrying | At zero the screen reloads. Consecutive failures on one screen double the wait (30 → 60 → 120 → 240 → 300 s cap); a failure after a quiet period starts again at `Retry-After` |
| unavailable / offline / syncing / not-found / other | Heading, message, "Retry"; no automatic retry |
| inline | One section of a multi-section page (a Leaderboards card, a Rivals section) shows a compact row with the same vocabulary and countdown; siblings keep rendering |

## Accessibility

- Heading is a header; Retry is ≥44 pt with a readable label ("Retry" / "Retry Now").
- Full-page states announce heading + message (or the countdown length) once on appearance; inline rows stay silent so a page of failing sections does not flood the screen reader. The countdown's spoken label is "Trying again automatically in N seconds".
- Reduce Motion (system or in-app) removes the pulsing symbol and numeric count transitions.

## Test IDs

`fst.service-status.title`, `.countdown`, `.retry`, `.inline`. Screens may keep their own container IDs (e.g. `fst.paths.error`, `fst.player.error`).
