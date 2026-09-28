# Mock service and fixtures

> **What:** the loopback mock service (`tools/mock_service.py`), its ports, scenarios and fixture files — shared by all platforms. **Read when:** writing a UI test or launching the app against deterministic data.

## Basics

- `python3 tools/mock_service.py --port 8765`, then launch Debug with `FST_API_BASE_URL=http://127.0.0.1:8765` ([Apple build-and-run](../platforms/apple/build-and-run.md)).
- Binds loopback only; implements publication pin / ETag / 409; **rejects every POST (405)**, selected-profile headers and privileged keys.
- Data: `contracts/fixtures/*.json` — `songs-demo`, `songs-empty` (synthetic; not a verified wire copy), `player-demo` (two synthetic players; player 2 has FC Lead + a Pulse Drums score; Bass charts stay empty on purpose), `path-demo` (schema-2), `shop-demo` (two offers, New + Leaving), `metadata-edge`, `publication`. All original/synthetic; no production payloads or third-party art.
- `GET /api/rankings/{instrument}` / `GET /api/rankings/bands/{bandType}`: deterministic in-code (not JSON-file) rankings — a fixed 3-account / 2-team roster (`fixture-player-1`/`2`, `fixture-rank-3`; `fixture-band-1`/`2`), paginated by the real `page`/`pageSize` query params. `fixture-player-1`/`2` reuse `player-demo`'s ids so a rankings row's navigation to a player profile resolves to real data.
- `GET /api/player/{accountId}/history?songId=&instrument=`: `fixture-player-1` returns two `fixture-pulse`/`Solo_Guitar` rows; `fixture-syncing` returns HTTP 202 (`status: "syncing"`); every other account 404s (unregistered), matching `FSTService`'s real registered/unregistered split.
- `GET /api/player/{accountId}/notifications?limit=`: `fixture-player-1` returns two items (a rank-improved and an FC-achieved event, both on `fixture-pulse`); every other account gets an empty, `notificationsGenerated: false` envelope (200, never 404 — an unknown account isn't an error for this endpoint).

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
