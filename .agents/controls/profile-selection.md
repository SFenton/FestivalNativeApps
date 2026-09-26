# Profile discovery and selection - pending on every platform

Source: `FortniteFestivalWeb/src/hooks/data/useUnifiedSearch.ts:41-160`,
`packages/theme/src/animation.ts:7`,
`FortniteFestivalWeb/src/components/search/SearchModal.tsx:495-525,838-917`,
`FortniteFestivalWeb/src/state/selectedProfile.ts:10-175`, and
`FortniteFestivalWeb/src/App.tsx:760-785`. The web search waits for two
characters, debounces for 250 ms, independently loads players/bands and
shows an error separately from an empty result. Opening a result
**views** the player or band; selecting it as the current profile
is a distinct action. Switching/deselecting a saved profile changes
available tabs, song scores and filters; the selected band must keep
type, team key and validated members, not just a display name.

**Read and write boundary:** public account autocomplete
`GET /api/account/search?q=...&limit=10` returns `{results:
[{accountId,displayName}]}` from a database SELECT
(`FSTService/Api/AccountEndpoints.cs:43-61`,
`FSTService/Persistence/MetaDatabase.cs:3484-3537`).
The native Core client now validates a 2-200-character trimmed query,
encodes literal `+` as `%2B`, limits results to ten, trims benign
outer display-name spaces, rejects invalid/duplicate identities,
unsafe control/bidi formatting and oversized/malformed wire data.
It distinguishes an empty response envelope from HTTP 403/429/503,
cancellation and transport loss. The service **also returns an empty
envelope on a logged database timeout**, so native cannot claim that
an empty response proves no matching players. The client makes one
**keyless** GET with no selected-profile header, tracking POST or
cold-launch cache. The service classifies account search as
**publication-bound** (`FSTService/Api/ApiPublicationClassification.cs:78-84`),
but this initial native direct read intentionally omits a client
publication pin and does not retain response provenance. Revalidate
identity under the current publication before shipping a selected
profile flow. The loopback fixture has synthetic player results,
empty, 403/429/503 and invalid-input states; it rejects a selected
header or privileged key. No live profile endpoint was probed in
this slice. Account search can still be denied at the deployed edge;
this client contract is **not** evidence that live discovery works.

**Player-score foundation:** the source's unfiltered
`GET /api/player/{accountId}` reads existing score projections and
responds with compact `si` song IDs, single-bit `ins` instrument hex
codes, and `acc` accuracy divided by 1,000. A registered player
without a published profile instead receives a distinct HTTP 202
`status: syncing` envelope
(`FSTService/Api/PlayerEndpoints.cs:14-83,190-259`,
`FSTService/Scraping/ScrapeTimePrecomputer.cs:911-953,2442-2476`,
`FSTService/ComboIds.cs:8-43,100-117`,
`packages/core/src/api/serverTypes.ts:1654-1715,1740-1799`).
The shared Apple Core decoder now maps all nine source-ordered bits,
restores the accuracy scale, preserves explicit FC, legacy fallbacks
and newer precomputed `ml` / `vs` / `rt` variants, rejects
duplicate/mixed-identity or corrupt rows and builds a once-per-profile
Songs lookup. The service sends a numeric `-1` percentile sentinel
when the metric is unavailable; native maps **only that sentinel**
to nil, while the source Songs percentile pill derives its shown
rank percentage from `rk / te`, not raw `pct`
(`FSTService/Scraping/GlobalLeaderboardScraper.cs:513-520`,
`FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:73-84`,
`packages/core/src/app/formatters.ts:56-63`).
A keyless player
GET uses the existing publication-aware read but **never** sends
selected-profile headers or stores raw per-account response bytes
in the offline/ETag cache. It has a **provisional 16 MB post-transport
body cap**, not a streaming-memory guarantee; measure legitimate
maximum and p99 precomputed payload sizes and decoding latency
before certifying large profiles. HTTP 202 is explicitly syncing
even without a response publication header and cannot become an
empty score card. HTTP 200 means **public scores available**, not
necessarily that an account is registered or its profile is fully
published: unregistered accounts can receive a current-state
response (`FSTService/Api/PlayerEndpoints.cs:31-51,85-103`).
The original synthetic fixture's two accounts now agree with both
Lead song leaderboards on identity, score, rank, FC and wire-quantized
accuracy; the 202, available-empty and denied cases stay distinct
and the serial device runner pins their bytes. The fixture does
**not** establish any Bass or Pro Drums player chart. Missing-FC
unit rows are synthetic robustness data; real precomputed rows
carry nonnullable booleans and numeric accuracy, where false/zero
may still represent unknown service history. **No** production
player read or selected UI flow has run. Applying precomputed
fallback/rank-tier rules and profile-dependent Settings/cards
requires separate native logic and proof; do not substitute only
legacy fields when filtering invalid scores.

Do **not** copy the web client's habit of adding selection headers to
every GET (`FortniteFestivalWeb/src/api/client.ts:73-112`).
`SelectedProfileActivityMiddleware` touches registrations after API
responses, and cached responses explicitly repeat the activity path
(`FSTService/Api/SelectedProfileActivityMiddleware.cs:47-103`,
`FSTService/Api/PublicApiResponseCacheMiddleware.cs:635-653`).
The band-search GET is **not unconditionally read-only**: when its
search projection is absent or empty, it calls a membership-summary
builder that deletes, rebuilds and upserts database state
(`FSTService/Persistence/GlobalLeaderboardPersistence.cs:3954-3971,4433-4453`,
`FSTService/Persistence/BandLeaderboardPersistence.cs:905-947`).
The player stats GET can compute/store missing tiers and the band
sync-status GET registers activity
(`FSTService/Api/PlayerEndpoints.cs:508-546,815-830`,
`FSTService/Api/BandSyncEndpoints.cs:10-43`).
Band search, stats and sync-status are not in the native allowlist;
do not infer safety from an HTTP method, a cache hit or the website's
use of these endpoints. Source-based risk does not establish whether
the fallback is currently active in production.

| Control state | Native acceptance still required |
|---|---|
| No profile | Explicit profile action in phone/tab and tablet/desktop sidebar, accessible in every relevant destination |
| Search | Distinct player/band scopes, 250 ms debounce, loading, empty envelope (possibly server-timeout masked), 403/429/503, retry, cancellation and stale-result rejection |
| Viewed result | Identity preview/detail with a separate, confirmed Select action; no automatic selection or tracking write |
| Player selected | Validated identity persisted across relaunch; dependent Songs scores, metadata, Settings, tabs and routes refresh without cross-profile leakage |
| Band selected | Validated type/key/member identity, band song rows and configurations after a guaranteed mutation-free read policy |
| Switch/deselect | Distinct confirmation, Settings song-filter reset rules, protected routes cleared or redirected, correct focus restoration |

The current Apple implementation contains typed player autocomplete
and compact-score **read contracts** with unit/loopback fixture tests,
but no native profile button, selection, profile-based Songs card,
band search, viewed profile page or parity certification. Build
fixture-backed selection and dependent-card proof without shipping
synthetic identities or calling write-capable endpoints in Release;
service-owner authorization and a mutation-free band projection are
separate prerequisites for live parity.
