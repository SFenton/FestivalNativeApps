# Global search — iPad notes

> **What:** how global search differs on iPad from the [iPhone design](ios.md). **Read when:** changing global search on iPad. Behavior: [spec.md](spec.md).

| Aspect | iPad |
|---|---|
| Shell, regular width | `NavigationSplitView` with the Festival sidebar. A **Search** row heads the sidebar (`fst.nav.sidebar.search`, `RootTab.search`); choosing it shows `GlobalSearchTab(asTab: false)` in the detail column with the bell and avatar in that column's bar. The field is **not** focused on selection |
| Shell, compact width | The phone tab bar, including the trailing Search tab (keyboard up), see [ios.md](ios.md) |
| Hardware keyboard | ⌘K and ⌘F open search (sidebar Search row or Search tab), as do the menu bar's Edit › Search Festival… and Go › Search…. Go destinations (⌘1…⌘9) leave Search like a sidebar row (the section Search was opened from returns with its stack); Go › Back is disabled while Search shows; Help › Licenses leaves Search and pushes on that section |
| Title | Large **Search** navigation title in the detail column, kept while the field is focused (issue #100, same modifier as the [iPhone tab](ios.md)) |
| Results | Pushed on the section that was showing before Search; that section's sidebar row is selected again |
| Empty state | Same centred title, subtitle and Retry as [ios.md](ios.md) (issue #99), centred in the detail column below the scope bar |
| Why | Issue #92. HIG Search fields (`apple-hig/references/hig/search-fields.md`): "Use a sidebar/tab-bar search item for a dedicated discovery area"; "on iPad with only a virtual keyboard, leave it unfocused to avoid unexpected keyboard coverage". The header Search button and the search sheet are gone on iPad |
