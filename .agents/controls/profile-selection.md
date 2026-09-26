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

The current Apple implementation contains only the typed **player
autocomplete read contract** and unit/loopback fixture tests. There
is no native profile button, selection, profile-based Songs card,
band search, viewed profile page or parity certification yet. Build
fixture-backed selection and dependent-card proof without shipping
synthetic identities or calling write-capable endpoints in Release;
service-owner authorization and a mutation-free band projection are
separate prerequisites for live parity.
