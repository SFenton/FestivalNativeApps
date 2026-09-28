# Apple architecture

> **What:** how the shared Swift code is structured and the runtime invariants every Apple feature must keep. **Read when:** adding Apple code, a network read, a cache or a shared component. Folder ownership per lane: [PROGRESS.md §1](../../../PROGRESS.md).

## Layout

| Path | Contents |
|---|---|
| `apple/Sources/FestivalCore` | URLSession wire models, publication consistency (pin / 409 retry / 304 ETag), session cache, policies (`SongShopFilter`, `SongPlayerScoreFilter`, `SongInstrumentStatusPolicy`, …). New domains go in `FestivalAPI+<Domain>.swift` |
| `apple/Sources/FestivalDesign` | Generated `BrandTokens.swift` ([tokens](../../design/fluent.md)), branded controls (difficulty meter) |
| `apple/Sources/FestivalUI/App` | `AppRoute`, `AppRouteDestination`, `FestivalTabStack` (orchestrator); `FestivalRootView`, `Shell/*`; `FestivalSession` (+ `FestivalSession+<Feature>.swift`) |
| `apple/Sources/FestivalUI/{Background,Common,Design}` | Animated background host; status views; `festivalGlass`, `FestivalSectionHeader`, `InstrumentIcon` |
| `apple/Sources/FestivalUI/Features/<Feature>` | One folder per page family (Songs, SongDetail, Shop, Profile, Leaderboards, SongLeaderboard, Settings, Rivals, …) |
| `apple/Apps/{iOS,macOS}`, `apple/Apps/*UITests` | App entry points and XCUITests (UITests frozen during Wave 1) |
| `apple/Tests/{FestivalCoreTests,FestivalDesignTests,FestivalUITests}` | SwiftPM tests; hosted snapshot helpers in `FestivalUITests` |

Separate navigation shells for iOS/iPadOS and macOS share Core, Design and screen state. Deployment targets: iOS 17, macOS 14.

## Runtime invariants

- **Network:** keyless public HTTPS by default; fixture origin only by explicit Debug override ([build-and-run](build-and-run.md), [service safety](../service-safety.md)).
- **Online-only:** in-process caches for speed are fine; do not build offline/warm-cache disclosure UX. Existing publication guards (`SongShopPublicationPolicy`, `SongRelatedPublicationPolicy`) stay; new features should not add provenance machinery.
- **Publication joins:** Shop-derived state and the selected-player score index each record their observed publication; catalogue, related data and session must agree before decorating Songs rows. On mismatch show a readable paused state rather than hiding, reordering or badging older rows. An observed ID is not response-header proof.
- **Caches (process-only):** `SessionResponseCache` holds publication-bound ETag responses; typed-and-validated headerless snapshots are bounded (16 MB / 128 entries), never sent as conditional ETags, and cleared when another publication is observed. `ArtworkCache` = 32 MB evictable `NSCache` + strongly held 16 MB / 64-URL recent LRU (evictable-only lost visible Shop covers on route re-entry) + 24 MB decoded thumbnails; all cleared on a known publication change; never persisted to disk; never replace a failed image with success-shaped data. CHOpt PNGs: 32 MB / 16-entry LRU, 8 MB per response before caching.
- **Cancellation:** check cancellation before any cache mutation and again inside the cache actor, so a cancelled older reply cannot overwrite a newer one or poison the next 304.
- **Accessibility settings:** the app may expose additive Reduce Motion / Contrast / Transparency / artwork-animation overrides; it never toggles VoiceOver.

## Shared components and conventions

| Use | Not | Why |
|---|---|---|
| `ServiceUnavailableView` (`.title2`/`.body`, heading trait, opaque ≥44pt Retry, scrolls at large text) | `ContentUnavailableView` for service errors | iOS 26.5's system view failed Dynamic Type audits |
| `.refreshable` on the loaded List only | on an error `ScrollView` | Replacing an active refresh source can strand a spinner |
| Explicit scaled `frame` inside shared badges | SwiftUI `padding` inside the fixed score badge | Padding caused an iPad split-view layout loop ([score-accuracy](../../controls/score-accuracy/ipados.md)) |
| Accessibility IDs from the `product.json` registry | Ad-hoc IDs | `tools/verify_product.py` checks the registry |

Code style: DocC `///` with parameters/returns, `// MARK: -` regions, clarifying comments only.
