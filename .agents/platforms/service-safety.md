# Service safety (all platforms)

> **What:** the single home for live-service rules: keys, headers, side-effecting GETs, endpoint allowlist and live probes. **Read when:** adding or changing any network call, fixture or live probe on any platform. [AGENTS.md](../../AGENTS.md) holds the one-paragraph summary.

## Hard rules

- **Never embed, request or log the privileged `X-API-Key`.** Debug and Release default to keyless public `https://festivalscoretracker.com`; fixture tests must explicitly select a loopback origin. Never spoof client headers or bypass the edge.
- **Never send selected-profile headers.** The web client adds them to every GET (`FortniteFestivalWeb/src/api/client.ts:73-112`); service middleware touches registrations after responses, and cached responses repeat that path (`FSTService/Api/SelectedProfileActivityMiddleware.cs:47-103`, `FSTService/Api/PublicApiResponseCacheMiddleware.cs:635-653`).
- **Side-effecting GETs are blocked** until the service owner grants a mutation-free policy. Do not infer safety from the HTTP method, a cache hit or the website's usage:
  - band search: when its projection is absent it deletes/rebuilds/upserts membership state (`FSTService/Persistence/GlobalLeaderboardPersistence.cs:3954-3971,4433-4453`, `FSTService/Persistence/BandLeaderboardPersistence.cs:905-947`);
  - band detail `GET /api/bands/{bandId}`: `GetBandConfigurations` → `EnsureBandTeamConfigurations` rebuilds band team configuration rows on a cache miss (`FSTService/Persistence/GlobalLeaderboardPersistence.cs:4160,4192`). Natives resolve band detail through `GET /api/rankings/bands/{bandType}?teamKey=` instead;
  - player stats GET can compute and store tiers; band sync-status GET registers bands (`FSTService/Api/PlayerEndpoints.cs:508-546,815-830`, `FSTService/Api/BandSyncEndpoints.cs:10-43`).
  These are source-backed potential effects, not proof they fired in production.
- Never run profile tracking, name refresh, scrape, maintenance, export or load tests against production. POSTs are fixture-only.
- Never open a real Shop purchase link in automation; validate the official host instead. Never bundle third-party album art.
- Never copy production payloads, titles or account IDs into fixtures or committed docs.

## Endpoint allowlist

| Endpoint (keyless GET) | Status | Notes |
|---|---|---|
| `/api/publication`, `/api/songs` | allowed | Songs ETag/304 valid only within the observed publication |
| `/api/leaderboard/{song}/{instrument}?top=&offset=[&leeway=]` | allowed | `leeway` only with invalid-score filtering on |
| `/api/leaderboard/{song}/all?top=10` | allowed | Re-probed 2026-09-27: 200 keyless |
| `/api/paths/{song}/{instrument}/{difficulty}` and `/data` | allowed (200) | PNG and schema-2 JSON |
| `/api/shop` | allowed (200) | Validate outbound URLs are `https://www.fortnite.com/item-shop/jam-tracks/…` |
| `/api/rankings/*` | allowed (200, re-probed 2026-09-27) | Earlier Cloudflare 1010 denial no longer applies |
| `/api/account/search?q=&limit=10` | allowed | Re-probed 2026-09-27: 200 keyless. Publication-bound (`FSTService/Api/ApiPublicationClassification.cs:78-84`). An empty envelope is also returned after a logged DB timeout (`FSTService/Persistence/MetaDatabase.cs:3495-3517,3523-3537`) — never proof of no match |
| `/api/player/{accountId}` | allowed, not yet probed live | 202 = syncing; 200 ≠ registered/published (`FSTService/Api/PlayerEndpoints.cs:31-51,85-103`, `FSTService/Scraping/ScrapeTimePrecomputer.cs:911-953,2442-2476`) |
| `/api/player/{accountId}/rivals/{instrument\|combo}[/{rivalId}]`, `/leaderboard-rivals/{instrument}[/{rivalId}]` | allowed (200) | Pure reads (`FSTService/Api/RivalsEndpoints.cs`, `LeaderboardRivalsEndpoints.cs`); 404 = no rivals yet (normalized to empty). `POST …/rivals/recompute` is never called |
| `/api/player/{accountId}/rivals/all` | allowed (200, probed 2026-09-28) | Pure read (`FSTService/Api/RivalsEndpoints.cs:207-273`): precomputed `rivals-all:{id}` → process cache → `SELECT`s from `user_rivals`/`account_names`; stores bytes only in the in-memory response cache. Precomputed shape has `songs[]` + per-rival `direction`/`samples`; the live fallback omits them and adds `avgSignedDelta` |
| band search, band detail (`/api/bands/{bandId}`), player stats, band sync-status | **blocked** | See hard rules |

## Public-read freeze

While the service scrapes and publishes, `PublicReadGateMiddleware` stamps every `/api/` response with `X-FST-Public-Read-Freeze-Reason` (`FSTService/Api/PublicReadGateMiddleware.cs:21-29`) — **including 200s served from published cache**. A read with no stable published response answers **503** with `Retry-After: 30` and `Cache-Control: no-store` (`FSTService/Api/CacheHelper.cs:230-240`, `PublicReadGateMiddleware.cs:45-62`, `PublicApiResponseCacheMiddleware.cs:598-609`).

| Reason (`FSTService/Scraping/ScrapeLifecycleNotifier.cs`, `Persistence/PublicReadFreezeState.cs`) | Native meaning |
|---|---|
| `scrape`, `post-process`, `publish`, `publication-commit`, `publication-commit-deferred` | Scores are updating → `ServiceIssue.scrapeInProgress`, automatic retry |
| `publication-isolation-pending`, `max-score-maintenance:v1:*`, any other value | Generic outage → `ServiceIssue.unavailable` |
| 503 without the header | Generic outage |

Clients must treat a freeze as transient, honour `Retry-After` with capped backoff, and never interpret it as missing data. List endpoints can keep answering 200 during a freeze while detail endpoints 503 on a cache miss. UI: [service-status control](../controls/service-status/spec.md).

## Live probes

- `bash tools/apple_live_service_smoke.sh --read-public-live` — opt-in, three public GETs (publication, Songs, ten Lead rows) through the real Swift client; prints aggregate counts and provenance only. Never run in automated fixture/coverage suites.
- Record live observations with a date; counts and pinning state change. Automated UI tests use [fixtures](../testing/fixtures.md), not production.
