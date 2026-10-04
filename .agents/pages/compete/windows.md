# Compete — Windows notes

> **What:** how `/compete` behaves on Windows. **Read when:** changing Compete routing in `MainWindow` or the Rivals hub. Full Rivals notes: [../rivals/windows.md](../rivals/windows.md).

- Windows has no Compete section: the wide split keeps Leaderboards and Rivals as separate navigation items. `AppRoute.Compete` (and `/rivals`) deep links show the Rivals section root when a player is selected; with no player selected, `/compete` redirects to the Songs root (checked by the `compete-no-player` scenario in `tools/windows/rivals_journey.py`).
- The web Compete page's leaderboard top-5 cards are covered by the Leaderboards section, not duplicated here.
- Loading (#65, 2026-10-02): every hub card shows a `ProgressRing` until its rows or inline error arrive; see [Rivals Windows notes](../rivals/windows.md).
- **Back keeps the scroll position (#82, 2026-10-02):** the iOS #39 check. Leaderboards → View All → Back and Rivals → rival → Back did not reload (both models are key-gated), but they came back scrolled several sections further down. When the clicked control left the window with the cached page, WinUI walked focus through the page's other controls, and the page `ScrollViewer` brought each one into view. `Services/CachedPageScroll` (attached to every section `Frame`) pauses `BringIntoViewOnFocusChange` on an outgoing cached page's scrollers and restores it when the page is shown again; focus still lands where it did. Regression: the Quick Links → Drums → View All → Back block in `tools/windows/journeys/leaderboards.steps` (fails without the fix).

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
