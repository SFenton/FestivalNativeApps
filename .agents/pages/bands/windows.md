# Bands without an ID — Windows notes

> **What:** what the Windows `/bands` route shows. **Read when:** changing `windows/Festival.App/Pages/BandsPage*`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- `/bands` with no band ID shows the web `BandPage` error state (operator 2026-09-28, [windows-gaps](../../testing/pwa-reference/windows-gaps.md) row 3): page title **Band**, centred **Band not found** and "This band link is missing an ID and cannot be resolved." No hub, no search: `/api/bands/search` can write server state on a GET ([service-safety](../../platforms/service-safety.md)).
- Bands are reached from a player's Bands list (`AppRoute.PlayerBands`) and Band Rankings. The Leaderboards overview's "Browse Bands" link to the old hub was removed; its band-ranking cards remain.

## IDs

`fst.bands.screen`, `.title`, `.not-found`. Journey: `tools/windows/journeys/bands.json` → `bands-not-found`.
