# All Rivals — Windows notes

> **What:** Windows state of `/rivals/all`. **Read when:** changing `windows/Festival.App/Pages/AllRivalsPage*` or `AllRivalsViewModel`. Full Rivals notes (data, scope, IDs, tests): [../rivals/windows.md](../rivals/windows.md).

- `AppRoute.AllRivals(RivalScope)` parses web queries (`category`, `mode=leaderboard`, `rankBy`, optional `instruments`); `category=common`/`combo` without instruments resolve against Settings at load, and an unresolvable scope shows "This rivals list could not be identified."
- Virtualized `ListView` of `RivalRowView` rows (above, then below), centred to 960 epx; rows push Rival Detail with the same scope. Rule (#603, [rival-rows](../../patterns/rival-rows.md) R6): the rows are one grouped card (`GroupedRows.ApplyToContainer` slices, hairlines between rows, `FadeIn.Together`), like iOS and the #543 boards, never a card per row. Journey `a11y-rivals-cards.json` `rivals-cards-all-rivals`.
- States: loading ring, shared `ServiceStatusView` (scrape freeze countdown), empty, no player.
- Header: an instrument icon or none, the title, then a subtitle (metric and rank, or the chart list) that collapses when empty (`HasSubtitle`) and wraps. The web has no subtitle; it's a native addition. Accessibility matrix pages: `all-rivals`, `all-rivals-lead`, `-board`, `-empty` and `-freeze` in `journeys/a11y.json`. Validation: [windows-accessibility.md](../../testing/windows-accessibility.md#all-rivals-validation-issue-201-2026-10-03).
- Design review (issue #201, `winui-design`/`winui-code-review`): the grouped card uses the 12 epx card radius of the #543 boards (the per-row `OverlayCornerRadius` container went with #603). Deliberate deviations:
  - The app is dark-only, so the theme dictionaries are Default plus HighContrast.
  - Strings are inline because the repo has no `.resw`.
  - Field-style `[ObservableProperty]` follows the repo convention.

## Split view (#652)

All Rivals and the Rivals hub are split list pages ([split-panes](../../patterns/split-panes.md) R7 Windows variant): the page starts full width, and a rival opens Rival Detail in the trailing half when the content area holds two 480 epx halves (`OnDemandSplitHost`, `fst.split.pane`), else pushes it full width. Another rival replaces the open one, Rivalry pushes inside the pane, and Back or Close (`fst.split.close`) closes the pane first. No rival is pre-selected and no row stays highlighted (the list keeps `SelectionMode=None`). The page-local 520 epx list column with an auto-selected first rival (`fst.all-rivals.detail-pane`) was removed. Journeys: `rivals-split-wide` and `rivals-push-medium` in `tools/windows/journeys/split-panes.json`, and `journeys/all-rivals-split.json` (Invoke opens and replaces the pane; `a11y_matrix.py --pages tools/windows/journeys/all-rivals-split.json --mode scale-150 --sizes wide,maximized` on a 300% host).
