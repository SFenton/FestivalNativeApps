# Global search — iPad notes

> **What:** how global search differs on iPad from the [iPhone design](ios.md). **Read when:** changing global search on iPad. Behavior: [spec.md](spec.md).

| Aspect | iPad |
|---|---|
| Shell | `NavigationSplitView` with the Festival sidebar (not a `TabView`), so there is no search tab |
| Entry point | Toolbar **Search** button (`fst.global-search.open`): trailing on every section root, before the bell and avatar (`FestivalRootTrailingItems`), and `.primaryAction` on pushed pages; hardware keyboard **⌘K** and **⌘F** |
| Surface | `GlobalSearchSheet` presented with `festivalSheet()` (form-sized on regular width), `.searchable` field focused on open, trailing Close; results push on the presenting section after the sheet closes |
| Why | HIG iPadOS: search usually sits at the trailing side of the toolbar; the sheet mirrors the web desktop dialog (520 × 640) and keeps the detail column visible behind it |

`TODO(orchestrator)`: when the iPad shell moves to `TabView` + `.sidebarAdaptable` (iPadOS phase), switch to a search tab in the sidebar (HIG: "include search as an item in the sidebar … when you want an area dedicated to discovery").
