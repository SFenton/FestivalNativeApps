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
**not** establish any Bass or Pro Drums player chart. A new player-2
Pulse Drums score agrees with its published mock Drums chart, while
both Bass leaderboards stay empty for the dedicated offscreen
zero-entry journey. Missing-FC
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
| No profile | Profile action in every root section and wide sidebar works on Apple 26.5; nested routes, deep links and other platforms remain open |
| Search | Player 250 ms debounce, loading, empty envelope, 403 and retry have selected Apple proof; band scope is explicitly blocked, with no band GET |
| Viewed result | Native in-sheet public-score preview and a separate confirmed Select action work; the PWA instead navigates to a full player page |
| Player selected | Public ID/name persist across relaunch, but scores stay process-only and are re-fetched; one visible instrument and Settings metadata affect Songs rows, not every page/tab |
| Band selected | Validated type/key/member identity, band song rows and configurations after a guaranteed mutation-free read policy |
| Switch/deselect | Player switch/deselect confirmation clears earlier scores and nested Songs routes; source song-filter resets, guarded tabs and complete focus restoration remain open |

**Current Apple WIP:** `FestivalSession` persists only a validated
player ID and display name in this app's preferences. No score/FC
bytes survive a cold process launch; their next read must succeed
under the current publication before a card is painted. A generation
change, HTTP failure, explicit player switch or deselect clears the
old process-only score index, and request epochs reject late
cross-identity results. Corrupt stored identity is removed with a
visible error. `ProfileSelectionSheet` keeps search, viewed player
and selected player distinct, exposes real loading/empty/403/202
states, confirms switches/deselect, and disables selection if a
profile's publication cannot be verified. Its Band tab shows a
read-policy blocker and makes **no** band-search GET; it does not
invent a band profile. `FST_UI_TEST_CLEAR_PROFILE=1` resets only the
native app's selected identity in Debug fixture tests, never
simulator data or production user settings. The shared native
XCTest launcher now sets it by default for every fresh test app;
the one deliberate cold-restore journey removes it before its
second launch. A failed profile case must not leak a persisted
identity into unrelated anonymous UI tests. The runner removes
a stale compiled-test marker **before** cleaning when the test
source changes, so an H1 → failed H2 → H1 rollback cannot
silently skip H1's clean.

A headerless player response may be previewed but cannot be
selected or persisted: a trusted publication pin is required
for score cards and live selection remains blocked until the
service/edge grants one. A preview observes publication
revision and reloads after a generation change; an unverified
response and a changed previously pinned response have distinct
messages. The selected Songs disclosure offers manual Retry for
202 syncing as well as an error, clearing old score bytes before
every retry. `ScoreFormatting.percentileBucket` follows the
source's Songs buckets instead of an exact subpercent label.

The compact iPhone profile icon follows the web mobile header's
accessible-name pattern, while iPad/macOS use a visible selected
name in a native sidebar footer. Songs, Settings and the placeholder
Leaderboards root have reachable profile actions
(`FortniteFestivalWeb/src/components/shell/HeaderActions.tsx:59-105`,
`FortniteFestivalWeb/src/components/shell/desktop/PinnedSidebar.tsx:85-113`).
Unlike the web, a search hit opens an in-sheet preview instead of
the `/player/:accountId` route. The source mobile search has its
Players/Bands actions **below** the results and a custom bottom
transition; native uses a top segmented scope and full-height
system sheet on iPhone and a centered iPad sheet
(`FortniteFestivalWeb/src/components/search/SearchModal.tsx:29-41,529-592`).
These are documented WIP geometry/navigation differences, not
certified Fluent or pixel parity.

Selected fixture-backed iPhone/iPadOS 26.5 tests pass two
**3/3-per-device** matrices for search → view → explicit
selection/switch/deselect, actual changing score/FC/Settings,
cold identity-only restore, error/syncing/empty/band-blocked
states and root/sidebar/Paths navigation. A subsequent
**2/2 per-device** rerun confirms Retry appears only for error
or empty results, never on a populated result. Matched PWA
WebKit tests pass **2/2 at phone/tablet widths** with the
synthetic player; results, the first-run Filter Songs overlay
and unobstructed selected Songs are captured. A later
source-frozen **7/7 per-device** run rechecked selection,
cold restore, syncing/403 preview, the selected page audit,
and an existing Detail regression. It also proves a
fresh fixture app discards a previously selected identity
without erasing the simulator and that an anonymous user
can hide and re-enable the filtered Songs Intensity meter.
Both UI-test source stamps match current bytes after
separate iPad/iPhone product-only cleans.

Source mobile search places its target row below results, uses different
result geometry and opens a player route. The native sheet
opens an in-sheet preview with a top scope; the source selected
Songs card and conditional tabs also visibly differ. These
captures demonstrate gaps, **not** source-profile pixel parity.

The selected preview and Songs have one unwaived iPhone `.all`
audit pass. Named visible iPad screenshot text measures at
least 4.5:1 contrast, but its full `.all` audit reports unnamed
"Potentially inaccessible text"; focus bounds remain unproved.
Select grows by >1.35x at largest text and all visible sheet
actions stay reachable on both devices. Full screen-reader
order, all-state contrast, macOS GUI and 95%/90% coverage gates
are still pending. The source all-instrument status-chip row
is reduced to native's **first visible chart**, there is no
band/member card, and Filter Invalid Scores explicitly pauses
profile-score detail rather than applying unsupported fallback
logic. Settings `Show Instrument Icons`, dependent Detail and
Statistics/Suggestions/Rivals tabs, player route and legitimate
live edge access remain pending. No real profile endpoint was
probed or privileged key/selected header used. The control
stays `pending`.

Real macOS **test-only**, offscreen `NSHostingView` snapshots
now paint the anonymous profile Form, validated identity-only
selected header, native Players/Bands segmented picker,
search field, Deselect, Close, root action and AX5 variant
at 390/820pt. `ImageRenderer` previously returned crossed
yellow placeholders for its AppKit controls; it must not be
used as a visual substitute. The 2/2 hosted tests use a
throwing client factory, private optional synthetic captures
and an isolated preference suite. Further real AppKit text
edits test the 250 ms player search through distinct result,
validated-empty/Retry and 403/Retry responses; switching
native Players→Bands→Players renders the blocked membership
read warning with **zero** band GETs. These host tests cover
**667/1001** SwiftPM `ProfileSelectionSheet` executable lines;
viewed-result press/preview/selection, complete focus, Mac
app GUI and live edge access are still pending. The full
SwiftPM host category now passes 90%, while the paired iOS
UI/app subset remains 71.65% and fails its own bar. See
[native hosted snapshots](../testing/native-hosted-snapshots.md).
