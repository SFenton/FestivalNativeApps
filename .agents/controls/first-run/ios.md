# First-run experiences — iPhone notes

> **What:** the SwiftUI carousel, seen-state store and Settings replay as built, decisions and
> open gaps (Lane F). Spec: [spec.md](spec.md).

## Architecture

- **Core (pure logic, `FestivalCore/`):**
  - `FirstRun.swift` — `FirstRunGateContext`, `FirstRunGate` (enum predicate, not a closure, so
    slide definitions stay `Equatable`/`Sendable` and unit-testable), `FirstRunSlide` (data only —
    no `render`; the UI layer maps `id` to a view), `FirstRunHashing` (djb2, ported bit-for-bit
    from the web's `contentHash`), `FirstRunSeenRecord`, and `FirstRunSlideEvaluator` (the pure
    `isUnseen`/`unseenSlides`/`gatePassingSlides`/`allSlides` functions).
  - `FirstRunSeenStore.swift` — bounded (`maxRecords = 500`, oldest-`seenAt`-first eviction),
    validated `UserDefaults` JSON persistence (`fst.firstRun.seen.v1`). A fully-corrupt or
    oversized (>256 KB) blob resets to empty, matching the web's `catch { return {} }`;
    individually malformed records (negative version, empty/oversized hash or id) are dropped
    while the rest of the store is kept — stricter than the web, never weaker.
  - `FirstRunCatalog.swift` — the full, hand-ported slide catalog for all 9 registered pages
    (`FirstRunPageKey`: `songs`, `songinfo`, `playerhistory`, `statistics`, `suggestions`,
    `leaderboards`, `compete`, `rivals`, `shop` — the same `pageKey` strings the web registers
    from `SettingsPage.tsx`). Only the mobile copy variant is ported for slides that differ by
    `isMobile` on the web (this lane targets iPhone only); each keeps the web's `contentKey` so a
    future desktop port would share seen-state.
  - `FestivalCoreTests/FirstRunTests.swift` — 36 tests covering hashing, `isUnseen` (missing
    record, version bump, content-hash change, `contentKey` sharing, a defensive lower-stored-
    version case), slide selection (gates, `ready`, the "only the new slide shows" scenario,
    `alwaysShow`, `gatePassingSlides`, `allSlides`), and the seen store (round-trip, corrupt data,
    oversized payload, per-record validation, bounding/eviction, `resetPage`/`resetAll`).
