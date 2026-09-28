# Apple architecture

> **What:** how the shared Swift code is structured and the runtime invariants every Apple feature must keep. **Read when:** adding Apple code, a network read, a cache or a shared component. Folder ownership per lane: [PROGRESS.md §1](../../../PROGRESS.md).

## Layout

| Path | Contents |
|---|---|
| `apple/Sources/FestivalCore` | URLSession wire models, publication consistency (pin / 409 retry / 304 ETag), session cache, policies (`SongShopFilter`, `SongPlayerScoreFilter`, `SongInstrumentStatusPolicy`, …). New domains go in `FestivalAPI+<Domain>.swift` |
| `apple/Sources/FestivalDesign` | Generated `BrandTokens.swift` ([tokens](../../design/fluent.md)), `FestivalText` (text colour rule), branded controls (difficulty meter) |
| `apple/Sources/FestivalUI/App` | `AppRoute`, `AppRouteDestination`, `FestivalTabStack` (orchestrator); `FestivalRootView`, `Shell/*`; `FestivalSession` (+ `FestivalSession+<Feature>.swift`) |
| `apple/Sources/FestivalUI/{Background,Common,Design}` | Animated background host; status views; `festivalGlass`, `FestivalSectionHeader`, `InstrumentIcon`, `StarRating` |
| `apple/Sources/FestivalUI/Features/<Feature>` | One folder per page family (Songs, SongDetail, Shop, Profile, Leaderboards, SongLeaderboard, Settings, Rivals, …) |
| `apple/Apps/{iOS,macOS}`, `apple/Apps/*UITests` | App entry points and XCUITests (UITests frozen during Wave 1) |
| `apple/Tests/{FestivalCoreTests,FestivalDesignTests,FestivalUITests}` | SwiftPM tests; hosted snapshot helpers in `FestivalUITests` |

Separate navigation shells for iOS/iPadOS and macOS share Core, Design and screen state. Deployment targets: iOS 17, macOS 14.

## Runtime invariants

- **Network:** keyless public HTTPS by default; fixture origin only by explicit Debug override ([build-and-run](build-and-run.md), [service safety](../service-safety.md)).
- **One request path:** every service GET goes through `FestivalAPI.send(_:)` (`FestivalAPI+Request.swift`): keyless guard (rejects `X-API-Key`, `x-fst-selected-*`, non-GET), 30 s timeout, cancellation checks, then `mapStatus` (2xx; 202 syncing only where the endpoint accepts it; 404; 503 → `publicReadFrozen`/`unavailable` with `Retry-After`). Pinned reads use `read(_:)` (`PublicEndpoint`); unpinned reads use `fetch`/`fetchJSON` (`OperationalEndpoint`, `RivalsEndpoint`). **Add endpoints via the [add-endpoint skill](../../skills/add-endpoint.md); never create another `URLSession` or call `transport.send` directly.**
- **Errors:** screens store `ServiceIssue(error)` and render `ServiceStatusView` / `ServiceStatusInline` ([service-status](../../controls/service-status/ios.md)); they never switch on HTTP codes.
- **Online-only:** in-process caches for speed are fine; do not build offline/warm-cache disclosure UX. Existing publication guards (`SongShopPublicationPolicy`, `SongRelatedPublicationPolicy`) stay; new features should not add provenance machinery.
- **Publication joins:** Shop-derived state and the selected-player score index each record their observed publication; catalogue, related data and session must agree before decorating Songs rows. On mismatch show a readable paused state rather than hiding, reordering or badging older rows. An observed ID is not response-header proof.
- **Caches (process-only):** `SessionResponseCache` holds publication-bound ETag responses; typed-and-validated headerless snapshots are bounded (16 MB / 128 entries), never sent as conditional ETags, and cleared when another publication is observed. `ArtworkCache` = 32 MB evictable `NSCache` + strongly held 16 MB / 64-URL recent LRU (evictable-only lost visible Shop covers on route re-entry) + 24 MB decoded thumbnails; all cleared on a known publication change; never persisted to disk; never replace a failed image with success-shaped data. CHOpt PNGs: 32 MB / 16-entry LRU, 8 MB per response before caching.
- **Cancellation:** check cancellation before any cache mutation and again inside the cache actor, so a cancelled older reply cannot overwrite a newer one or poison the next 304.
- **Accessibility settings:** the app may expose additive Reduce Motion / Contrast / Transparency / artwork-animation overrides; it never toggles VoiceOver.

### Per-entity screens

A screen showing one account, band or rival must reset its state when that entity changes. It must never draw, or accept a late response for, a different entity.

- **Key identity with the entity.** Apply `.id(entityId)` wherever the entity can change under a surviving view: `AppRouteDestination` does this for `.player`/`.playerBands` (the viewed account) and for `.allRivals`/`.rivalDetail`/`.rivalry` (the selected account). `StatisticsScreen` keys `PlayerProfileContent` by `selected.accountId`, and the Rivals/Compete hubs key their sections by `session.selectedPlayer?.accountId`. `.id` must be applied by the *parent*: inside a view's own `body` it resets only children, not that view's `@State`.
- **Include the id in `task(id:)`**, and in any late-response guard key (`PlayerBandsScreen.RequestKey` carries `accountId`). `task(id:)` alone is not enough: it reloads *after* the new id has already rendered once with the old state. That is why `PlayerProfilePhase.shown(for:)` also refuses to draw a payload whose `accountId` differs.
- **Selected-player reads** (`FestivalSession+Rivals`) resolve `session.selectedPlayer` at call time. Their views must therefore key on the selected account, not just on instrument/scope.
- **Never cache the entity in session-level singletons.** `FestivalSession` holds only the *selected* identity and its score index, never a "last viewed" profile.

