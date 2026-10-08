# Back keeps place

> **What:** how a page you return to with Back (from View All, a rival, a song, Licenses) comes back: no reload, no movement, no replayed fade-in, and focus on the control that opened the pushed page. **Read when:** making a page cacheable or kept on the back stack, changing what a page does when it appears again, or adding a pushed page reached from a cached root.

Status: **current**, 2026-10-08. Provenance: #39 (iOS), #82 (Android, Windows), #276 (Windows), #347 (Apple splits), #352 (profiles cover the split), #369 (Compete rivals beside Compete).

## Intent

Back undoes a push. The reader lands where they left: the same rows, at the same scroll position, with nothing moving or fading in, and (on Windows) keyboard and Narrator focus on the control they activated. Changes that happened while they were away still apply: a new publication or account reloads, a failed load retries, and a Settings or filter change is already shown.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/hooks/ui/useScrollRestore.ts` (`useScrollRestore`) | Saves each page's scroll offset by cache key and restores it when the page mounts again after Back. |
| `FortniteFestivalWeb/src/hooks/ui/usePageTransition.ts` (`usePageTransition(cacheKey, isReady, hasCachedData)`) | A page that returns with cached data skips the spinner and the stagger (`shouldStagger` false). |
| `FortniteFestivalWeb/src/pages/suggestions/suggestionsScrollRestoration.ts` (`beginSuggestionsScrollRestoration`), `suggestionsSessionCache.ts` | Suggestions keeps its generated mix for the session and restores the scroll position on return. |

The web has no focus return: the browser moves focus to the document on Back. Native focus return (R4) is a platform requirement, not web parity.

## Rules

1. **R1. Back doesn't reload.** A page kept on the back stack (Windows `NavigationCacheMode`, Android back-stack `ViewModel`, Apple `NavigationStack`) keeps its loaded content when its load key (account, publication, visible charts or other read inputs) is unchanged. A failed or cancelled load still retries on return, and a new publication or account reloads in place ([load-transition](load-transition.md) R9). Gate the read on the key, never on "appeared again".
2. **R2. Back doesn't rebuild or replay.** Settings and filter changes made while the page was away are applied when they happen, not by rebuilding the list on reappearance. A returning page keeps its item objects, so it replays no entrance fade or stagger ([load-transition](load-transition.md) R5; web `usePageTransition` `hasCachedData`). Suggestions keeps its mix and its cards (#276).
3. **R3. Back doesn't move anything.** After Back, the opener and the card or section around it keep their window position and size (UIA tolerance 1 px), immediately and 1.5 s later. Pause any platform behavior that moves content on return: Windows focus-follow scrolling (`ScrollViewer.BringIntoViewOnFocusChange`) and scroll anchoring (`VerticalAnchorRatio` NaN) while the page is away. Inner lists that would re-estimate row heights on return stay realized (Windows `LeaderboardsCardGridLayout` as a one-column stack, #276).
4. **R4. Focus returns to the opener (Windows).** When a cached root is left, remember the focused control and its `FocusState`. On Back, after layout, focus it again in that state (pointer focus shows no rectangle; keyboard focus does). If the control was recycled, prefer the visible control with the same automation ID bound to the same item, else the first visible one; skip collapsed or stale containers. Don't take focus back if the reader has already moved it to the navigation pane, and never scroll for it: a partly visible opener scrolls in on the next key press. Agent decision (#276, 2026-10-06), see below.
5. **R5. Every consumer has a regression journey.** Each cached root that can push a page has a fixture journey in `tools/windows/journeys/back-keeps-place.json`. Every Back round pins the opener and its card or section, goes Back, asserts both immediately and again after `wait:1.5`, then asserts focus on the opener. The container pin must stay on screen at every size and text scale (the driver only measures on-screen elements): pin a card by its named UIA group (`name=<title>&class=AccessibleGroup`), which stays on screen while any part shows, rather than its heading; use the list or grid (`fst.songs.list`, `fst.shop.grid`) or the adjacent section (Settings' First Run Guides row) where the opener has no card. `tools/windows/tests/test_back_keeps_place.py` enforces this shape. Live checks (`--live`) cover Leaderboards and Rivals with the public `SFentonX` profile.

6. **R6. Back closes an open split pane first (Apple on-demand split).** While a trailing pane is open next to a pushed list page (Song Detail with its full leaderboard or score history, All Rivals, Compete pushed in another section with Rival Detail beside it, Leaderboards pushed in Compete with Full or Band Rankings beside it), the leading pane's Back closes the trailing pane and keeps the list page; only the next Back pops it. Back, Close, Escape and ⌘[ all go through `OnDemandSplitPolicy` (`pathAfterListBack` / `pathClosingDetail`), and focus returns to the row that opened the pane. On iOS the leading page's system Back is replaced by `SplitListBackButton` (`fst.split.list-back`, chevron, "Back (⌘[)") only while the pane is open, which also stops the edge swipe from popping the page; once the pane closes, the system Back returns. A section-root list page (Rivals, Compete, Leaderboards, Settings) has no Back. HIG toolbars.md: "The standard Back button retraces an information hierarchy"; "A custom version should retain the standard appearance, expected behavior". Owner #347. **A profile covers the split and keeps it (#352, agent decision; owner may override with `/choose`):** a player or band profile is a full page, never a pane. Opened inside the trailing pane (Full Rankings beside Leaderboards) the pane widens over the hidden list page; its Back returns to the split with the board, its scroll and the list's selection kept. Opened from the list page it is pushed over it; Back returns to the list page with its place kept (`OnDemandSplitPolicy.Cover`).

## Decision: return focus to the opener (agent decision, #276, 2026-10-06; owner may override with `/choose`)

After #82 paused focus-follow scrolling, Back left keyboard focus on the pane's Toggle Navigation button, so a keyboard or Narrator reader lost their place.

| Option | Result | Chosen |
|---|---|---|
| WinUI default (no restore) | Focus falls to the first focusable chrome element; the reader has to Tab back through the page. | No |
| Return focus to the opener on cached roots (`CachedPageScroll`) | Back lands on the control that opened the page, in its original focus state, without scrolling. | **Yes** |
| Navigation-wide focus and scroll restore, including pushed pages | Would also restore Song Detail and other pushed pages, which are rebuilt on Back. | Deferred: needs page caching for pushed pages, a separate navigation decision |

Grounds, by strength: `winui-design` (**must** for custom navigation): "Build custom UI only when … you'll implement keyboard, focus, UI Automation …". The section `Frame`s are app navigation, so restoring focus is ours to implement. Fluent flyouts, dialogs and the search box already return focus to their invoker ([design/windows](../design/windows.md), the search box's `RestoreFocus`); this extends that precedent to Back. Web: no equivalent (R4 is native only). Apple and Android aren't changed by this decision.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Keyed reload gate (R1) | `apple/Sources/FestivalCore/ReappearanceLoadGate.swift` `ReappearanceLoadGate` | `android/app/src/main/java/com/festivalscoretracker/android/presentation/compete/CompeteViewModel.kt` `CompeteViewModel` | Each page model's key gate (`LeaderboardsViewModel`, `RivalsHubViewModel`, `SuggestionsViewModel.LoadAsync`) |
| Split Back closes the pane first (R6) | `apple/Sources/FestivalUI/App/Layout/OnDemandSplitPolicy.swift` `OnDemandSplitPolicy.pathAfterListBack`, `OnDemandSplit.swift` `SplitListBackButton` (iOS leading pane and Mac `MacListDetailStack` toolbar) | Not applicable (no on-demand split) | Not applicable (no on-demand split) |
| No movement, focus return (R3, R4) | `NavigationStack` (system) | Navigation back stack (system) | `windows/Festival.App/Services/CachedPageScroll.cs` `CachedPageScroll`, attached to every section `Frame` in `MainWindow` |

### Windows consumers (#276 sweep)

| Cached root | Pushed page | Journey | Pinned container (R5) | Status |
|---|---|---|---|---|
| Leaderboards | Full Rankings, Band Rankings, player | `back-leaderboards-instrument`, `-band`, `-selected`, `back-leaderboards-live` | The instrument or band card's group | ✅ |
| Rivals | All Rivals, Rival Detail | `back-rivals-view-all`, `back-rivals-row`, `back-rivals-live` | The section card's group (Lead, Common or Drums Rivals) | ✅ |
| Songs | Song Detail | `back-songs-row` | The song list | ✅ |
| Item Shop | Song Detail | `back-shop-song` | The tile grid | ✅ |
| Suggestions | Song Detail | `back-suggestions-row` | The category card | ✅ **Fixed (#276):** Back rebuilt every card and replayed the fade-in (R2), and focus fell to the Back button because the re-realized card left a collapsed copy (R4) |
| Settings | Licenses | `back-settings-licenses` | The First Run Guides row above Licenses | ✅ |

Out of scope: pushed pages (Song Detail, Full Rankings, Rival Detail, Licenses …) aren't cached, so they rebuild on Back and don't keep focus or scroll (the deferred option above). Statistics isn't cached and pushes nothing.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple and Android focus return after Back not audited | R4 on those platforms | Their platform owners check it with VoiceOver/TalkBack before claiming R4 |

## Guards (`tools/pattern_guard.py`)

- `back-keeps-place/windows-scroll-pause`
