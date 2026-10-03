# Global search — iPad notes

> **What:** how global search differs on iPad from the [iPhone design](ios.md). **Read when:** changing global search on iPad. Behavior: [spec.md](spec.md).

| Aspect | iPad |
|---|---|
| Shell, regular width | `NavigationSplitView` with the Festival sidebar. A **Search** row heads the sidebar (`fst.nav.sidebar.search`, `RootTab.search`); choosing it shows `GlobalSearchTab(asTab: false)` in the detail column with the bell and avatar in that column's bar. The field is **not** focused on selection |
| Shell, compact width | The phone tab bar, including the trailing Search tab (keyboard up), see [ios.md](ios.md) |
| Hardware keyboard | ⌘K and ⌘F open search (sidebar Search row or Search tab) |
| Results | Pushed on the section that was showing before Search; that section's sidebar row is selected again |
| Why | Issue #92. HIG Search fields (`apple-hig/references/hig/search-fields.md`): "Use a sidebar/tab-bar search item for a dedicated discovery area"; "on iPad with only a virtual keyboard, leave it unfocused to avoid unexpected keyboard coverage". The header Search button and the search sheet are gone on iPad |
