# Profile discovery and selection (`fst.profile.*`) — spec

> **What:** platform-neutral web behavior, wire contracts and client rules for searching, viewing and selecting a player or band. **Read when:** touching search, selected identity or anything that depends on it, on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md) · [windows.md](windows.md). Endpoint safety: [service-safety](../../platforms/service-safety.md).

Source: `FortniteFestivalWeb/src/hooks/data/useUnifiedSearch.ts:41-160`, `packages/theme/src/animation.ts:7`, `FortniteFestivalWeb/src/components/search/SearchModal.tsx:495-525,838-917`, `FortniteFestivalWeb/src/state/selectedProfile.ts:10-175`, `FortniteFestivalWeb/src/App.tsx:760-785`. Audit refs: `App.tsx:760-834`, `SearchModal.tsx:495-590`. Layout refs: `FortniteFestivalWeb/src/components/search/SearchModal.tsx:29-41,529-592`, `FortniteFestivalWeb/src/components/shell/HeaderActions.tsx:59-105`, `FortniteFestivalWeb/src/components/shell/desktop/PinnedSidebar.tsx:85-113`.

## Web behavior

- Search waits for two characters, debounces 250 ms, loads players and bands independently, and shows errors separately from empty results. Mobile puts the Players/Bands target row **below** results with a custom bottom transition.
- Opening a result **views** the player/band route; **selecting** it as the current profile is a distinct action. Mobile header uses an icon-only profile action; wide layouts name the selected account in the sidebar.
- The header profile action opens search **only without a selection**: a selected player (or a band with type and team key) goes to Statistics, their own profile (`FortniteFestivalWeb/src/utils/profileNavigation.ts` `getProfileClickDestination`, `App.tsx:760-773`). Natives match this on every platform (issue #290).
- Switching/deselecting changes available tabs, song scores and filters (Songs filters, instrument and player sorts reset on confirmed deselect or a player↔band switch, not on a player-to-player switch: [songs-filter spec](../songs-filter/spec.md)). A selected band keeps type, team key and validated members, not just a name.

## Wire

- Account search: `GET /api/account/search?q=…&limit=10` → `{results:[{accountId,displayName}]}` from a DB SELECT (`FSTService/Api/AccountEndpoints.cs:43-61`, `FSTService/Persistence/MetaDatabase.cs:3484-3537`). An empty envelope is also returned after a logged DB timeout — never proof of no matches.
- Player scores: unfiltered `GET /api/player/{accountId}` returns compact `si` song IDs, single-bit `ins` instrument hex codes and `acc` accuracy ÷1,000; a registered but unpublished player gets HTTP 202 `status: syncing` (`FSTService/Api/PlayerEndpoints.cs:14-83,190-259`, `FSTService/Scraping/ScrapeTimePrecomputer.cs:911-953,2442-2476`, `FSTService/ComboIds.cs:8-43,100-117`, `packages/core/src/api/serverTypes.ts:1654-1715,1740-1799`). Newer rows carry precomputed `ml`/`vs`/`rt` variants. Percentile `-1` is an "unavailable" sentinel; the Songs pill derives rank % from `rk / te`, not raw `pct` (`FSTService/Scraping/GlobalLeaderboardScraper.cs:513-520`, `FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:73-84`, `packages/core/src/app/formatters.ts:56-63`). HTTP 200 ≠ registered.
- Player stats and band sync-status GETs can write: **blocked**. Band search is read-only since the #320 service fix and allowed under [service-safety](../../platforms/service-safety.md#endpoint-allowlist) conditions; natives use it in global search, but choosing a band as the selected profile is not built yet, so the native profile sheet's Bands scope says so and points to Search.

## Native client contract (all platforms)

- Query: trimmed 2–200 chars, literal `+` encoded as `%2B`, ≤10 results, benign outer spaces trimmed; reject invalid/duplicate identities, control/bidi formatting and oversized or malformed wire data.
- Distinguish empty envelope, 403/429/503, cancellation and transport loss. One keyless GET; no selected-profile header, tracking POST or cold-launch cache of account identities.
- Player read: map all nine instrument bits in source order, restore accuracy scale, keep explicit FC, reject mixed-identity/corrupt rows, build a once-per-profile Songs lookup; map only the `-1` sentinel to nil. 202 is syncing even without a publication header and never becomes an empty card.
- Persist only a validated player ID and display name; scores are process-only and refetched under the current publication. Clear scores on retry, 202, failure, switch, deselect and generation change; reject late cross-identity results. A headerless (unpinned) response may be previewed but not selected.

## States

| State | Native acceptance |
|---|---|
| No profile | Profile action in every root and wide sidebar; it opens search |
| Profile action, player selected | Opens the selected player's Statistics, never search (issue #290) |
| Search | 250 ms debounce, loading, empty envelope, 403, Retry (only for error/empty) |
| Viewed result | Preview vs separate confirmed Select |
| Player selected | Identity persists; scores re-fetched; dependent Songs/Settings update |
| Band selected | Validated type/key/members, band rows — after a mutation-free read policy exists |
| Switch / deselect | Confirmation; clears earlier scores and nested routes; guarded tabs and focus restoration |
