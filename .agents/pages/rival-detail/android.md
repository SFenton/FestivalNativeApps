# Rival Detail — Android notes

> **What:** Android state of `/rivals/:rivalId`. **Read when:** changing `RivalDetailScreen` / `RivalDetailViewModel` in `android/`. Full Rivals notes: [../rivals/android.md](../rivals/android.md).

- Resolves the route's scope with `RivalScopes.resolveDetail` (leaderboard, one or more merged song scopes, Settings fallback); `allowLiveFallback` only from Find Rival.
- Header "You vs. Name" + web `rivals.detail.summary`; the web's six categories (`RivalCategorization`, same keys, split rules and descriptions) as cards of five songs with sentiment-tinted headings, See All → Rivalry forwarding scope and live-fallback flag.
- Toolbar: Quick Links (shared `QuickLinksAction`; web `rival-category:<key>` items with the category titles, `RivalQuickLinks.rivalDetail`; the web shows them only on mobile chrome, Android at every size like Song Detail; the shared rule needs 2+ categories) and View Profile (`PlayerRoute`). Song rows open Song Detail; the catalogue is read best-effort for year and artwork. No song data → "No song data for this rival."
