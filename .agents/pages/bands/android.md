# Bands (`/bands`) — Android notes

> **What:** what Android shows for `/bands` without a band id and where bands are reached instead. **Read when:** changing `ui/bands/BandListScreens.kt` (`BandNotFoundScreen`) or `BandsDestinations.kt`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implemented

- `BandsRoute` (`/bands`, no id) shows the web's `BandPage` empty state: **Band not found** / "This band link is missing an ID and cannot be resolved." (web `band.notFound` / `band.missingId`; sentence case like the web), with back. No request is made (orchestrator decision 2026-09-28, PWA gap 5; replaces the earlier landing with a player-bands preview and Band Rankings links).
- **Layout (issue #118):** the message is the shared `FestivalEmptyState` (Title Large heading, Body Large centred supporting text; [design/android.md](../../design/android.md)), not a page-local copy. It sits in a `verticalScroll` column (`fst.bands.not-found.pane`) and is centred in a box at least one viewport tall, so 200% font in landscape scrolls instead of clipping and wrapped lines stay centred. A **half-open vertical fold** keeps the column in the leading pane (`BandLayout.listSplit(rememberBandHinge(...))`); a **tabletop** (separating horizontal fold) centres it in the top half above the fold (`rememberBandTabletopHinge` in `BandComponents.kt`), because the bottom half holds the bottom bar and is the controls area. Flat folds keep one centred column. Material 3 layout reference: "Never place interactive content or critical information across the hinge."
- Band search lives only in global search (issue #320; read-only since the service fix, [service-safety](../../platforms/service-safety.md)): a band result opens the Band page with its `bandType` and `teamKey`. Bands are also reached from a player's band list ([Player Bands](../player-bands/android.md)), Band Rankings and a song's band leaderboard. The drawer has no Bands row (web sidebar parity), and nothing in the app pushes `BandsRoute` (only `DebugLaunch` `route=bands`).

## IDs

`fst.bands.screen`, `fst.bands.not-found`, `fst.bands.not-found.pane`.

## Accessibility

TalkBack (real walk, FST_Phone): "Band" → "Search. Button" → "Choose profile. Button" → "Band not found. Heading" → message → Songs/Leaderboards/Settings tabs → "Back. Button". Top-bar targets are 48 dp; white/near-white text on the dark scheme (or dimmed artwork) passes contrast; Remove animations has no page motion to stop (only the shell's navigation transition). The app uses its dark brand scheme in both system themes (design/android.md), so light and dark render the same.

## Validation (issue #118, live service, 2026-10-03)

| Configuration | Result |
|---|---|
| FST_Phone portrait/landscape, font 1.0/2.0, light/dark | Pass after fix (before: "Band Not Found" title case, left-aligned wrapped lines at 200%, landscape 200% clipped without scroll). |
| FST_Tablet portrait/landscape, font 1.0/2.0 | Pass (rail, centred in content). |
| FST_Resizable phone/foldable/tablet/desktop | Pass (compact bottom bar, medium/expanded rail; foldable preset fold is flat → one column). |
| FST_Book_Fold folded, half, unfolded, tabletop | Pass after fix (before: tabletop text straddled the horizontal fold). |
| FST_Passport_Fold folded, half, unfolded, font 2.0 | Pass (half keeps the leading pane). |
| FST_TriFold folded, partial, unfolded | Pass. |

Frames captured within ~5 s of a posture or `wm size` change can still show the previous window size (whole shell clipped). Launching already in the posture renders correctly, so this is an emulator transition artifact, not a page bug.

## Tests

Robolectric `BandNotFoundUiTest` (copy/heading/centred, no band requests, 200% text, landscape scroll, expanded width, half-open book, flat vertical fold, tabletop, flat horizontal fold) and `BandsUiTest`; connected `BandsSettingsJourneyTest#bandsWithoutAnIdIsAccessibleAndClearOfTheFold` (ATF, reading order, nothing straddles the fold; run on FST_Phone and FST_Book_Fold `--posture half`).
