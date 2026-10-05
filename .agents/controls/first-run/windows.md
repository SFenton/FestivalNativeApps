# First-run experiences — Windows notes

> **What:** the Windows carousel, seen-state store, shell seam and Settings replay. **Read when:** touching onboarding, `FirstRun*` Core types or the First Run Guides section on Windows. Spec: [spec.md](spec.md).

## Core (`windows/Festival.Core`)

| File | Contents |
|---|---|
| `Domain/FirstRun.cs` | `FirstRunGateContext`, `FirstRunGate`, `FirstRunSlide`, `FirstRunHashing` (djb2 over **UTF-16 code units** with 32-bit wraparound — bit-identical to the web's `charCodeAt` loop, stricter than Apple's scalar loop for astral characters), `FirstRunSeenRecord`, `FirstRunSlideEvaluator`, `FirstRunModeParser` |
| `Domain/FirstRunCatalog.cs` | 42 slides for the 9 web page keys; **desktop** copy variants (they share the web `contentKey`, so seen-state matches mobile); verbatim `firstRun.en.json` text; `shop-views` omitted until Shop has a view toggle; `FirstRunPages.For(section, route)` maps navigation state to a page |
| `Data/FirstRunSeenStore.cs` | `first-run.json` via `Data/BlobStore.cs` (atomic file blob); ≤500 records (oldest `seenAt` evicted), per-record validation, corrupt/oversized → empty |
| `ViewModels/FirstRunViewModels.cs` | `FirstRunCenter` (single active carousel, Shop context override `{hasPlayer: false, shopHighlightEnabled: true}` from `ShopPage.tsx:141`, replay = reset page + `AllSlides`), `FirstRunCarouselViewModel` (paging, spoken "Slide x of y", completes once) |

## UI

