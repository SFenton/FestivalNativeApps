# Player Bands — Android notes

> **What:** what the Android Player Bands page implements. **Read when:** changing `ui/bands/BandListScreens.kt` (`PlayerBandsScreen`) or `PlayerBandsViewModel`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implemented

- `PlayerBandsRoute(accountId, displayName?)` → `GET /api/player/{accountId}/bands?group=&page=&pageSize=25` (pure read). The account must be 1–128 `[A-Za-z0-9_-]` (`BandText.isValidMemberId`, which also admits fixture IDs); otherwise the page shows "Player not found" and sends nothing.
- Top bar `<Name>'s Bands`: route name → selected player (same account) → the account's own member row → `Player Bands`. Subtitle `<Group> · N bands`.
- Group filter: Material 3 single-choice segmented buttons (All · Duos · Trios · Quads) instead of the web filter sheet; switching returns to page 1. A newer load cancels an older one, so a late response never shows an old group or page. A group or page change runs the shared load swap (issue #71; spinner `fst.player-bands.loading`), and the cards stagger in.
- Band cards (glass, whole card tappable, no chevron): distinct members with instrument icons, size pill, `N appearances` → `BandRoute(bandId, membersLabel, bandType, teamKey)`. Anonymous members (empty `accountId`) show "Unknown User" and never collapse into each other.
- Adaptive grid (`BandLayout.grid`): as many ≥320 dp columns as fit (1 on phones and covers, 2 on book/passport inner and tablet portrait, 3+ wide). With a separating vertical hinge, or a flat fold where two columns fit anyway, exactly two columns whose gutter is the fold ±16 dp, so no card straddles the crease.
- Pager: First/Previous/`page / pages`/Next/Last (48 dp targets, spoken "Page X of Y"), hidden for one page. A page past the end reloads the last page.
- States: loading, empty (`No bands found` / `No <group> have been recorded for this player yet.`), failure (`ServiceStatusView` at a fixed height inside the grid, because a lazy item cannot host its unbounded vertical scroll).

## IDs

`fst.player-bands.screen`, `.list`, `.subtitle`, `.group-picker`, `.group.<all|duos|trios|quads>`, `.row.<bandId>`, `.empty`, `.error`, `.invalid`, `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- Entry points from the player page: its Bands section ("See all", "View all bands (N)"; [player-profile/android.md](../player-profile/android.md#bands-section)). No `?name=` carry-through (band search is blocked).
