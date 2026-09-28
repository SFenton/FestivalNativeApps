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

- Fluent `ContentDialog` (`Controls/FirstRunCarousel.xaml`): FlipView + PipsPager, no visible "Slide x of y" (the web shows only pips; operator 2026-09-28): FlipView items expose UIA `PositionInSet`/`SizeOfSet` and each slide change raises a UIA notification ("<title>, slide 2 of 5"); Next/Done (primary), Back (secondary), Skip (close). Close, Skip, Esc and Done all mark every displayed slide seen. TeachingTip was rejected: it is for one anchored tip, not a multi-slide sequence.
- `Controls/FirstRunIllustration.cs`: static brand-gradient card + Segoe Fluent glyph per slide (no animation, so off-screen FlipView pages cost nothing). The web's live per-slide demos are **not** ported yet.
- Shell seam `MainWindow.Settings.cs`: tracks each section frame's route stack, and after every navigation or settings change queues (low priority) `FirstRunCenter.TryBegin` for the visible page. Skipped over `PlaceholderPage`, while minimized, or when another carousel is active. Dialogs are serialized through `MainWindow.ShowDialogAsync` (one ContentDialog per window).

## Debug

`FST_DEBUG_FIRST_RUN` (Debug/automation env) or `--first-run off|on|force`: Debug and [automation](../../platforms/windows.md) launches default **off** (automation is never blocked), Release default normal. `force` shows every gate-passing slide on each evaluation. Settings replay works in every mode.

## Open

- Live demos per slide (web `pages/<page>/firstRun/demo/*`).
- IDs: `fst.first-run.dialog`, `.carousel`, `.slides`, `.pips`; replay rows `fst.settings.first-run.<pageKey>`. Screenshot: `windows/reports/screenshots/first-run-replay-wide.png`.
