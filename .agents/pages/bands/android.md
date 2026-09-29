# Bands (`/bands`) — Android notes

> **What:** what Android shows for `/bands` without a band id and where bands are reached instead. **Read when:** changing `ui/bands/BandListScreens.kt` (`BandNotFoundScreen`) or `BandsDestinations.kt`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implemented

- `BandsRoute` (`/bands`, no id) shows the web's `BandPage` empty state: **Band not found** / "This band link is missing an ID and cannot be resolved." (web `band.notFound` / `band.missingId`), with back. No request is made (orchestrator decision 2026-09-28, PWA gap 5; replaces the earlier landing with a player-bands preview and Band Rankings links).
- No band-name search anywhere: `/api/bands/search` can write on a GET ([service-safety](../../platforms/service-safety.md)). Bands are reached from a player's band list ([Player Bands](../player-bands/android.md)), Band Rankings, a song's band leaderboard and global search (Bands scope explains the missing search and links Band Rankings). The drawer has no Bands row (web sidebar parity).

## IDs

`fst.bands.screen`, `fst.bands.not-found`.

## Open

- The Leaderboards overview's Bands header (`ui/leaderboards/LeaderboardsScreen.kt`, FST-and-boards2) still pushes `BandsRoute`; it should link to Band Rankings instead (reported to the orchestrator).
