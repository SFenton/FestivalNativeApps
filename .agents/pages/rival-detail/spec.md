# rival-detail (`/rivals/:rivalId`) — spec stub

> **What:** generated placeholder; this page has not been investigated. **Read when:** starting work on it — replace this stub with real web behavior first ([port-page skill](../../skills/port-page/SKILL.md)).

<!-- stub -->

- Guard: `player` · Web source: `FortniteFestivalWeb/src/App.tsx:81` (route declaration)
- Backlog: route `rival-detail` — Apple `absent`, epics `apple-rivals`; gap text via `python3 tools/parity_backlog.py --list`

## Parity gaps (from the pre-2026-09-27 parity audit)

- Native acceptance: Rival drill-down; player-only guard.

## Native correction: publish freeze (#95, 2026-10-02)

- While the service publishes (`X-FST-Public-Read-Freeze-Reason`), `GET /api/player/{id}/rivals/{scope}/{rivalId}` serves only `RivalsCache` entries stored earlier in the same publication and answers 503 "Published data unavailable" otherwise (`FSTService/Api/RivalsEndpoints.cs` detail handler → `CacheHelper.ServeUnavailableIfFrozen`). The cache key is account, canonical scope, rival, `limit`, `offset`, `sort`, `allowLiveFallback`, `includeGaps`; detail is never prewarmed. `/rivals/{scope}` and `/rivals/all` are prewarmed and keep answering 200.
- Natives must therefore send the web's scope and query (`FortniteFestivalWeb/src/pages/rivals/helpers/rivalRouteState.ts` `resolveRivalCombos`; `api/client.ts` `getRivalDetail`: `?limit=0&sort=closest[&allowLiveFallback=true]`, no `offset=0`). Rivals hub rows open with the Settings scope, not the row's instrument.
- A cold key still 503s even in the web shape. `/rivals/all` embeds each rival's song samples `{s, i, ur, rr, us, rs}` (the same `rival_song_samples` rows), so a client can rebuild the comparison (filter `i` to the scope's instruments, `rankDelta = rr − ur`, sort by `|rankDelta|`) and keep the retry state only when that rival has no samples.
