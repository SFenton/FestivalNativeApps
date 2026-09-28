# player-history (`/songs/:songId/:instrument/history`) — spec

> **What:** platform-neutral web behavior of the selected player's score-change history for one song and instrument. **Read when:** changing score history on any platform. Platform notes: [ios.md](ios.md).

Source: `FortniteFestivalWeb/src/pages/leaderboard/player/PlayerHistoryPage.tsx:41-298`, `src/pages/leaderboard/player/modals/PlayerScoreSortModal.tsx`, `src/hooks/data/useSortedScoreHistory.ts`, `src/hooks/data/useScoreFilter.ts`. Wire type: `packages/core/src/api/serverTypes.ts:860-888`.

## Query

- `GET /api/player/{accountId}/history?songId=&instrument=` — pure, keyless read of a precomputed published cache (`FSTService/Api/PlayerEndpoints.cs:733-790`); it never writes. Not registered under `/api/player/**` publication gating the same way `/notifications` is, but still frozen the same as other `/api/player/*` reads while a publication is unready.
- Registration gate: an account absent from `registeredAccountIds` gets HTTP 404 `{error: "Score history is only available for registered users."}` — not empty history, a distinct unavailable state.
- Precompute gate: a registered account whose history has not been computed yet gets HTTP 202 `{accountId, status: "syncing", notYetPublished: true, count: 0, history: []}`.
- Response rows already match `songId`/`instrument` server-side; the web still re-filters client-side (`history.filter(entry => entry.instrument === instKey)`) as a defensive no-op, which the native client also does.
- `ServerScoreHistoryEntry`: `songId, instrument, oldScore?, newScore, oldRank?, newRank, accuracy?, isFullCombo?, stars?, percentile?, season?, scoreAchievedAt?, seasonRank?, allTimeRank?, difficulty?, changedAt`. Display date prefers `scoreAchievedAt`, falling back to `changedAt`.

## Sort

- Modes: `date | score | accuracy | season` (`PlayerScoreSortMode`), each with an independent ascending/descending toggle. Default: `score` descending.
- Accuracy ties break by full combo, then score, then date (`useSortedScoreHistory.ts:26-36`).
- The highest `newScore` in the *currently sorted* list is highlighted (`highScoreIndex` in `PlayerHistoryPage.tsx:150-157`) — it moves with sort/filter, it is not fixed to the chronologically-newest row.
- Sort state is in-memory only (component state), not persisted across visits.

## States

| State | Web behavior |
|---|---|
| No player selected | `history.selectPlayer` message, no request made |
| Loading | Spinner |
| 404 (unregistered) | Distinct "registered users only" message, not an empty list |
| 202 (syncing) | Distinct syncing message |
| Empty (0 rows for this instrument) | `history.noHistoryForInstrument` |
| Error | Parsed API error title/subtitle |
| Loaded | Virtualized list, personal-best row highlighted, sort/filter applied |

## Native client contract

- Route mirrors the web: `PlayerHistoryScreen(session:song:instrument:)`, always reading `session.selectedPlayer` (the web ties the page to `useTrackedPlayer()`, not a viewed-but-unselected player).
- Never send the selected-profile header; this is an ordinary keyless GET like every other native read.
- 202 and 404 are explicit `PlayerHistoryState` cases (`.syncing`, `.unregistered`), not folded into the generic error path — the UI text must not claim "no history" for either.
- Invalid-score filtering (`useScoreFilter().filterHistory`) is **not** ported natively this wave: the native client shows the server's rows as-is. If Settings later exposes filtered-score display for other surfaces, extend `PlayerHistoryPayload.entries(songId:instrument:)` to filter consistently.

## Gaps and open issues

- **No entry point today.** Neither Song Detail nor the solo leaderboard link to this route natively yet (the web reaches it from a per-instrument action on those pages). Route `.playerHistory(Song, Instrument)` and the screen exist and are reachable only via `FST_DEBUG_ROUTE`/hosted tests until Song Detail or Song Leaderboard add a link — flagged for those lanes.
- Swift Charts score-over-time line chart is a native addition (the web has no chart on this page); it renders only with two or more dated entries.

## Test matrix

No player selected; 404 unregistered; 202 syncing; empty for this instrument; loaded with 1/many rows; each sort mode × direction; personal-best row tracks sort; stale/offline banner; chart present/absent (0–1 vs 2+ dated rows).
