# Service safety (all platforms)

> **What:** the single home for live-service rules: keys, headers, side-effecting GETs, endpoint allowlist and live probes. **Read when:** adding or changing any network call, fixture or live probe on any platform. [AGENTS.md](../../AGENTS.md) holds the one-paragraph summary.

## Hard rules

- **Never embed, request or log the privileged `X-API-Key`.** Debug and Release default to keyless public `https://festivalscoretracker.com`; fixture tests must explicitly select a loopback origin. Never spoof client headers or bypass the edge.
- **Never send selected-profile headers.** The web client adds them to every GET (`FortniteFestivalWeb/src/api/client.ts:73-112`); service middleware touches registrations after responses, and cached responses repeat that path (`FSTService/Api/SelectedProfileActivityMiddleware.cs:47-103`, `FSTService/Api/PublicApiResponseCacheMiddleware.cs:635-653`).
- **Side-effecting GETs are blocked** until the service owner grants a mutation-free policy. Do not infer safety from the HTTP method, a cache hit or the website's usage:
  - band search: when its projection is absent it deletes/rebuilds/upserts membership state (`FSTService/Persistence/GlobalLeaderboardPersistence.cs:3954-3971,4433-4453`, `FSTService/Persistence/BandLeaderboardPersistence.cs:905-947`);
  - band detail `GET /api/bands/{bandId}`: `GetBandConfigurations` → `EnsureBandTeamConfigurations` rebuilds band team configuration rows on a cache miss (`FSTService/Persistence/GlobalLeaderboardPersistence.cs:4160,4192`). Natives resolve band detail through `GET /api/rankings/bands/{bandType}?teamKey=` instead;
  - band team ranking `GET /api/rankings/bands/{bandType}/{teamKey}` (bare route, no sub-path): also calls `GetBandConfigurations` → `EnsureBandTeamConfigurations` (`FSTService/Api/RankingsEndpoints.cs:1020,1049`). Its `/history`, `/songs`, `/song-rows` sub-routes and `GET /api/rankings/bands/{bandType}?teamKey=` do **not** write and are allowed;
  - player stats GET can compute and store tiers; band sync-status GET registers bands (`FSTService/Api/PlayerEndpoints.cs:508-546,815-830`, `FSTService/Api/BandSyncEndpoints.cs:10-43`).
  These are source-backed potential effects, not proof they fired in production.
