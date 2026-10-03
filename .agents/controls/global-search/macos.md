# Global search — Mac notes

> **What:** how global search differs on macOS from the [iPhone design](ios.md). **Read when:** changing global search on the Mac. Behavior: [spec.md](spec.md).

| Aspect | Mac |
|---|---|
| Entry point | Toolbar **Search** item (`.primaryAction`) on every section root (before the profile item) and pushed page; **⌘K** and **⌘F** open it from anywhere in the window |
| Surface | `GlobalSearchSheet` (window-modal sheet, `FestivalModal("Search")` so the sheet shows its **Search** title), its own `GlobalSearchField` focused on open, Close as the confirmation action; Escape closes. No Search tab or sidebar row on the Mac, so the iOS title fix (issue #100) does not apply; the title was already present (`~/FestivalShowcase/native-mac/14-search.png`, 2026-10-02) |
| Empty state | Same centred title, subtitle and Retry as [ios.md](ios.md) (issue #99), centred in the sheet below the scope bar |
| Why | Mac users expect ⌘F for find and a toolbar search affordance; a sheet matches the web desktop dialog and keeps results separate from the Songs list filter |

Open: the Mac app's menu bar has no Find command yet; add "Search…" (⌘K) to the app's commands when the Mac phase adds a `Commands` builder.
