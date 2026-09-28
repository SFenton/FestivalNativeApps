# Rivalry — Android notes

> **What:** Android state of `/rivals/:rivalId/rivalry`. **Read when:** changing `RivalryScreen` in `android/`. Full Rivals notes: [../rivals/android.md](../rivals/android.md).

- Shares Rival Detail's view model type and cached read (same scope and live-fallback flag on the route), then shows one category (`mode`; unknown keys show the key as title and the empty state, as on the web).
- Native sort menu (`RivalrySort`: Default, Closest Gap, Your Biggest Leads, Their Biggest Leads, Title); the web has none and the service `sort` stays `closest`.
- Full head-to-head rows (You | rank and score gap pills | Them), 1–2 columns split at a separating hinge.