- Never run profile tracking, name refresh, scrape, maintenance, export or load tests against production. POSTs are fixture-only in automation; the one user-initiated POST is [in-app feedback](#user-initiated-feedback-post).
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
| `/api/rankings/{instrument}/{accountId}/history?days=` | allowed (pure read; probed live 2026-09-28: 200) | `FSTService/Api/RankingsEndpoints.cs:392-413` → `InstrumentDatabase.GetRankHistory` (`FSTService/Persistence/InstrumentDatabase.cs:3143-3224`): one `SELECT` over `rank_history` ⋈ snapshot stats. `GetOrCreateInstrumentDb` only memoizes an in-process handle. No 404 for an unranked account (empty `history`). Player-profile rank-history chart |
| `/api/account/search?q=&limit=10` | allowed | Re-probed 2026-09-27: 200 keyless. Publication-bound (`FSTService/Api/ApiPublicationClassification.cs:78-84`). An empty envelope is also returned after a logged DB timeout (`FSTService/Persistence/MetaDatabase.cs:3495-3517,3523-3537`) — never proof of no match |
| `/api/player/{accountId}` | allowed (probed live 2026-09-28: 200) | 202 = syncing; 200 ≠ registered/published (`FSTService/Api/PlayerEndpoints.cs:31-51,85-103`, `FSTService/Scraping/ScrapeTimePrecomputer.cs:911-953,2442-2476`) |
| `/api/player/{accountId}/rivals/{instrument\|combo}[/{rivalId}]`, `/leaderboard-rivals/{instrument}[/{rivalId}]` | allowed (200) | Pure reads (`FSTService/Api/RivalsEndpoints.cs`, `LeaderboardRivalsEndpoints.cs`); 404 = no rivals yet (normalized to empty). `POST …/rivals/recompute` is never called |
| `/api/player/{accountId}/rivals/all` | allowed (200, probed 2026-09-28) | Pure read (`FSTService/Api/RivalsEndpoints.cs:207-273`): precomputed `rivals-all:{id}` → process cache → `SELECT`s from `user_rivals`/`account_names`; stores bytes only in the in-memory response cache. Precomputed shape has `songs[]` + per-rival `direction`/`samples`; the live fallback omits them and adds `avgSignedDelta` |
| `/api/rankings/combo?combo=&rankBy=&page=&pageSize=`, `/api/rankings/combo/{accountId}?combo=&rankBy=` | allowed (pure read) | `FSTService/Api/RankingsEndpoints.cs:528-613`: `MetaDatabase.GetComboLeaderboard`/`GetComboRank`/`GetComboTotalAccounts` + display-name `SELECT`s; frozen-miss 503 like other reads. 400 without two instruments; 404 for cross-group combos or an unranked account (treat as empty board/no rank) |
| `/api/player/{accountId}/notifications?limit=` | allowed (pure read) | `FSTService/Api/ImprovementNotificationEndpoints.cs:10-31` → `ImprovementNotificationService.GetPlayerNotifications` (`Persistence/ImprovementNotificationService.cs:441-552`): one `SELECT` over visible `player_improvement_events`; `limit` clamped 1–200; `Cache-Control: public, max-age=60`. The band variants (`/api/rankings/bands/{type}/{teamKey}/notifications`, `/api/bands/{bandId}/notifications`) are not used by natives |
| `/api/service-info` | allowed (pure read, operational) | `FSTService/Api/HealthEndpoints.cs:62-300`: in-process `ScrapeProgressTracker` + one `SELECT` (`MetaDatabase.GetServiceRuntimeState`, `Persistence/MetaDatabase.cs:2769`; catalog-lag read memoized in process). Not publication-bound, so never a freeze 503; carries the freeze header. `Cache-Control: public, max-age=1`. Body also exposes infrastructure fields (`postgresConnectionTarget`, `serviceInstance`): natives must not decode, store or log them. Settings Service Info polls it every 5 s only while visible |
| `/api/version` | allowed (pure read) | `HealthEndpoints.cs:18-29`: assembly metadata `{version}`, `max-age=86400`. Settings → Version |
| `/api/leaderboard/{songId}/bands/all?top=&accountId=[&selectedBandType=&selectedTeamKey=&combo=]`, `/api/leaderboard/{songId}/bands/{bandType}` | allowed (pure read) | `FSTService/Api/LeaderboardEndpoints.cs:14-160` → `BuildSongBandLeaderboardsPayload` (`MetaDatabase` SELECTs only; checked 2026-09-29). `accountId` only highlights the selected player's band in the response and bypasses the shared preview cache; frozen misses 503 like other reads. Song Detail band previews |
| `/api/features` | allowed (pure read) | `{appManual, feedback}` flags. Settings shows the feedback rows only for `feedback: true` ([feedback-form](../controls/feedback-form/spec.md)) |
| `/api/feedback/{id}` | allowed (pure read; only for an ID this client just received) | In-memory job status (60 min); `id` is validated as 32 lowercase hex before the call. 404 once expired or when feedback is disabled |
| band search, band detail (`/api/bands/{bandId}`), bare band team ranking (`/api/rankings/bands/{type}/{teamKey}`), player stats, band sync-status | **blocked** | See hard rules |

## User-initiated feedback POST

`POST /api/feedback` (multipart) is the only write natives send to production, and only when a person presses **Submit** in the [feedback form](../controls/feedback-form/spec.md). It files a real GitHub issue, so:

- never call it from automated tests, evidence runs or probes; use a loopback stub or `FakeTransport`/fake handlers;
- send no `X-API-Key` and no selected-profile headers, only the documented form fields (diagnostics: app version, OS version and device model, nothing that identifies the person);
- respect 429 `Retry-After` and 503 `feedback_busy`; never retry automatically;
- show only fixed client copy, never the server's `error` text.

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
- Driving the **production PWA** (`tools/pwa_ios.py`, [pwa-reference](../testing/pwa-reference/apple.md)) is browse-only: never select a profile, never type into global/profile search (the web queries band search on every keystroke, `FortniteFestivalWeb/src/hooks/data/useUnifiedSearch.ts:120-175`), never open a player page (it GETs `/api/player/{id}/stats`, `FortniteFestivalWeb/src/pages/player/PlayerPage.tsx:132-138`) or a band page. 2026-09-28: an off-screen XCUITest tap opened one public player page once (stats + sync-status GETs, no track POST, no selected-profile headers); the driver now refuses off-screen taps.
- Record live observations with a date; counts and pinning state change. Automated UI tests use [fixtures](../testing/fixtures.md), not production.

## Wire scale notes

- Player score-history `accuracy` is in **ten-thousandths of a percent** (`1000000` = 100%), like band accuracy; never a 0–1 fraction. Fixtures must use the same scale (`tools/mock_service.py` fixed 2026-09-28). Ranking `avgAccuracy` (player and band) and band member/row `accuracy` use the same scale (live band `avgAccuracy` 999271, 2026-09-28); fixtures aligned the same day.
- Rival detail `GET /api/player/{accountId}/rivals/{combo}/{rivalId}?allowLiveFallback=true` is **allowed**: the fallback only computes samples from reads (`RivalsCalculator.ComputeDirectSongSamples` → `GetCurrentStatePlayerScores*`, no writes; verified 2026-09-28). The web passes it for Find Rival / untracked accounts; natives should too.
