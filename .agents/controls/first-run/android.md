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
- `ui/firstrun/FirstRunCarousel.kt`: the shared compact `FestivalModalDialog` (`ui/common/FestivalModal.kt`, issue #23) headed by the page label (`fst.first-run.title`, a heading in the shared **Title Large** modal header like What's New and Notifications; before issue #147 it alone overrode it with Label Large; `paneTitle` "Feature tour: <page>", which TalkBack announces on open, including a Settings replay; verified for issues #24 and #147) and the standard Close icon button, with a `HorizontalPager`, white dots (current solid, others 35% white), "Slide x of y" (polite live region, no visible text) and the footer, ordered as Material 3 dialog actions (issue #25, superseding operator batch 6.7's "Next/Done before Back" on Android): **Back, then Next/Done** at the trailing edge, so the confirming action is always last and Next/Done never moves when Back appears (before #25 Next jumped left on page 2 and Back took its spot, so a quick second tap went back). Back only after the first slide (never shown disabled); **no Skip** (the Close icon button is the one-tap early exit), so a one-slide guide shows only Done. Every control is a 48 dp Material button (Close `IconButton`, Back `TextButton`, Next/Done filled `Button`); TalkBack reads Close → slide heading → description → "Slide x of y" → Back → Next/Done, each as "<name>, Button" (`talkback_walk.py`, 2026-10-02). Close, Done, system back and outside taps all complete. The slide title takes focus on each page.
- **Window fit (issue #139):** the tour is always the full-width dialog (16 dp margins, at most 560 dp — M3 "Centered dialog (max 560dp wide)"); `usePlatformDefaultWidth` would measure it at the platform's preferred dialog width (≈320 dp on a landscape phone). Inside, `FirstRunSlideLayout` picks the slide layout from the dialog body's own size: **stacked** (demo above a centred title/description, dots above the footer) unless the body is shorter than 480 dp *and* at least 480 dp wide, then **side by side** (`fst.first-run.layout.side-by-side`: demo at 45% width scaled down to fit — never below 40% — beside a start-aligned, vertically scrolling title/description; dots move to the start of the footer row). This keeps the title, description, dots and buttons in view on landscape phones, folded landscape and tabletop. The decorative demo (`fst.first-run.demo`, hidden from TalkBack) always draws at font scale 1.0, so large text no longer clips its rows; the title and description still scale with the system font. On a half-open foldable (separating hinge) the dialog sits on the wider side of a vertical hinge (leading on a tie) or below a horizontal one (`FestivalModalDialog(avoidHinge = true)`, `core/nav/DialogHinge.kt`; M3 "Never place interactive content or critical information across the hinge area"); a tap on the other side still dismisses it. The activity handles density changes itself (`configChanges`), and a display-size change removed the dialog's window while Compose still held it, so `FestivalModalDialog` keys its `Dialog` on `densityDpi` (state hoisted outside the dialog, such as the tour's pager, survives).
- Seen state: closing marks **only the slides actually displayed** (`FirstRunCenter.complete(carousel, viewedCount)`; the pager moves one page at a time, so seen slides are a prefix). Unseen slides show on the next visit.
- `ui/firstrun/FirstRunDemos.kt`: mini-demos for **all 42 slides** (song rows, sort/metadata lists, nav replica, status icons, bar chart, rank/rival rows, stat grid, shop grid, pulsing Shop pills/rows). Every song demo (including Statistics' top/bottom songs) shows real catalogue songs with art from `core/firstrun/FirstRunDemoSongs.kt` (web `useDemoSongs`/`useItemShopDemoSongs`, Apple `FirstRunDemoSongs`): Shop demos prefer the loaded Shop only when its observed publication matches the catalogue's, then "Epic Games" artists, then any song, in catalogue order. `FirstRunHost` reads the memoized `FestivalApi.catalog()` (never fetches the Shop) into `LocalFirstRunDemoCatalog`; while it loads or fails the demos show muted redacted bars (`fst.first-run.demo.placeholder`), never invented songs. Players, ranks and percentiles stay fictional like web. Pulses run only on the settled current page and never under reduce motion. The 12 web content-rotating slides rotate like web (next bullet).
- **Data-swap rotation (issue #58):** the 12 web-rotating slides (`FirstRunRotatingDemos.IDS`: `songs-song-list`, `songs-icons`, `songs-metadata`, `statistics-top-songs`, `songinfo-bar-select`, `suggestions-category-card`, `leaderboards-experimental-metrics`, `compete-hub`, `compete-rivals`, `rivals-overview`, `rivals-instruments`, `rivals-detail`) render through `ui/firstrun/FirstRunRotatingDemos.kt`. Core `core/firstrun/FirstRunDemoRotation.kt` holds the web timing (`FirstRunDemoTiming`: 5 s interval, 400 ms CSS-`ease` fade out → swap while hidden → 400 ms fade in; bar-select 2.5 s / 300 ms; card 8 dp drop, hub 6 dp rise, rival groups 4 dp drop), the web swap-count table with deterministic SplitMix64 row picks (never the same set twice running) and duplicate-free pool walks; `FirstRunDemoData.kt` holds the web pools (rankings, rivals, instrument rivals, KeyDrifter categories, metadata, suggestion templates, experimental metrics, bars). Song rows draw from `FirstRunDemoSongs.rotationPool` (the same `pick` over `LocalFirstRunDemoCatalog`, up to 40 songs); until the catalogue arrives they are redacted placeholders (`FirstRunDemoSong.isPlaceholder`) that **hold still** (song tickers need a real pool), while non-song parts (rivals, categories, metrics, bars) keep rotating. `DemoTicker` runs only for the settled current page while the activity is RESUMED and Data Saver is off (Data Saver also skips artwork); leaving mid-fade completes the swap. Reduce motion (app setting or system Remove animations) keeps rotating but each changed part is a simple `Crossfade` (instant when the animator scale is 0). Not ported: rivals-detail's per-row 100 ms re-stagger (the slot fades together); pool order is catalogue order, not a random shuffle. Tests: `firstrun/FirstRunDemoRotationTest.kt`, `firstrun/FirstRunRotatingDemoUiTest.kt`.
- Settings replay rows: `fst.settings.first-run.<pageKey>` ([settings/android.md](../../pages/settings/android.md)).

## Debug

`FST_DEBUG_FIRST_RUN=off|on|force` (debug builds; default **off** so device automation is never blocked). Release always behaves as `on`. Settings replay works in every mode.

## IDs and evidence

`fst.first-run.dialog`, `.title`, `.pager`, `.slide.<id>`, `.position`, `.close`, `.skip`, `.back`, `.next`, `.done`, `.layout.stacked` / `.layout.side-by-side`, `.demo`. Tests: `firstrun/FirstRunTest.kt` (Apple `FirstRunTests` port + center), `firstrun/FirstRunStatesUiTest.kt` (every spec state through `FirstRunHost` — `hidden-all-seen`, `new-slides-only`, `gated`, `waiting-not-ready`, `replay-all`, `dismissed`; both slide layouts; the hinge side and outside tap; the layout policy), `firstrun/FirstRunDemoCatalogHostTest.kt` (the host's demo catalogue: loading → songs, failure, Shop preference, hidden Shop, publication mismatch), `core/nav/DialogHingeTest.kt`, `settings/SettingsUiTest.kt` (unseen-only first visit, no repeat, replay of all 9, every slide has a demo), and the connected `journeys/FirstRunJourneyTest.kt` (`new-slides-only` → `dismissed`, `hidden-all-seen` → `replay-all` with ATF, layout and hinge checks on the device window). Screenshot: `android/reports/screenshots/first-run-*.png`.

## Validation (issue #139, 2026-10-04)

Live public service, debug build with `FST_DEBUG_FIRST_RUN=force`, animator scale 0 (reduced motion) except the motion recording. The app is dark-only (brand `darkColorScheme`), so the system light theme renders identically by design.

| Configuration | Before | After |
|---|---|---|
| FST_Phone portrait, font 1.0 / 2.0 | font 2.0 clipped the third demo row (fixed 220 dp box) | stacked; demo drawn at font 1.0, unclipped |
| FST_Phone landscape, font 1.0 / 2.0 | ≈320 dp-wide platform dialog: demo clipped, title/description below the fold | side by side; at 2.0 the description scrolls, title/dots/buttons stay in view |
| FST_Tablet portrait / landscape, font 1.0 / 2.0 | font 2.0 demo clipping | stacked 560 dp dialog, unclipped |
| FST_Book_Fold folded portrait / landscape, font 1.0 / 2.0 | as phone | as phone (side by side in landscape) |
| FST_Book_Fold unfolded, font 1.0 / 2.0 | fine | stacked, centred (flat fold is not separating) |
| FST_Book_Fold half-open (book) and rotated (tabletop) | dialog centred across the hinge | wider side of the hinge / below it; outside tap on the other side dismisses |
| FST_Passport_Fold folded portrait / landscape, unfolded, half-open, font 1.0 / 2.0 | as phone / across the hinge | stacked or side by side as above; half-open stays beside the hinge |
| FST_TriFold folded / partial / unfolded, font 1.0 / 2.0 | — | stacked, unclipped |
| FST_Resizable phone / foldable / tablet / desktop (compact, medium, expanded) | a display-density change (foldable → tablet, desktop → phone) removed the dialog window while the carousel stayed active: no tour, and What's New blocked until restart | the dialog reopens in a new window per density (`FestivalModalDialog`), on the same slide; stacked at every preset |

Accessibility: the connected journeys run ATF on every state (no errors) and assert nothing straddles a separating hinge; reading order is unchanged (Close → heading → description → position → Back → Next/Done); every control is a 48 dp Material button; the white-on-card text and dots keep their contrast. Material 3 review (`material-3` skill, Compose guidance): centred dialog ≤ 560 dp, 28 dp corners, actions trailing with the confirming action last, 48 dp targets, nothing across a separating hinge. Deliberate deviations: full-width centred dialog rather than a full-screen dialog on compact windows (issue #23), no Skip (issue #25), white dots (operator batch 6.7), the decorative demo ignores the font scale (its text is hidden from TalkBack; the readable title and description scale).

## Validation (issue #147, 2026-10-04): modal title

Live public service, debug build with `FST_DEBUG_FIRST_RUN=force` (Songs) plus a Settings replay (Leaderboards), dark-only app as above. Finding: the header title was the only modal title in Label Large (14 sp), so it was not styled like the app's other modals; it now uses the shared Title Large header (`FirstRunCarousel.kt`).

| Configuration | Result after the fix |
|---|---|
| FST_Phone portrait / landscape, font 1.0 / 2.0 | page name beside Close; Close stays 48 dp at the trailing edge; Next in view (landscape 2.0: side by side, description scrolls) |
| FST_Tablet portrait / landscape, font 1.0 / 2.0 | as phone, 560 dp stacked dialog |
| FST_Resizable phone / foldable / tablet / desktop | as phone at every preset |
| FST_Book_Fold and FST_Passport_Fold folded (portrait/landscape), unfolded, half-open, font 1.0 / 2.0 | as phone; half-open stays on one side of the hinge |
| FST_TriFold folded / partial / unfolded, font 1.0 / 2.0 | as phone |
| TalkBack (FST_Phone) | opening the forced Songs tour says "Feature tour: Songs"; a Settings replay says "Feature tour: Leaderboards"; then "<page>, Heading" → Close, Button → slide heading → description → "Slide 1 of 6" → Next, Button |

Material 3 (`material-3` skill, typography and shape): "Top app bar title | Title Large"; the M3 basic dialog's headline is Headline Small, but here the slide title below already uses Headline Small and the header pairs with a Close icon like a full-screen dialog / app bar, so the header keeps the app's shared Title Large modal style (deliberate). At font 2.0 the header grows about 8 dp; the slide layout adapts. Tests: `FirstRunCarouselUiTest` (every page's title text, heading, Title Large size and pane title; title beside Close at font 2.0 portrait and landscape) and the connected `FirstRunJourneyTest` (`assertTitled`), passing on FST_Phone and FST_Book_Fold half-open.

## Validation (issue #152, 2026-10-04): Close control

Check of #44 (first-run dismiss control must be the native one that matches the app's other modals). Finding: already compliant, so there is no UI change. `FirstRunCarousel` uses the shared `FestivalModalDialog` header, whose `FestivalModalCloseButton` is the stock M3 `IconButton` + `Icons.Filled.Close` (24 dp icon, 48 dp target, label "Close", tag `fst.first-run.close`). It is the same control as Profile (`fst.profile.close`), What's New, Paths, Notifications and Quick Links. Live public service, debug build with `FST_DEBUG_FIRST_RUN=force` (Songs tour); the UIAutomator bounds of the clickable Close node at each density:

| Configuration | Close target | Close tap | System Back | Esc |
|---|---|---|---|---|
| FST_Phone portrait 1.0 (dark and system light), 2.0; landscape 1.0, 2.0 | 126 px @420 = 48 dp | dismissed | dismissed | dismissed (portrait 1.0, landscape 2.0) |
| FST_Tablet landscape / portrait, font 1.0 / 2.0 | 96 px @320 = 48 dp | dismissed | dismissed | dismissed (landscape 1.0) |
| FST_Resizable phone 1.0 / 2.0 (compact), foldable (medium), tablet (expanded), desktop 1.0 / 2.0 (expanded) | 126 px @420, 72 px @240, 48 px @160 = 48 dp | dismissed | dismissed | dismissed (desktop 1.0) |
| FST_Book_Fold folded portrait 1.0 / 2.0, folded landscape, unfolded 1.0 / 2.0, half-open | 117 px @390 = 48 dp | dismissed | dismissed | dismissed (half-open; dialog on one side of the hinge) |
| FST_Passport_Fold folded portrait, folded landscape 2.0, unfolded 1.0 / 2.0, half-open | 126 px @420 = 48 dp | dismissed | dismissed | dismissed (half-open) |
| FST_TriFold folded, partial, unfolded 1.0 / 2.0 | 96 px @320 = 48 dp | dismissed | dismissed | dismissed (unfolded 1.0) |

The Close icon stays at the header's trailing edge and is never clipped at font 2.0. The app is dark-only, so the system light theme looks the same. TalkBack reads the merged node as "Close, Button": the label sits on the child `Icon`, so UIAutomator shows an empty `content-desc` on the clickable parent. Material 3 (`material-3` skill, Compose guidance): icon-only buttons need a label and a "Minimum touch target 48x48dp" (`component-catalog.md`); dialogs are "Centered dialog (max 560dp wide)" on medium+ windows (`layout-and-responsive.md`). The deliberate deviations listed under #139 still apply. Tests: `FirstRunCarouselUiTest` (Close is a named 48 dp button; closing marks the viewed slides seen) and the connected `FirstRunJourneyTest`, which adds `systemBackDismissesAndMarksTheDisplayedSlidesSeen` and `escapeDismissesAndMarksTheDisplayedSlidesSeen` (4/4 on FST_Phone).

## Validation (issue #165, 2026-10-05): demo songs

Check of #57: first-run song demos, including Statistics' highest/lowest-ranked songs (`statistics-top-songs`), must show real catalogue songs, with placeholders while the catalogue is loading or unavailable. Finding: already compliant on every configuration, so there is no UI change; no invented title remains in `ui/firstrun/`. Live public service, debug build with `FST_DEBUG_FIRST_RUN=force` (Statistics, selected `SFentonX` held in memory only, never sent as a header) at animator scale 0, unless noted.

| Configuration | Result |
|---|---|
| FST_Phone portrait / landscape, font 1.0 / 2.0 | `statistics-top-songs` shows real Epic Games songs with art and fictional Top x% pills; landscape is side by side |
| FST_Phone system light theme | identical (the app is dark-only) |
| FST_Phone airplane mode | muted placeholder bars that hold still; no percentile pills; non-song demos (stat grid) still render |
| FST_Phone Songs, Suggestions, Rivals and Shop tours | real songs; the Shop grid shows placeholders for about 10–20 s on a cold debug start, then real Shop songs |
| FST_Tablet portrait / landscape, font 1.0 / 2.0 | real songs, stacked 560 dp dialog |
| FST_Resizable phone / foldable / tablet / desktop (compact, medium, expanded), font 1.0 / 2.0 | real songs at every preset |
| FST_Book_Fold folded / unfolded, font 1.0 / 2.0 | real songs |
| FST_Passport_Fold folded / unfolded, font 1.0 / 2.0 | real songs |
| FST_TriFold folded / partial / unfolded, font 1.0 / 2.0 | real songs |
| FST_Phone with animations on (recording) | song rows rotate through catalogue songs every 5 s with the web fade |

The placeholder time is the time to decode and validate the full catalogue: the public `/api/songs` download takes under a second, and the work runs on `Dispatchers.Default`. It shows on a cold debug start in the emulator, and it is the specified loading state (web shows the same skeleton). At font 2.0 on narrow windows the description scrolls under the fixed demo, as documented for #139; the demo itself is drawn at font 1.0 and hidden from TalkBack, so it never clips. Material 3 (`material-3` skill, Compose guidance): outlined card rows ("Surface fill, outline-variant border"), the "Centered dialog (max 560dp wide)", 48 dp targets on every control and 4.5:1 text contrast on the dark surface. The #139 deviations still apply. Test added: `firstrun/FirstRunDemoCatalogHostTest.kt` covers the host's catalogue wiring, which full-app tests cannot reach because the demo is hidden from semantics: placeholders while loading, then catalogue songs; a failed load keeps placeholders; the Shop is preferred only for a matching, visible Shop; a hidden Shop or a newer publication ignores the Shop feed.

## Open

- Pages owned by other lanes get first-run automatically through the host; no per-screen registration is needed. Songs list-detail on expanded widths shows the Songs carousel even when a song is open in the detail pane.
