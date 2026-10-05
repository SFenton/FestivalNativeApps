# Player Bands — Windows notes

> **What:** what the Windows Player Bands page implements, its validation and its open gaps. **Read when:** changing `windows/Festival.App/Pages/BandsPlayerBandsPage*`, `PlayerBandsViewModel` (`BandsPlayerBandsViewModel.cs`) or `BandCardView`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Route `AppRoute.PlayerBands(accountId)`; read `GET /api/player/{accountId}/bands?group=&page=&pageSize=25` (pure: `GetPlayerBandsList` returns an empty page instead of rebuilding its projection).
- Title `<Name>'s Bands` from the selected player (same account) or the account's own member row; otherwise `Player Bands`. Subtitle `<Group> · N bands`.
- Group filter: Fluent `SelectorBar` (All Bands · Duos · Trios · Quads) instead of the web's filter sheet; changing it returns to page 1.
- Cards (`BandCardView` in `LeaderboardsCardGridLayout`, min 320 epx, at most 3 columns; each row is as tall as its tallest card, non-virtualizing): distinct members with name and 28 px instrument icons, band-size pill, `N appearances`, chevron. The card opens `AppRoute.Band(bandId, bandType, teamKey)`. It is one Narrator stop named `View band: <member>, <instruments>; …. <Size>, N appearances`; its parts are Raw.
- Paging: the shared board pager (`LeaderboardsPager` over `IBoardPager`, operator batch 7.4; floating over the cards), hidden for one page; a page past the end (list shrank) reloads the last page. Late responses for an older group/page are discarded.
- Footer edge (issue #305): cards fade out over 40 epx above the floating pager and are hidden beneath it, matching the web's page scroll mask over `useLeaderboardFooterScrollMargin` and every other board ([scroll-edge](../../patterns/scroll-edge.md) R9). `BoardFooterFade.Attach(BoardFadeSource, BoardFadeHost, Footer, Scroller, FooterPlate)` draws it. Under a contrast theme a window-colour `FooterPlate` replaces the fade. With one page the pager is collapsed and nothing is drawn.
- States: loading ring, empty (`No bands found` + `No <group> have been recorded for this player yet.`), failure (`ServiceStatusView`, Retry).
- Load-swap gate (issue #71): first load, group changes and paging run the shared web sequence (300 ms content-out, centered ring, 500 ms ring-out, card stagger). New cards/empty/error state commits while hidden; rapid choices are latest-wins. Reduce Motion swaps immediately.

## Evidence

Fixture screenshots (mock service, compact/medium/wide): `windows/reports/screenshots/player-bands-{compact,medium,wide}.png`. At compact (500 epx) the shell keeps the navigation pane open, leaving ~340 epx of content; pages switch to a smaller title below 560 epx page width.

## Validation (issue #210)

Checked 2026-10 with the winui-design and winui-code-review skills, `a11y_matrix.py` (fixture `fixture-player-1`: 18 duos, 8 trios and 4 quads over two pages) and the live public service (SFentonX, 125 bands, through a temporary wrapper without `--base-url`). Axe.Windows reported 0 errors in every row, and no Tab walk repeated a stop or left the app.

| Configuration | Finding |
|---|---|
| Compact (500 epx), snap-left, snap-right | Single column. Tab: pane toggle → search → profile → group picker (one stop, arrows move between groups) → cards (one stop, arrows between cards) → Next/Last page → Back. |
| Medium (900), wide (1440, clamped by the 300% desktop), maximized | Two or three columns. **Fixed:** `UniformGridLayout` sized every card from the first one, so on a page that starts with a duo, the trio and quad cards lost their third and fourth members, the size pill and the appearances line (live: SFentonX's first page). The grid also virtualized cards below the fold, so `scrollinto` could not reach them. It now uses `LeaderboardsCardGridLayout` (row height = tallest card, non-virtualizing, at most 25 cards per page). |
| Keyboard only | `kb-player-bands` (compact): group picker → Tab to the first card → Down to the next → Tab to Next page → Enter pages; Shift+Tab from a card returns to the picker and Right selects Duos (focus and selection move together); Enter on a card opens Band Detail and Alt+Left returns. The focus rectangle shows on every stop. |
| High Contrast (Desert, Night sky) | **Fixed:** the size pill kept a fixed navy fill behind system text. It now uses `FSTMutedPillFillBrush` (ButtonFace) with a ButtonText border and text. |
| Light and dark system theme | Same rendering, a deliberate deviation: the app is dark only ([design/windows.md](../../design/windows.md#content-branded-fluent-tokens)). |
| Text 200% | Cards grow with the text; rows keep every member (live and fixture). The pager floats over the last row as on every paged board. |
| Display 100% / 150% | Correct. |
| Narrator / UIA | **Fixed:** scan mode read each card twice (the button name, then every name, icon, pill and count). The parts are Raw, and the card name reads `View band: <member>, <instruments>; …. <Size>, N appearances`. **Fixed:** `.empty` sat on a panel (no UIA peer); it is now on the "No bands found" heading (level 2). SelectorBar items expose SelectionItem with the selected state. |
| Empty, failure | `player-bands-empty` (all groups and Quads copy) and `player-bands-error` (`fst.service-status.retry`, Retry) pass on fixtures only; the live service has neither state for a real player. |

Journeys: `player-bands-mixed-sizes`, `player-bands-empty`, `player-bands-error` (bands.json) and `kb-player-bands` (a11y-keyboard.json) pass. `player-bands-groups-paging-detail` passes its Player Bands steps (group changes now use `select:` because real clicks miss on a locked console). Its Band Detail tail times out after Quick Links → Songs because the page does not scroll to the songs section. That also happens on the unchanged base build, so it belongs to the Band Detail page, not this one.

## IDs

`fst.player-bands.screen`, `.title`, `.subtitle`, `.group-picker`, `.group.<all|duos|trios|quads>`, `.list`, `.row.<bandId>`, `.empty` (on the "No bands found" heading), `.error` (failure is matched by `fst.service-status.*`), `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- No `?name=` title carry-through (band search is blocked, so no safe source).
- Entry point from the player profile page is owned by the Profile lane (`AppRoute.PlayerBands`).
