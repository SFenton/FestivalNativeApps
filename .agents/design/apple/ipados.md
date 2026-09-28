# iPadOS design

> **What:** iPad split-view and sidebar decisions. **Read when:** building iPad layouts (after the iPhone phase; see [PROGRESS.md](../../../PROGRESS.md)).

- `NavigationSplitView` sidebar (chosen for its audited Dynamic Type behavior). Every custom sidebar row sits on an opaque Fluent card; selection = visible 3pt accent-blue leading bar + semibold label + `.isSelected` trait (a trait alone is invisible). The selected player's name sits in a sidebar footer.
- Detail-pane width changes with Hide/Show Sidebar, Slide Over and window resizing: never fix row counts (chips wrap 5+4 where the web tablet shows 9 in one row) and never hardcode device sizes.
- Sheets are centered and narrower; a Form may need scrolling to expose Reset above a pinned footer.
- Grids (e.g. Shop) use full-bleed adaptive cards and reflow to a list at accessibility text sizes (a clipped grid artist prompted this).
- Always exercise Hide Sidebar with a detail visible: badge padding once caused a main-thread layout loop there.
