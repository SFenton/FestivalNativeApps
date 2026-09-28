# Rival Detail — Windows notes

> **What:** Windows state of `/rivals/:rivalId`. **Read when:** changing `windows/Festival.App/Pages/RivalDetailPage*` or `RivalDetailViewModel`. Full Rivals notes: [../rivals/windows.md](../rivals/windows.md).

- Reads the scope carried on the route (leaderboard, combo or per-chart merge; no scope merges every visible chart). Summary line = web `rivals.detail.summary`.
- Web categories via `RivalCategorization` (same keys, thresholds and descriptions) in masonry cards; 5 compact song rows each, "View all N songs" → Rivalry with the same scope. Headings are tinted by sentiment.
- View Profile opens `AppRoute.Player(rivalId)`. Song rows open Song Detail on the compared chart; titles/art come from the catalogue when loaded.
