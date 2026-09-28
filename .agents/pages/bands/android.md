# Bands landing — Android notes

> **What:** what the Android `/bands` landing implements and why it has no search. **Read when:** changing `ui/bands/BandListScreens.kt` (`BandsLandingScreen`). Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implemented

- Pushed from the drawer (`BandsRoute`, back button). No band-name search: `/api/bands/search` can write on a GET ([service-safety](../../platforms/service-safety.md)); a footnote says so and points to the safe entry points.
- With a selected player: `<Name>'s Bands` preview of the first 6 bands (`GET /api/player/{accountId}/bands?group=all&page=1&pageSize=6`) as band cards, then `View All N Bands` → `PlayerBandsRoute`. The preview view model is keyed by account, so switching players resets it. Loading, inline failure (Retry) and empty states.
- Without a player: a Your Bands card with Select Player (opens the profile sheet).
- Band Rankings: one glass card per size (`<Size> Rankings`, `N-player bands ranked across every song`) → `BandRankingsRoute(wireId)` (screen owned by the Leaderboards lane).
- Layout: one lazy grid with full-width header rows; card columns = ⌊width / 320 dp⌋, forced even when a vertical separating hinge splits the window.

## IDs

`fst.bands.screen`, `.list`, `.subtitle`, `.select-player`, `.your-bands-section`, `.your-bands-list`, `.your-bands` (View All), `.your-bands-empty`, `.rankings.<Band_Duets|Band_Trios|Band_Quad>`, `.footnote`; cards reuse `fst.player-bands.row.<bandId>`.

## Open

- A fixture-mode preview needs a 32-hex selected profile (`SelectedPlayer.validated`), but the mock service's band accounts are `fixture-…` IDs, so device shots show the no-player state; the preview is covered by Robolectric journeys.