- Fluent `ContentDialog` built with the shared `Controls/FestivalDialog` (issue #23; `Controls/FirstRunCarousel.xaml`): FlipView + white PipsPager, no visible "Slide x of y" (the web shows only pips; operator 2026-09-28): the dialog title is the page label (UIA window "Songs", `fst.first-run.dialog`, read by Narrator on open; issue #24). Each FlipView item's UIA name is its slide title through `FirstRunSlide.ToString()` (before #24 Narrator read the record dump after the title). FlipView items expose UIA `PositionInSet`/`SizeOfSet` and each slide change raises a UIA notification ("<title>, slide 2 of 5"). Buttons (operator batch 6.7; checked against Fluent for issue #25, no change): **Next/Done before Back**, then the standard **Close** (`FirstRunCarouselViewModel.CloseLabel`; UIA ID `fst.first-run.close` from `CloseAutomationId`, the Apple/Android test ID, since issue #244), no Skip. This is `ContentDialog`'s fixed Primary (accent) → Secondary → Close order, and Back stays in place disabled on slide 1, so no command moves under the pointer. UIA: Buttons "Next"/"Done" (`PrimaryButton`), "Back" (`SecondaryButton`) and "Close" (`fst.first-run.close`), Fluent standard size (141×32 epx at 900 px wide). A one-slide guide shows only a full-width **Done** (`ModalCommands.SpansFullWidth`). The FlipView's hover arrows are made transparent and click-through (FlipView toggles them from code). Done, Close, Esc and a click on the dimmed backdrop (`DialogChrome.LightDismiss`, every `ShowDialogAsync` dialog) close it and mark **only the slides actually viewed** seen (`FirstRunCarouselViewModel.ViewedSlides`); unvisited slides return on the next visit. TeachingTip was rejected: it is for one anchored tip, not a multi-slide sequence.
- **Live demos** (`Controls/FirstRunDemo.cs`, data in `Domain/FirstRunDemos.cs`): every one of the 42 catalogue slides maps to a demo kind (song rows, sort flip, filter chip, letter strip, status chips, metadata pills, green/gold/red Shop pulse rows, score bars, leaderboard / your-rank rows, Shop button breathe, stat tiles, rival rows, Shop tiles). Song demos use real catalogue songs with art through the shared art cache (`FirstRunDemos.Pick`/`SongPool`; web `useDemoSongs`/`useItemShopDemoSongs`): Shop demos prefer the loaded Shop only when `ShopOffersForCatalog` confirms a matching publication and Shop isn't hidden, then "Epic Games" artists, then any song, in catalogue order. While the catalogue loads or is unavailable they show muted redacted bars (`FirstRunDemoSong.Placeholder`, never invented titles) and rebuild when `Session.Catalog` arrives. Placeholders never rotate (they share one rotation identity). Only the selected FlipView slide's demo runs (`Active`, set by `FirstRunCarousel` on selection) and it stops when the dialog closes. Since issue #83 that includes the Shop pulse rings and breathing fills: they are created with `Live = active` and `UpdateTimer` toggles them, so off-screen slides hold a still peak-opacity frame instead of running composition animations, and the fill's breathe is 90 held keyframes at 30 steps/s (`ShopPulse.BreatheSteps`) rather than a bezier sampled at display refresh. The backdrop pauses behind the dialog (`ModalOpen`, [artwork background](../artwork-background/windows.md#issue-83-dialogs-and-first-run)). Decorative (UIA Raw). `FirstRunIllustration` (static glyph card) only covers an ID without a demo.
- **Data-swap rotation (issue #58):** only the 12 web-rotating slides swap data: `songs-song-list`, `songs-icons`, `songs-metadata`, `statistics-top-songs`, `songinfo-bar-select`, `suggestions-category-card`, `leaderboards-experimental-metrics`, `compete-hub`, `compete-rivals`, `rivals-overview`, `rivals-instruments` and `rivals-detail`. `FirstRunDemoTiming` matches the web (5 s interval, 400 ms fade out, swap while hidden, 400 ms fade in; bar-select 2.5 s with 300 ms detail fades). `FirstRunDemoRotation` uses deterministic SplitMix64 row selection with the web swap-count table; `FirstRunRowRotation` walks song pools without duplicate visible IDs, and `FirstRunWindowRotation` wraps rival windows. Shop, sort, filter, navigation and other static web demos keep data still; existing non-data pulses may continue. Rotation runs only for the selected FlipView slide while the app is visible/foreground. Windows Animation effects / Reduce Motion disable fade and translation but **do not** freeze data rotation; hidden/minimized/unloaded states pause and complete any in-flight swap.
- Shell seam `MainWindow.Settings.cs`: tracks each section frame's route stack, and after every navigation or settings change queues (low priority) `FirstRunCenter.TryBegin` for the visible page. Skipped over `PlaceholderPage`, while minimized or hidden, or when another carousel is active. Since issue #232 a restore from minimized (`OnAppWindowChanged`) or the window becoming visible again (`VisibilityChanged`) re-queues the check: before, a page reached while minimized never showed its carousel that session (Windows' `waiting-not-ready`: gate facts are synchronous, so the web's `ready` wait maps to this deferral). Closing any carousel for a page, including a Settings replay, ends that page's automatic carousel for the session (`closedThisSession`). Dialogs are serialized through `MainWindow.ShowDialogAsync` (one ContentDialog per window).
- **Text scaling (issue #232):** FlipView can't size to its items, so `FirstRunCarousel.FitSlidesHeight` measures every slide's title (`SubtitleTextBlockStyle`) and description at the 432 epx text width when the dialog loads. It sets the FlipView to max(370, 210 illustration + 12 + tallest), so the height stays the same while paging. At 200% text the longest copy (`songinfo-view-all`, 241 characters) fits without clipping, and the ContentDialog's own scroller handles short windows. A text-scale change while the dialog is open applies on the next open. The decorative demo keeps its 210 epx frame: since issue #241 `FirstRunDemo.MeasureOverride` re-lays it out wider and shrinks it uniformly (`FirstRunDemoFit.Scale`) when larger text makes it taller than the frame. Before, at 200% text the song rows were cut off at the top and bottom of the frame. The title and description keep the full text scale.
- **Demo lifecycle (issue #241):** the FlipView re-hosts realized slides after the dialog lays out, and WinUI then raises a late `Unloaded` while the demo is still in the live tree (`IsLoaded` true). `FirstRunDemo` and the carousel's announcement hook ignore that event (`if (IsLoaded) return;`) and resubscribe idempotently on `Loaded`. Before, slides realized at open (1–2) stopped listening for the catalogue, so on the live service they kept placeholder rows forever and never loaded art. Fixtures answer instantly, so the bug only appeared live. Swap fades animate the slot visual's `Translation`, never `Offset`: XAML layout owns a hand-out visual's Offset, and resetting it to 0 stacked every swapped row onto the first.
- **Pip colours (issue #232):** the white pip overrides live in `ThemeDictionaries` (Dark and Light are both white because `FestivalDialog` forces the dark theme). The HighContrast entries use WinUI's own `SystemColorButtonText`/`SystemColorHighlightText` mapping (generic.xaml), following the `winui-design` rule that custom theme dictionaries cover Light, Dark and HighContrast explicitly with only system colours in HC. On screen, WinUI's high-contrast text adjustment already drew the selected pip glyph white on a black backplate before the change, so the visible result is unchanged.

## Validation (issue #232, 2026-10-04)

Debug build, Rivals fixture (`a11y_matrix.py --only first-run`, forced Songs carousel), 3840×2160 at 300% host:

| Configuration | Result |
|---|---|
| compact, medium, wide, maximized, snap-left, snap-right | Pass: Axe 0, 4 tab stops `Page 1 → Next → Close → Song List` (Back disabled on slide 1), nothing clipped |
| Light, Dark theme | Pass: identical (dialog forced dark, by design) |
| HC Desert, HC Aquatic | Pass: Axe 0; system borders, accent Next and selected pip on Highlight; decorative demo fills fade (UIA Raw) |
| display 100%, 150% | Pass |
| text 200% (and 200% + 150% display) | **Failed before:** the fixed 370 epx FlipView clipped descriptions. Fixed by the text-scale fit above (the longest copy was checked in compact and medium windows). |
| keyboard | Pass: `kb-first-run-esc` (focus on Next, Enter pages, Esc closes); runner `keyboard` scenario |
| Narrator / UIA | Dialog window named after the page, FlipView items named by slide title with PositionInSet/SizeOfSet, pips "Page N" buttons, Back's disabled state exposed; slide changes raise a UIA notification |

Reachable states run in `tools/windows/first_run_journey.py`; all 7 scenarios pass: `hidden-all-seen`, `new-slides-only` (unviewed slides, version bump), `gated` (anonymous 6, player 9, Shop hidden 3, one-slide Leaderboards), `waiting-not-ready`, `replay-all`, `dismissed` (Close, Esc, Done). **`waiting-not-ready` failed before** the restore re-queue above.

## Validation (issue #241, 2026-10-04)

Next/Back/Skip validation of the issue #25 controls against the `winui-design` skill. The setup was a Debug build on the **live public service** (`a11y_matrix.py --live`, anonymous, `--first-run=force`) with a 3840×2160 display at 300% host scale. The pages were `first-run` (slide 1), `first-run-back` (slide 2) and `first-run-done` (last slide), plus the fixture `first_run_journey.py` scenarios.

| Configuration | Result |
|---|---|
| compact, medium, wide, maximized, snap-left, snap-right | Pass (18 runs): Axe 0, no Tab stop outside the dialog, no repeats. Slide 1: `Page 1 → Next → Close` (Back disabled). Later slides: `slide → Page N → Next/Done → Back → Close` |
| Light, Dark theme | Pass: identical (the dialog is forced dark, matching the web) |
| HC Desert (medium), HC Aquatic (compact) | Pass: Axe 0. Focused Next has the system focus rect, the selected pip is on Highlight, and the buttons use system borders |
| display 100%, 150% | Pass: Axe 0 |
| text 200% (compact, medium) | Copy fit (issue #232 fix). **Failed before:** the decorative demo's rows were clipped in their 210 epx frame. Fixed by the demo fit above |
| keyboard | Pass: `kb-first-run-esc` (live). The fixture `keyboard` journey covers Enter paging, Back and Esc |
| Narrator / UIA | Buttons "Next"/"Done", "Back" (disabled state exposed on slide 1) and "Close". FlipView items are named by slide title with PositionInSet/SizeOfSet, and slide changes raise a notification |
| live slide demos | **Failed before:** placeholder rows that never filled, then swapped rows stacking on the first row. Fixed by the demo lifecycle note above |

Fluent alignment (`winui-design` Dialogs, Targeting, Theming):

- ContentDialog's Primary (accent, default) → Secondary → Close order is the platform onboarding pattern.
- **Close is the Windows Skip.** Fluent dialogs dismiss through Close or Esc, and closing marks only the slides you viewed.
- Two deliberate deviations from the Apple/Material arrangement:
  - Back stays visible but disabled on slide 1, so ContentDialog's button columns don't shift under the pointer.
  - The buttons keep WinUI's standard 32 epx height. The skill's targeting guidance treats standard controls as compliant, and they are full column width (141×32 epx at 900 px wide).
- `FirstRunCarouselViewModel.BackLabel` blanks Back for a one-slide guide (Done only).

## Validation (issue #244, 2026-10-04)

This pass checked #44's question: is the guide dismissed through the native Fluent control rather than a small custom "x"? It used a Debug build on the **live public service** (`a11y_matrix.py --live --scan --tabs 12`, anonymous, `--first-run=force`), a 3840×2160 display at 300% host scale and the fixture `first_run_journey.py`.

| Configuration | Result |
|---|---|
| compact, medium, wide, maximized, snap-left, snap-right | Pass (18 runs, `first-run`/`-back`/`-done`): Axe 0, no Tab stop outside the dialog. Slide 1: `Page 1 → Next → Close → slide`. Close is ContentDialog's own command button, with no glyph |
| Light, Dark theme | Pass: identical (dialog forced dark) |
| HC Desert, HC Aquatic (compact, medium) | Pass: Axe 0, Close has a system border and visible focus |
| display 100%, 150% | Pass: Axe 0 |
| text 200% (and 200% + display 150%) | Axe 0, but **failed before:** in short windows the tall dialog grew into the 48 epx caption band, so the window's own –/□/× sat over its top-right corner. That × quits the app, which is the "small x" the issue describes. Fixed by `DialogChrome.ClearOfTitleBar` ([design](../../design/windows.md)): the dialog now starts below the title bar and its body scrolls. At 100% text the compact dialog still fits without scrolling |
| keyboard | Pass: `kb-first-run-esc` (live; compact, medium, wide). Tab reaches Close, Esc closes and records the viewed slides seen |
| Narrator / UIA | **Failed before:** Close kept the template's generic `CloseButton` ID, while Apple/Android use `fst.first-run.close` and the other Windows dialogs tag their Close. It now exposes `fst.first-run.close` (`assertstate` in the `first-run` matrix page; the `lifecycle` journey invokes it). A one-slide guide has only Done and no Close ID |
| Profile search | Unchanged: a light-dismiss flyout with no close control |

All 7 `first_run_journey.py` scenarios pass, and `dismissed` covers Close, Esc and Done. Fluent alignment (`winui-design`; `winapp find-ui` → Gallery ContentDialog samples; `winapp find-api` confirmed `CloseButtonText`/`DefaultButton`/`IsSecondaryButtonEnabled`/`CloseButtonStyle` on `ContentDialog`): dismissal is the platform's text Close command plus Esc. ContentDialog has no title-bar close button, so the #241 deviations remain (Back disabled on slide 1, standard 32 epx buttons). No screen recording was possible because the host console is locked, so the live screenshots come from PrintWindow. The `winui-code-review` analyzer package isn't referenced, so its checklist was applied by hand.

## Debug

`FST_DEBUG_FIRST_RUN` (Debug/automation env) or `--first-run off|on|force`: Debug and [automation](../../platforms/windows.md) launches default **off** (automation is never blocked), Release default normal. `force` shows every gate-passing slide on each evaluation. Settings replay works in every mode.

## Open

- Demos approximate the web's per-slide `render()` rather than copying each 1:1; the issue #58 rotation core now uses the web pools and timings for the 12 rotating demos.
- IDs: `fst.first-run.dialog`, `.carousel`, `.slides`, `.pips`, `.close` (the template's Close button, issue #244; absent on one-slide guides); replay rows `fst.settings.first-run.<pageKey>`. Screenshot: `windows/reports/screenshots/first-run-replay-wide.png`.
