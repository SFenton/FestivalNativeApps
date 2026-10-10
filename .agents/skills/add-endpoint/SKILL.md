---
name: add-endpoint
description: Add a keyless public service read to a native client safely (allowlist, wire format, fixtures). Use when a page needs a new service endpoint.
---

# Skill: add a service endpoint (Apple)

> **What:** the procedure for adding a keyless public GET to `FestivalCore` through the one shared request path. **Read when:** a feature needs data from a service route the client does not read yet.

1. **Prove it is safe.** Read the route in `~/repos/FortniteFestivalLeaderboardScraper/FSTService/Api/*Endpoints.cs` and every persistence call it reaches; it must only `SELECT` or read caches. No `RequireAuthorization()`, no registration/tracking side effects. Add or update its row in the [endpoint allowlist](../../platforms/service-safety.md#endpoint-allowlist) with the file:line evidence. Blocked routes stay blocked.
2. **Choose the path.**
   - Publication-bound catalogue/score data → add a case to `PublicEndpoint` (`FestivalAPI.swift`) and read with `read(_:)`; set `acceptsSyncing` if it documents a 202 envelope and `allowsSnapshotCache` false for personal account data (profile, history, notifications, a player's bands, reads carrying a selected player's `accountId`). Public board data about a viewed account (`/api/rankings/{instrument}/{accountId}[/history]`) stays cacheable so it survives a scrape freeze ([empty-error-states](../../patterns/empty-error-states.md) R9).
   - Unpinned data (Rivals-like, operational) → add a case to `RivalsEndpoint`/`OperationalEndpoint` or a new enum conforming to `ServiceEndpoint`, and read with `fetchJSON(_:as:invalid:)`.
   - Never create a `URLSession`, call `transport.send` directly or add headers other than the helper's; `send(_:)` rejects `X-API-Key`, `x-fst-selected-*` and non-GET.
3. **Build the URL** from individually validated segments (account IDs via `ProfileSearchText.isValidAccountId`, no `/` in segments, bounded paging) and throw the domain's `invalidResource` otherwise.
4. **Model the wire** in `FestivalCore/<Domain>.swift`: `Decodable & Sendable`, optional fields for every documented variant (precomputed vs fallback payloads differ). Normalize documented "none yet" 404s to an empty value in the wrapper (`catch FestivalAPIError.httpStatus(404)`), never other statuses.
5. **Expose** one `public func` in `FestivalAPI+<Domain>.swift` with DocC (source cite, side-effect proof, Parameters/Returns/Throws).
6. **Fixture + tests.** Add a synthetic, captured-shape fixture in `contracts/fixtures/` (no production IDs or names). In `FestivalCoreTests`, decode it through a fake `HTTPTransport`, assert the URL, and cover the 404/503-freeze paths. See `ServiceRequestTests.swift`.
7. **UI** stores `ServiceIssue(error)` and renders the [service-status](../../controls/service-status/ios.md) views.
