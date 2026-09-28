# Bands landing — Windows notes

> **What:** what the Windows `/bands` landing implements and why it has no search. **Read when:** changing `windows/Festival.App/Pages/BandsPage*` or `BandsLandingViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- No band-name search: `/api/bands/search` can write server state on a GET ([service-safety](../../platforms/service-safety.md)). A caption explains this.
- With a selected player: `<Name>'s Bands` section previewing the first 6 bands (`GET /api/player/{accountId}/bands?group=all&page=1&pageSize=6`) as `BandCardView` cards, a `View All N Bands` link to `AppRoute.PlayerBands`, and loading/empty/failure states. It follows selection changes live and discards a preview for a previous player.
- Band Rankings: one card per size (Duos/Trios/Quads with a one-line description) opening `AppRoute.BandRankings(bandType)`.

## IDs

`fst.bands.screen`, `.title`, `.your-bands-section`, `.your-bands` (View All link), `.your-bands-list`, `.your-bands-empty`, `.rankings.<Band_Duets|Band_Trios|Band_Quad>`, `.footnote`.

## Open

- Not reachable from the navigation pane yet: needs a link from the Leaderboards overview (Leaderboards lane) or a pane/drawer item (TODO(orchestrator): shell placement for Bands, Item Shop and other drawer destinations).
