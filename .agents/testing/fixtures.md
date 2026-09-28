# Mock service and fixtures

> **What:** the loopback mock service (`tools/mock_service.py`), its ports, scenarios and fixture files — shared by all platforms. **Read when:** writing a UI test or launching the app against deterministic data.

## Basics

- `python3 tools/mock_service.py --port 8765`, then launch Debug with `FST_API_BASE_URL=http://127.0.0.1:8765` ([Apple build-and-run](../platforms/apple/build-and-run.md)).
- Binds loopback only; implements publication pin / ETag / 409; **rejects every POST (405)**, selected-profile headers and privileged keys.
- Data: `contracts/fixtures/*.json` — `songs-demo`, `songs-empty` (synthetic; not a verified wire copy), `player-demo` (two synthetic players; player 2 has FC Lead + a Pulse Drums score; Bass charts stay empty on purpose), `path-demo` (schema-2), `shop-demo` (two offers, New + Leaving), `metadata-edge`, `publication`, `rivals-list-demo`, `leaderboard-rivals-demo`, `rival-detail-demo`, `leaderboard-rival-detail-demo`, `rivals-overview-demo`. All original/synthetic; no production payloads or third-party art.
- `GET /api/rankings/{instrument}` / `GET /api/rankings/bands/{bandType}`: deterministic in-code (not JSON-file) rankings — a fixed 3-account / 2-team roster (`fixture-player-1`/`2`, `fixture-rank-3`; `fixture-band-1`/`2`), paginated by the real `page`/`pageSize` query params. `fixture-player-1`/`2` reuse `player-demo`'s ids so a rankings row's navigation to a player profile resolves to real data.
- `GET /api/rankings/{instrument}/{accountId}/history`: `contracts/fixtures/player-rank-history-demo.json` (7 daily snapshots, Total Score rank 14 → 4) for `fixture-player-1`/`2` on every instrument; any other fixture account gets `{"history": []}` (unranked, never 404). Unknown instrument → 404, unexpected query → 400.
- `GET /api/player/{accountId}/history?songId=&instrument=`: `fixture-player-1` returns two `fixture-pulse`/`Solo_Guitar` rows; `fixture-syncing` returns HTTP 202 (`status: "syncing"`); every other account 404s (unregistered), matching `FSTService`'s real registered/unregistered split.
- `GET /api/player/{accountId}/notifications?limit=`: `fixture-player-1` returns two items (a rank-improved and an FC-achieved event, both on `fixture-pulse`); every other account gets an empty, `notificationsGenerated: false` envelope (200, never 404 — an unknown account isn't an error for this endpoint).
- Rivals/Compete (added by Lane U3): `GET /api/player/{id}/rivals/{instrumentOrComboToken}[/{rivalId}]` and `GET /api/player/{id}/leaderboard-rivals/{instrument}[/{rivalId}]` serve the fixtures above regardless of the requested instrument/token/rivalId (the rival id is echoed back into the response's `rival` field); a `-empty`/`-503` suffix on `{id}` (the *viewing* player, e.g. `fixture-riv-empty`) selects an empty list/detail or a 503 with `Retry-After`/`X-Fst-Public-Read-Freeze-Reason: scrape`, matching the live service's scrape-window freeze. `--port 0` asks the OS for a free loopback port instead of a fixed one (the process still prints `Local test fixture service on 127.0.0.1:<port>`) — used by `RivalsRenderTests.swift`'s hosted (non-simulator) tests, since Rivals reads need a genuine loopback origin (see that file's own header comment).

## Scenarios (`FST_FIXTURE_SCENARIO`)

| Scenario | Serves |
|---|---|
| `art-error` / `art-skip` | 404-only art / valid→bad→valid catalogue art |
| `art-white` | One pure-white cover + unavailable solo score (contrast worst case) |
| `shop-error` / `shop-empty` / `shop-single` | Shop 503 / validated empty feed / one offer (distinct: a 503 must never look empty) |

## Stateful listeners (fresh process per device suite; the matrix runner owns and cleans them)

| Port | Flags | Purpose |
|---|---|---|
| 8769 | `--fail-first-white-catalogue` | Songs 503 once → Settings check → recovered Songs |
| 8767 / 8768 | `--unpinned --rollover-on-command` | iPhone / iPad generation 7→8 via one `GET /__fixture__/advance-publication` (`--rollover-on-read 2` is only for its Python wire test) |
| 8771 | `--unpinned --stop-after-first-songs` | Songs connection loss (legacy offline journey) |
| 8772 | `--unpinned --stop-after-first-score` | Serves the top-10 preview **and** first top-25 chart, then closes (legacy offline journey) |
| 8773 | `--unpinned --stop-after-first-shop` | Closes after a validated Shop read and a test-only painted-art proof |
| 8774 / 8775 | `--unpinned --stop-after-first-score` | Offscreen tenth Lead row / empty Bass full chart |
| 8776 | `--metadata-edge` (pinned) | Long title, seven-digit score, Shop New offer |
| 8777 / 8778 | `--rollover-on-command --mismatched-shop-rollover` (pinned) | Old Songs / new Shop + profile / Songs 503 join (8778 = iPad, untested) |

Diagnostics (numeric only, never IDs or payloads): `/__fixture__/last-score-query`, `/__fixture__/last-full-score-query` (only `top=25`), `/__fixture__/publication-join-reads`.

Online-only (2026-09-27): the one-shot offline listeners support older journeys; do not add new offline tests. Reuse of a pre-existing 8765 is allowed only if its startup hashes and flags match the frozen inputs; never kill a stale service you did not start.

## Bands/Player/Statistics additions (Lane U4)

Added for the Profile/Statistics/Bands/Settings/Suggestions UX-test lane, since
none of these routes previously existed in the fixture server:

- `GET /api/rankings/{instrument}/{accountId}`: `fixture-player-1`/`2`/`fixture-rank-3` return an `AccountRankingEntry`-shaped row plus `instrument`/`totalRankedAccounts` (rank 1/2/3); `fixture-rank-unranked` (a registered player with one Lead score, outside the roster) 404s → the app's honest **unranked** state; `fixture-rank-fail` (also a registered Lead-scoring player) always 500s → the **failed/retry** state. Every other/unknown account also 404s.
- `GET /api/player/{accountId}/bands?group=&page=&pageSize=`: `fixture-player-1` has a synthetic 30-row "all" group (18 duos + 8 trios + 4 quads, `pageSize=25` → 2 pages) built by `_player_band_entry`; its first duo reuses `fixture-band-1`/`fixture-team-1` so Player Bands and Band Rankings resolve to the same Band Detail. `fixture-player-2` (and any other account) gets an empty page, matching the real service's missing-projection-fallback behavior.
- `GET /api/rankings/bands/{bandType}?teamKey=…`: filtered lookup for `FestivalAPI.bandProfile` (`selectedBandEntry`), built by `_band_detail` — a **richer** member/config shape than a plain `entries[]` row (matching the live service, which only attaches full instrument/combo detail to the one filtered team). `fixture-team-1` (rank 1) carries one Duets combo `BandConfiguration`; `fixture-team-2` (rank 2) has none. `teamKey=fixture-team-503` 503s with `Retry-After`/`X-Fst-Public-Read-Freeze-Reason: scrape`, matching the Rivals scrape-freeze shape, for testing `BandDetailScreen`'s failed state. Unknown team keys return `selectedBandEntry: null` (client-side `invalidBandProfile`).
- `GET /api/rankings/bands/{bandType}/{teamKey}/history?days=`: `fixture-team-1` returns 3 daily snapshots; every other team key returns an empty `history`.
- `GET /api/rankings/bands/{bandType}/{teamKey}/songs?limit=`: `fixture-team-1` returns one catalog-linked Best row (`fixture-pulse`) and one **not-in-catalog** Worst row (`fixture-ghost-song`, exercising `BandDetailScreen`'s raw-songId fallback); every other team key returns empty `best`/`worst`.
- `GET /api/leaderboard/{songId}/bands/{bandType}?top=&offset=`: `fixture-pulse`/`Band_Duets` returns two ranked entries (reusing `fixture-band-1`/`fixture-band-2`'s rosters, this time with per-member score/accuracy/stars populated, matching `SongBandLeaderboardEntry`); every other song/band-type pair is empty.

A dedicated loopback instance for these lane's XCUITest journeys runs on `127.0.0.1:18790` (started manually, not the shared default `8765`) since the shared `8765` listener predates this lane's `tools/mock_service.py` changes and "never kill a stale service you did not start" forbids restarting it to pick up new code; hosted (non-simulator) tests instead reuse `RivalsMockService`'s `--port 0` launcher, which always starts a fresh process from the current source.
