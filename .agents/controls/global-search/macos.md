# Global search — Mac notes

> **What:** how global search differs on macOS from the [iPhone design](ios.md). **Read when:** changing global search on the Mac. Behavior: [spec.md](spec.md).

| Aspect | Mac |
|---|---|
| Entry point | Toolbar **Search** item (`.primaryAction`) on every section root (before the profile item) and pushed page; **⌘K** and **⌘F** open it from anywhere in the window |
| Surface | `GlobalSearchSheet` (window-modal sheet, `FestivalModal("Search")` so the sheet shows its **Search** title), its own `GlobalSearchField` focused on open, Close as the confirmation action; Escape closes. No Search tab or sidebar row on the Mac, so the iOS title fix (issue #100) does not apply; the title was already present (`~/FestivalShowcase/native-mac/14-search.png`, 2026-10-02) |
| Empty state | Same centred title and subtitle as [ios.md](ios.md) (issue #99; no Retry since #299, Return in the field re-runs a failed or empty search), centred in the sheet below the scope bar; the #299 spinner centres in the same area |
| Size and columns (#350) | In a landscape window at least 960 × 700 pt the sheet opens at 880 × 640 pt and shows two result cards per row under full-width headings; otherwise 620 × 680 pt, one column. Resizable (minimum 560 × 520); the columns follow the sheet's own size, two when it is wider than tall and at least 684 pt wide ([wide-columns](../../patterns/wide-columns.md) R1, R6; `WideColumns.macSheetSize`, `count(size:)`). HIG Sheets (`sheets.md`): "Present a sheet in a reasonable default size" (should); HIG Mac Catalyst (`mac-catalyst.md`): "split a single column into multiple columns … reflowing content side by side as the window resizes" (should) |
| Why | Mac users expect ⌘F for find and a toolbar search affordance; a sheet matches the web desktop dialog and keeps results separate from the Songs list filter |

Open: the Mac app's menu bar has no Find command yet; add "Search…" (⌘K) to the app's commands when the Mac phase adds a `Commands` builder.