### List rows hold one action

Never put several default-style `Button`s or `NavigationLink`s in **one** `List`/`Form` row (e.g. a `LazyVStack` of results inside a single `Section` row). On iOS such a row makes the whole row the hit target and fires **every** control in it on one tap. This caused the 2026-09-28 wrong-account bug: tapping any profile search result pushed one `/player/:id` per result, leaving the *last* result's profile on top. Emit one row per action (`PlayerSearchResultRows` is a bare `ForEach`), or give intentionally side-by-side controls `.buttonStyle(.borderless)`/`.plain` (as `ProfileSelectionSheet.selectedProfileRow` does). macOS hosted tests cannot reproduce the iOS tap behavior, so `ProfileSearchResultRowsTests` pins the row structure via `_VariadicView`, and `ProfileJourneyTests` covers the tap on-device.

## Shared components and conventions

| Use | Not | Why |
|---|---|---|
| `StarRating(stars:gold:style:)` (`Design/StarRating.swift`; web `star_white`/`star_gold` in `Resources/Stars.xcassets`; 6 → five gold; `.inline` 14 pt or `.mini` web `MiniStars` circles) | SF Symbol `star`/`star.fill` | Operator rule (2026-09-28): stars use the game's own artwork everywhere |
| `ServiceStatusView(ServiceIssue(error), title:)` (`.title2`/`.body`, heading trait, opaque ≥44pt Retry, scrolls at large text, freeze countdown) | `ContentUnavailableView` or a bare message for service errors | iOS 26.5's system view failed Dynamic Type audits; one vocabulary for freeze/offline/syncing |
| `.refreshable` on the loaded List only | on an error `ScrollView` | Replacing an active refresh source can strand a spinner |
| Explicit scaled `frame` inside shared badges | SwiftUI `padding` inside the fixed score badge | Padding caused an iPad split-view layout loop ([score-accuracy](../../controls/score-accuracy/ipados.md)) |
| Accessibility IDs from the `product.json` registry | Ad-hoc IDs | `tools/verify_product.py` checks the registry |

Code style: DocC `///` with parameters/returns, `// MARK: -` regions, clarifying comments only.

## Text colour rule (operator rule, 2026-09-28)

**Text is white everywhere.** Use `FestivalText.primary` (`FestivalDesign/FestivalText.swift`) for titles, values, stat-tile captions, row subtitles (artist names, "N songs together"), descriptions, and empty-state or status messages. Only HIG de-emphasis uses `FestivalText.deemphasized` (muted blue-grey, ≥4.5:1 on app and card backgrounds but **fails over bright artwork** ([fluent.md](../../design/fluent.md)), so only inside opaque cards, sheets or lists): timestamps and dates, chart axis labels, text-field placeholders, and decorative glyphs (disclosure chevrons, search magnifier, clear buttons). `FestivalText.disabled` is for inactive controls. Do not use `.secondary`/`.tertiary`/`.gray` or raw `BrandTokens.textSecondary`/`textMuted` for text in feature code. Semantic colours (gold, status green/red, accent blue) are unaffected. `FestivalTextTests` pins white and the de-emphasis contrast.

Status countdowns, `FestivalSectionHeader` subtitles and the tab-accessory Search button stay primary because they can sit over artwork. Status (2026-09-28, Lane AP): applied to Profile, Statistics, Rivals, Compete (foreground only), Suggestions, Bands, Notifications, Search, `Common` and `Design`. Songs, Song Detail, Shop, Leaderboards/Song Leaderboard, Settings, First Run and What's New still use raw `BrandTokens.text*` and need the same sweep by their owning lanes.

## New content fades in as it loads (operator rule, 2026-09-28)

Loaded content never pops in: apply `.festivalFadeIn(isLoaded:)` (`Common/FadeInOnLoad.swift`) to the view that replaces a spinner, and `.festivalFadeIn(isLoaded:index:)` to list rows and card stacks. It ports the web's `fadeInUp` (opacity 0 → 1 while rising 12 pt, 400 ms CSS `ease-out`, `FADE_DURATION`) and `useStagger`/`getCardDelay` (125 ms per item; items past the first ~8 appear instantly). The fade plays once per view lifetime, is instant under system or in-app Reduce Motion, and is disabled in hosted snapshots (`\.festivalFadeInEnabled`, set by `NativeHostedRoot`). Put it on the loaded content, never on a container that also holds the spinner (the content is invisible until `isLoaded`). Applied to Suggestions, Profile/Statistics, Rivals, Compete, Bands, Player Bands and Notifications; other lanes adopt it on their pages. `festivalFadeInOnAppear()` (Lane W4) is the same as `festivalFadeIn(isLoaded: true)`.

## Loading indicators (operator rule)

Every spinner is `Common/FestivalLoadingView` (white, **no visible title/subtitle**; spoken label only). Never `ProgressView("…")` with text. Determinate progress bars (e.g. Paths image download) are exempt.