- **UI (`FestivalUI/Features/FirstRun/`):**
  - `FirstRunCenter` (`@Observable`, `@MainActor`) — one per session, reached via
    `session.firstRunCenter` (added the same weakly-keyed-registry way as
    `FestivalSession+Artwork.swift`'s `backgroundCoordinator`, so no edit to
    `FestivalSession.swift` itself was needed). Owns the `FirstRunSeenStore` and arbitrates the
    single `activeKey` ("one carousel at a time") via `claim`/`release`. Also resolves
    `FirstRunDebugMode` from `FST_DEBUG_FIRST_RUN` once at session start.
  - `.firstRun(page:session:)` (`FirstRunModifier.swift`) — the one seam every page needs.
    Evaluates gates from live `@AppStorage` settings + `session.selectedPlayer` on appear and on
    every relevant setting/profile change, presents a `.sheet` when unseen gate-passing slides
    exist and the shared slot can be claimed, and marks them seen (releasing the slot) in the
    sheet's `onDismiss` — so a swipe-to-dismiss is handled identically to tapping Skip/Done.
  - `FirstRunCarouselView.swift` — the paged carousel: `TabView(.page)` (iOS-only; macOS falls
    back to the default style purely so `swift test` keeps compiling on the host Mac — this
    carousel never actually presents on macOS since Apple's build order ports iPhone first),
    close (✕) button, Skip/Next/Done controls, and a combined VoiceOver announcement per slide
    (`accessibilityValue = "Slide x of y"`) with `@AccessibilityFocusState` moving focus to the
    new slide's content on every index change (button-driven or swipe). `withAnimation` calls for
    the Next/Done transition are skipped under `accessibilityReduceMotion` — there is no
    web-style per-line stagger animation to gate in the first place.
  - `FirstRunDemoContent.swift` / `Demo/FirstRunSongsDemos.swift` — see the parity table below.
  - `FirstRunSettingsSection.swift` — the Settings "First-Run Guides" section: one "Show" row per
    `FirstRunPageKey`, opening a carousel over `FirstRunSlideEvaluator.allSlides(...)` (gates and
    seen-state both ignored, matching `getAllSlides`), resetting that page's seen-state first
    (matching `useFirstRunReplay.open`'s `resetPage` call) and re-marking everything seen on
    dismiss. No "reset all" control — the web doesn't have one either.
- **Debug:** `FST_DEBUG_FIRST_RUN` — unset/anything else → `.off` in DEBUG (default, so other
  lanes' `ios_sim.py shot`/`drive` scripts aren't blocked by an unexpected sheet); `force` → shows
  every gate-passing slide on every page regardless of seen-state; `on` → real seen-state
  behavior in DEBUG. Release always behaves as `.normal` (real behavior), ignoring the env var
  entirely. No `FST_DEBUG_FIRST_RUN` handling existed anywhere on `master` at the time this landed
  (checked via `git log`/`grep` before starting), so there was nothing to reconcile with Lane X.

## Seam edits (narrow, additive)

- `App/AppRouteDestination.swift` — `.firstRun(...)` appended to the 8 registered-page cases in
  the `switch` (`songDetail → .songInfo`, `playerHistory → .playerHistory`, `statistics`,
  `suggestions`, `leaderboards`, `compete`, `rivals`, `shop`); every other case (song leaderboards,
  player/band pages, rankings, licenses, …) is untouched — the web doesn't register those either.
- `App/FestivalRootView.swift` — the same 6 pages that are *also* tab roots (`songs`, `suggestions`,
  `leaderboards`, `compete`, `rivals`, `statistics`) get `.firstRun(...)` on their tab-root
  composition in `content(for:)` too, since reaching them as a tab never goes through
  `AppRouteDestination`. `FirstRunCenter.claim`/`release` make it safe for both the tab-root and a
  pushed-route instance of the same page to carry the modifier — only whichever is actually
  visible ever calls `onAppear`/succeeds at `claim` in practice.
- `App/FestivalSession+FirstRun.swift` — new file, following the established
  `FestivalSession+<Feature>.swift` convention; adds `session.firstRunCenter` without touching
  `FestivalSession.swift`.
- `Features/Settings/SettingsScreen.swift` — one line added to the section list:
  `FirstRunSettingsSection(session: session)`.

## Songs slide parity (9/9 — all with live native demos)

| Slide id | Live demo | Notes |
|---|---|---|
| `songs-song-list` | Yes (`FirstRunSongListDemo`) | 3 static demo rows on glass cards |
| `songs-sort` | Yes (`FirstRunSortDemo`) | Sort-mode list + direction indicator |
| `songs-navigation` | Yes (`FirstRunNavigationDemo`) | Compact tab-bar replica |
| `songs-filter` | Yes (`FirstRunFilterDemo`) | Instrument row + two toggle rows |
| `songs-icons` | Yes (`FirstRunSongIconsDemo`) | `InstrumentIcon` + FC/played/unplayed/not-charted badges |
| `songs-metadata` | Yes (`FirstRunMetadataDemo`) | Song card + metadata pill row |
| `songs-shop-highlight` | Yes (`FirstRunShopBadgeDemo(.highlight)`) | Gold glow + sparkles badge |
| `songs-new-in-shop` | Yes (`FirstRunShopBadgeDemo(.new)`) | Same gold treatment as "new" |
| `songs-leaving-tomorrow` | Yes (`FirstRunShopBadgeDemo(.leaving)`) | Red glow + clock badge |

These reuse real design primitives (`InstrumentIcon`, `festivalGlass`, `BrandTokens`) with a
small static demo-song pool (no network/session dependency, matching the web's own hardcoded
first-run demo data) rather than instantiating the full `SongRowView`/`FestivalSession` graph —
a lighter-weight but faithful-looking equivalent. Reusing the literal `SongRowView` type is a
possible future refinement, not required for a first pass.

## Other pages (31 slides) — static illustration, live demos are a follow-up

Song Info (8), Player History (2), Statistics (6), Suggestions (4), Leaderboards (3), Compete (3),
Rivals (3) and Item Shop (4, `shop-views` intentionally omitted — this lane's Shop screen has no
grid/list view toggle yet) all render `FirstRunStaticIllustration`: a page-themed SF Symbol on a
glass card. The slide's real title/description (shown below it by the carousel) still carries the
actual explanation; only the interactive/live preview is deferred. Porting each of these ~31
web demo components (`pages/<page>/firstRun/demo/*.tsx`) to a native mini-view is real, but
separable, follow-up work — flagged rather than attempted wholesale in this pass so the core
seen-state/gate/replay machinery (the part the operator's request was actually about) landed with
full test coverage instead of being crowded out.

## Known gaps / follow-ups

- Live demos for the 31 non-Songs slides (see above).
- `shop-views` slide omitted pending the Shop grid/list view toggle (add it back to
  `FirstRunCatalog.shop` once that toggle ships).
- `ready` is always `true`: `FestivalSession` resolves the selected-player identity synchronously
  from storage at init, so there's no async gap where gates could evaluate against stale data on
  this platform. Revisit if a future async gate dependency is added.
- No XCUITest coverage yet for the carousel or replay flow (Wave 1 is unit + visual smoke only,
  per `PROGRESS.md` §3); `fst.firstRun.close/skip/next/done` and
  `fst.settings.first-run.<page>` accessibility identifiers are in place for when that lands.
- `contracts/product.json` has no `first-run` control entry yet (orchestrator-owned file, not
  edited by this lane) — `check_docs.py` reports the same pending "topic not in contracts"
  warning that `songs-section-index` already has on `master`.
