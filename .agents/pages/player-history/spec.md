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

## Entry points and gaps

- Song Detail's Score History card lists the best five scores and, with more than five, a purple "View all scores" (`ScoreHistoryChart` → `GraphCard viewAllLabel`) that navigates to this page for the card's instrument; notifications and deep links open it directly. Native clients push the page; they never expand the card in place (issue #324).
- The page has no chart (the web has none); the chart lives on Song Detail.

## Test matrix

No player selected; 404 unregistered; 202 syncing; empty for this instrument; loaded with 1/many rows; each sort mode × direction; personal-best row tracks sort; Song Detail shows View all scores only above five rows.
