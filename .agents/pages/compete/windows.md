# Compete — Windows notes

> **What:** how `/compete` behaves on Windows. **Read when:** changing Compete routing in `MainWindow` or the Rivals hub. Full Rivals notes: [../rivals/windows.md](../rivals/windows.md).

- Windows has no Compete section: the wide split keeps Leaderboards and Rivals as separate navigation items. `AppRoute.Compete` (and `/rivals`) deep links show the Rivals section root when a player is selected; with no player selected, `/compete` redirects to the Songs root (checked by the `compete-no-player` scenario in `tools/windows/rivals_journey.py`).
- The web Compete page's leaderboard top-5 cards are covered by the Leaderboards section, not duplicated here.
- Loading (#65, 2026-10-02): every hub card shows a `ProgressRing` until its rows or inline error arrive; see [Rivals Windows notes](../rivals/windows.md). Validated per configuration in #265 (UIA journeys `loading` / `loading-freeze`, `a11y_matrix` page `compete-loading`); results are in the Rivals notes.
- **Back keeps the scroll position (#82, 2026-10-02):** the iOS #39 check. Leaderboards → View All → Back and Rivals → rival → Back did not reload (both models are key-gated), but they came back scrolled several sections further down. When the clicked control left the window with the cached page, WinUI walked focus through the page's other controls, and the page `ScrollViewer` brought each one into view. `Services/CachedPageScroll` (attached to every section `Frame`) pauses `BringIntoViewOnFocusChange` on an outgoing cached page's scrollers and restores it when the page is shown again. Regression: the Quick Links → Drums → View All → Back block in `tools/windows/journeys/leaderboards.steps` (fails without the fix).
- **Back returns focus to the opener (agent decision, #276, 2026-10-06; owner may override with `/choose`):** after #82, Back left keyboard focus on the pane's Toggle Navigation button, so a keyboard or Narrator reader lost their place. `CachedPageScroll` now records the focused control when a cached section root is left. On Back, once the page is `Loaded` and laid out (a `Low`-priority enqueue), it focuses that control again in its original `FocusState`, so pointer focus shows no rectangle. If the control was rebound to another item, it focuses the live control with the same automation ID instead (Songs re-projects its rows). It skips this when the reader has already moved focus to a `NavigationViewItem`. The scrollers stay paused and the focus's `BringIntoViewRequested` is handled, so Back still never moves the page; a control left partly visible scrolls in only on the next key press. Options weighed: leave WinUI's default (no restore), this, or navigation-wide focus+scroll restore for pushed pages too (deferred: they are rebuilt on Back). Grounds: flyouts/dialogs return focus to their invoker ([design/windows](../../design/windows.md)), the search box's `RestoreFocus`, and `winui-design`'s requirement that custom navigation implements keyboard focus. Web has no equivalent (the browser restores scroll only). Regression: `tools/windows/journeys/back-keeps-place.json` (`assertpinned` twice, then `assertfocus` on the opener).
- **Back never anchors (#276, 2026-10-06):** at text 200% in a compact window, Leaderboards crept up 2 epx after Back. The page didn't reload; the `ScrollViewer`'s scroll anchoring was chasing sub-pixel re-layout of `ItemsRepeater` rows, which have fractional heights at 300% scale. The offset stepped 776.33 → 774.33 while the extent stayed the same. The #82 code alone did this too. `CachedPageScroll.Pause` now also records each scroller's `VerticalAnchorRatio` and sets it to `double.NaN`, which turns anchoring off. `Resume` restores the recorded ratio. Regression: `back-leaderboards-instrument` / `back-leaderboards-band` at `--mode text-200 --sizes compact`.
- **Card rows stay realized (#276, 2026-10-06):** live at text 200% in a compact window, the Duos View All still moved 3 epx after Back, with anchoring off and an unchanged offset. Card 8's top-ten `ItemsRepeater` used a virtualizing `StackLayout`. While the page was away it dropped its rows, and on Back it laid them out at an estimated 48 epx instead of their real 66.67. The page shrank 13 epx, then grew back row by row over about half a second (visible jitter above the opener) and ended 2.67 epx short. The top-ten row repeaters in Leaderboards' instrument and band cards and in Rivals' cards now use `LeaderboardsCardGridLayout` with `MaxColumns="1"` and `MinColumnWidth="0"`. That is the repo's non-virtualizing `ItemsRepeater` layout (Bands and Song Detail precedent: "every card is realized"), used as a stack. At most about 11 rows per card, so realizing them all is cheap, and the page extent is now exact (10,440 epx where the estimate gave 9,127). Song Detail isn't cached (its `VerticalCacheLength="20"` already realizes its rows). Regression: `back-leaderboards-live` at `--mode text-200 --sizes compact`, whose band step goes Back with the title-bar button while the opener sits at the window's bottom edge.
- **Band rows no longer crash on Back (#276, 2026-10-06):** live, Back from Band Rankings to Leaderboards closed the app now and then, most often snapped. The app fail-fasted (0xc000027b in CoreMessagingXP). `MarqueeText.Play()` runs a synchronous `UpdateLayout()`, which can apply x:Bind to a recycled band row. The new text then called `Stop()`, which called `StopAnimation("Translation.X")` before `Play` had enabled Translation. That throws `ArgumentException` inside a XAML callback. The #82 code crashed the same way. `Stop()` now stops the composition animation only once `Play` has started it, and `Play` returns if it was stopped during its layout pass. Found with a temporary first-chance exception log; regression: `back-leaderboards-live` at `snap-left` / `snap-right`.

## Validation (issue #276, 2026-10): back keeps place

Rule: Back from a pushed page (View All, a rival, a song) to a cached section root keeps the page still and returns focus to the control that opened the pushed page. It doesn't reload and doesn't jump. `a11y_matrix.py --pages tools/windows/journeys/back-keeps-place.json`: each page pins the opener and presses Enter, then goes Back with Alt+Left (or the title-bar Back button). It asserts the opener and its card didn't move, twice 1.5 s apart, then asserts focus is on the opener. Live means the public service with the public `SFentonX` profile (`back-leaderboards-live`, `back-rivals-live`). Fixture pages cover Leaderboards (instrument, band, selected player), Rivals (View All, a rival row), Songs (a row → Song Detail) and the Shop (a tile → Song Detail). The `winui-design` and `winui-code-review` skills were applied.

| Configuration | Result |
|---|---|
| Compact / medium / wide, maximized, snapped left/right | ✅ Live and fixture: no reload, nothing moves, focus on the opener; Axe 0. **Fixed:** focus fell to Toggle Navigation (see the #276 focus bullet above); snapped, Back from Band Rankings could close the app (see the band-rows crash bullet above) |
| Light / dark | ✅ Identical by design (dark-only, [design/windows](../../design/windows.md)) |
| High contrast Night sky, Desert (compact, medium) | ✅ The focus rectangle is visible on View All after Back (keyboard `FocusState` kept); Axe 0 |
| Text 200% (compact, snapped, medium) | **Fixed:** in compact, Leaderboards crept up 2 epx after Back because of scroll anchoring, and live, re-estimated card rows moved the page by up to 13 epx (see the #276 anchoring and card-rows bullets above). Now ✅ live and fixture; Axe 0 |
| Display 100% / 150% (medium, wide) | ✅ Axe 0 |
| Keyboard only | ✅ Enter opens, Alt+Left returns, `assertfocus` on the opener |
| Narrator | The UIA tree stands in: the opener keeps its name and role, and Back focus is announced on it. Narrator was not run live |

Limits: this host renders at 300%, so the wide preset clamps at 1280 epx. The console session is locked, so the journeys post keys rather than real mouse clicks. Suggestions and Settings use the same `CachedPageScroll` but were not probed individually. Pushed pages such as Song Detail are rebuilt on Back, so they don't keep focus or scroll; that's deferred to a navigation-wide decision.

## Validation (issue #213, 2026-10)

Live public service (keyless HTTPS, public `SFentonX` profile, `/compete`) unless marked fixture. The `winui-design` and `winui-code-review` skills were applied.

| Configuration | Result |
|---|---|
| Compact / medium / wide, maximized, snapped left/right | ✅ The masonry hub reflows 1→2 columns. **Fixed:** Quick Links named the second card of the first row (the FadeIn stagger offset skews `TransformToVisual`), so it now uses the `QuickLinks.RowTolerance` row rule. See [quick-links](../../controls/quick-links/windows.md) |
| Leaderboard Rivals tab | **Fixed:** Lead and Vocals cards showed "Unavailable" because live lists contain anonymous rows. See [rivals Data](../rivals/windows.md#data) |
| Light / dark | Identical by design (the app is dark-only, [design/windows](../../design/windows.md)) |
| High contrast Night sky, Desert (live); Aquatic (fixture) | ✅ System colours, focus visible, Axe 0 |
| Text 200% (compact, medium) | ✅ Pills wrap and nothing clips; Axe 0 |
| Display 100% / 150% | ✅ At wide width the Quick Links pane replaces the menu button and selects the top card; Axe 0 |
| Keyboard only | ✅ `kb-compete-order` journey (tabs → Quick Links → cards in order), 9/10/10 tab stops, every stop inside the app |
| No player | ✅ Redirects to Songs (`compete-no-player`) |

Limits: this host renders at 300%, so the wide preset clamps at 1280 epx, and the Quick Links pane appears only at display 100%/150%. The console session is locked, so the journeys post keys rather than real mouse clicks. Narrator was not run live, so the UIA tree (names, roles, heading levels, focus) stands in for it.

## Validation (issue #266, 2026-10): no Leaderboards Overview button

Rule (#66, web parity): Compete has no Leaderboards Overview button, as on web `CompetePage.tsx`, which has only per-section See All and View Full Leaderboards. Each Leaderboards card keeps its View All Rankings → Full Rankings path. Windows already complies, so no app code changed. `/compete` opens the Rivals section root. Leaderboards is its own `NavigationView` item ("2–7 sections → NavigationView", `winui-design`), and `RivalsViewModels` routes the hub only to `AppRoute.AllRivals`/`RivalDetail`.

Live public service, public `SFentonX` profile, `a11y_matrix.py --live` with `waitgone:name=Leaderboards Overview` on every page:

| Configuration | `/compete` | `/leaderboards` (+ Lead View All) |
|---|---|---|
| Compact / medium / wide, maximized, snapped left/right | ✅ no overview button; 14 Tab stops, Axe 0 | ✅ View All Rankings on every card at every width; 23 Tab stops, Axe 0 |
| Light / dark | ✅ identical by design (dark-only) | ✅ |
| High contrast Night sky, Desert | ✅ system colours, focus visible, Axe 0 | ✅ Axe 0 |
| Text 200% (compact, medium) | ✅ Axe 0, nothing clipped | ✅ View All reachable, Axe 0 |
| Display 100% / 150% (medium, wide) | ✅ Axe 0 (13 stops at wide 100%/150%, where the pane replaces the menu button) | ✅ Axe 0 |
| Keyboard only | ✅ every Tab stop inside the app, none repeated | ✅ |

Regression: the fixture `compete` journey in `tools/windows/journeys/navigation.py` checks three things. `/compete` selects Rivals with no `fst.leaderboards.*` or "Leaderboards Overview" element. Leaderboards has no overview button. Lead View All opens Full Rankings.
