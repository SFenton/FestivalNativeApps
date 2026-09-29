# First-run experiences — Android notes

> **What:** the Android carousel, seen-state store, shell seam, Settings replay and debug modes. **Read when:** touching onboarding, `core/firstrun/*`, `presentation/firstrun/*` or `ui/firstrun/*` on Android. Spec: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Core (`core/firstrun/`, pure Kotlin)

| File | Contents |
|---|---|
| `FirstRun.kt` | `FirstRunGateContext`, `FirstRunGate`, `FirstRunSlide`, `FirstRunHashing` (djb2 over **UTF-16 units** with 32-bit wraparound — bit-identical to the web `charCodeAt` loop, like Windows), `FirstRunSeenRecord`, `FirstRunSlideEvaluator` (strict `>` version, hash, gates, `ready`, `alwaysShow`, `allSlides`), `FirstRunMode.parse` |
| `FirstRunCatalog.kt` | 42 slides for the 9 web page keys, verbatim `firstRun.en.json` text; `FirstRunPageKey.forRoute` (`PlayerRoute` maps to `statistics`, as web `PlayerPage` serves both) |
| `FirstRunSeenStore.kt` | JSON blob in the settings DataStore key `fst.firstRun.seen.v1` (registered `Kept`): ≤500 records (oldest `seenAt` evicted), per-record validation, corrupt/oversized → empty |

## Copy variants

Android puts page actions in the top app bar, so it uses the web **desktop** ("header") copy for the variant slides (same `contentKey`s as mobile, so seen-state is shared). `songs-navigation` is the only width-dependent slide: bottom tabs on compact windows, "sidebar" (rail/drawer) otherwise. `shop-views` is omitted until Shop has a grid/list toggle.

## Center and UI

- `presentation/firstrun/FirstRunCenter.kt`: one per process (`AppContainer.firstRun`). `tryBegin` claims the single slot (web `activeCarouselKey`) under a mutex; the Shop page uses the fixed web context `{hasPlayer: false, shopHighlightEnabled: true}` (`ShopPage.tsx:141`); `beginReplay` resets the page, then shows every slide; `complete` marks every displayed slide seen once (stale carousels are no-ops).
- `ui/firstrun/FirstRunHost.kt`: the one shell seam. `firstRunPage(topEntry)` maps the visible back-stack destination to a page; 600 ms after the page settles (and whenever a gate input changes) it calls `tryBegin`. It is blocked while the profile or notifications sheet is open.
- `ui/firstrun/FirstRunCarousel.kt`: M3 `Dialog` card (full width on compact windows) with a `HorizontalPager`, white dots (current solid, others 35% white), "Slide x of y" (polite live region, no visible text), close ✕ and the footer (operator batch 6.7, same as Windows): **Next/Done, then Back** at the trailing edge; Back only after the first slide (never shown disabled); **no Skip** (the ✕ is the web's only early exit), so a one-slide guide shows only Done. Close, Done, system back and outside taps all complete. The slide title takes focus on each page.
- Seen state: closing marks **only the slides actually displayed** (`FirstRunCenter.complete(carousel, viewedCount)`; the pager moves one page at a time, so seen slides are a prefix). Unseen slides show on the next visit.
- `ui/firstrun/FirstRunDemos.kt`: static, synthetic mini-demos for **all 42 slides** (song rows, sort/metadata lists, nav replica, status icons, bar chart, rank/rival rows, stat grid, shop grid, pulsing Shop pills/rows). Pulses run only on the settled current page and never under reduce motion. Content-rotating web timers are collapsed to one representative state (as on iPhone).
- Settings replay rows: `fst.settings.first-run.<pageKey>` ([settings/android.md](../../pages/settings/android.md)).

## Debug

`FST_DEBUG_FIRST_RUN=off|on|force` (debug builds; default **off** so device automation is never blocked). Release always behaves as `on`. Settings replay works in every mode.

## IDs and evidence

`fst.first-run.dialog`, `.pager`, `.slide.<id>`, `.position`, `.close`, `.skip`, `.back`, `.next`, `.done`. Tests: `firstrun/FirstRunTest.kt` (Apple `FirstRunTests` port + center), `settings/SettingsUiTest.kt` (unseen-only first visit, no repeat, replay of all 9, every slide has a demo). Screenshot: `android/reports/screenshots/first-run-*.png`.

## Open

- Pages owned by other lanes get first-run automatically through the host; no per-screen registration is needed. Songs list-detail on expanded widths shows the Songs carousel even when a song is open in the detail pane.
