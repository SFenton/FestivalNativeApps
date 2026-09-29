# Player Bands — Windows notes

> **What:** what the Windows Player Bands page implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/BandsPlayerBandsPage*`, `PlayerBandsViewModel` or `BandCardView`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Route `AppRoute.PlayerBands(accountId)`; read `GET /api/player/{accountId}/bands?group=&page=&pageSize=25` (pure: `GetPlayerBandsList` returns an empty page instead of rebuilding its projection).
- Title `<Name>'s Bands` from the selected player (same account) or the account's own member row; otherwise `Player Bands`. Subtitle `<Group> · N bands`.
- Group filter: Fluent `SelectorBar` (All Bands · Duos · Trios · Quads) instead of the web's filter sheet; changing it returns to page 1.
- Cards (`BandCardView`, `UniformGridLayout` min 320 epx: one column compact/medium, 2–3 wide): distinct members with name and 28 px instrument icons, band-size pill, `N appearances`, chevron. The card opens `AppRoute.Band(bandId, bandType, teamKey)`.
- Paging: the shared board pager (`LeaderboardsPager` over `IBoardPager`, operator batch 7.4; floating over the cards), hidden for one page; a page past the end (list shrank) reloads the last page. Late responses for an older group/page are discarded.
- States: loading ring, empty (`No bands found` + `No <group> have been recorded for this player yet.`), failure (`ServiceStatusView`, Retry).

## Evidence

Fixture screenshots (mock service, compact/medium/wide): `windows/reports/screenshots/player-bands-{compact,medium,wide}.png`. At compact (500 epx) the shell keeps the navigation pane open, leaving ~340 epx of content; pages switch to a smaller title below 560 epx page width.

## IDs

`fst.player-bands.screen`, `.title`, `.subtitle`, `.group-picker`, `.group.<all|duos|trios|quads>`, `.list`, `.row.<bandId>`, `.empty`, `.error`, `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- No `?name=` title carry-through (band search is blocked, so no safe source).
- Entry point from the player profile page is owned by the Profile lane (`AppRoute.PlayerBands`).
