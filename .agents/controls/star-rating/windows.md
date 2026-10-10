# Star rating — Windows notes

> **What:** WinUI 3 implementation, design decisions and validation results. **Read when:** drawing or announcing stars on Windows. Spec: [spec.md](spec.md).

## Implementation

- `windows/Festival.Core/Domain/StarRating.cs`: `StarRating.From(int?)` maps a wire count to its drawing: 1–5 white images, **6 or more** gold (web `MiniStars` `starsCount >= 6`), and `null` for 0, negative or missing (every web call site guards `stars > 0`, so the web's `max(1, n)` floor only ever applies to 1). `Announcement` ("1 star", "4 stars", "5 gold stars"), `StateName` (`white-1`…`white-5`, `gold-6`) and `AutomationId` (`fst.star-rating.<state>`) are unit-tested in Core (`StarRatingTests`).
- `windows/Festival.App/Controls/StarRow.cs` is a horizontal `StackPanel` of 1–5 bundled `Assets/Stars/star_white.png`/`star_gold.png` images, each in a round `Border` (circle = 1.25 × `StarSize`, 2 epx spacing). One decoded bitmap per colour is shared app-wide. Nothing to draw collapses the row.
- Gold stars get a 1.5 epx ring in `FSTEmphasisBrush` (gold; WindowText under a contrast theme). The ring is set from code, so the row subscribes to `ContrastTheme.Changed` on `Loaded` (unsubscribes on `Unloaded`) and re-applies **only the ring**: visibility belongs to the host (`PlayerStatTileView` hides its gold row below a six-star average).
- UI Automation: one `Image` element (class `StarRow`, no children; the images are `Raw`) named with `Announcement`, `ItemStatus` = state name and AutomationId `fst.star-rating.<state>` (the per-state ID replaced the old shared `fst.stars`, so a driver's first-match lookup can't hit a recycled row of another state). A collapsed row clears its name, status and ID. A tooltip repeats the announcement. Never a tab stop.
- Hosts and how they read: song and band song leaderboard rows (`LeaderboardEntryRow`, `SongBandPreviewRowView`, `BandsSongLeaderboardPage`) set the row `Raw` and put `StarRating.Announcement` at the end of the row button's name. Score History rows do the same. The profile/band Avg Stars tile reads "Avg Stars: 5 gold stars". Songs rows' metadata slot is `Raw`. Suggestion rows keep the image as a child of the row button, like their sibling metadata pills. All Core announcement sites use `StarRating.Announcement`: they used to say "6 stars" (leaderboards, band leaderboards, history; history also said "0 stars") or "gold stars" (Suggestions).
- Song leaderboard rows show the stars column only from 700 epx (page design, [song-leaderboard/windows.md](../../pages/song-leaderboard/windows.md)). Below that the row name still speaks them.

## Design decisions (winui-design)

- `winapp find-ui "rating stars"` returns only `RatingControl`, an interactive input with its own glyphs. The spec requires the web's bundled star images, read-only, never glyphs, so the control stays custom (a deliberate deviation from "prefer system controls").
- `theme-accessibility.md`: inline brush assignments don't follow `{ThemeResource}` on a contrast switch, hence the `ContrastTheme.Changed` re-apply. No `Opacity` on system-colour brushes.
- Colour is never the only signal: gold also differs by ring and image, and the name says "gold".
- The images are graphics, so they keep their size at text 200% (WCAG 1.4.4 covers text); the spoken count carries the information.
- Strings are English-only, like every Core view-model string (no `x:Uid`/`.resw` in this repo yet). The 1.5 epx ring and 2 epx spacing match the web `MiniStars` outline rather than the 4 epx grid.
- Dark-only app theme: the light system theme still renders dark (see [design/windows.md](../../design/windows.md)).

## States and reachability

| State | Reached by | Evidence |
|---|---|---|
| `white-1` | Score with 1 star (fixture leaderboard rank 3) | `journeys/star-rating.json` `stars-leaderboard-*` (`assertstatus:id=fst.star-rating.white-1`, row name "…, 1 star") |
| `white-5` | Score with 5 stars (rank 2) | Same journeys (`white-5`, row "…, full combo, 5 stars"); rank 7 covers `white-3` |
| `gold-6` | 6 or more stars (rank 1 = 6, rank 5 = 7) | Same journeys (`gold-6`, row "…, 5 gold stars"); Core `From_AboveSixIsGold` |
| `minimum-one` | The 1-star floor: 1 draws one image; 0 (rank 4) and missing (rank 6) draw nothing and add no stars to the name | Journeys (rank 4/6 names end without stars) + Core `From_MissingOrInvalidDrawsNothing` |
| `gold-average` | Profile instrument Avg Stars = 6 (`/player/fixture-player-1`, every score six stars) | `stars-gold-average`, `stars-gold-average-compact` ("Avg Stars: 5 gold stars", `gold-6`) |

Run: `python tools/windows/ui_journey.py tools/windows/journeys/star-rating.json` (6 journeys: leaderboard compact/medium/wide/maximized, gold average medium/compact; each names `star_rating_fixture.py` in its `fixture` list, so CI runs it with no flag, issue #529). Row names follow [score-accuracy](../score-accuracy/windows.md): `season N` from 520 epx and `accuracy unavailable` for an FC-only row. The fixture wraps `mock_service.py` and rewrites `fixture-*` Lead leaderboards by rank and fixture-player-1's scores. A11y matrix pages: `journeys/a11y-star-rating.json` (`stars-gold-average-quick-links` reaches the Lead tiles at text 200%, where the virtualized section isn't realized until you jump or scroll to it).

## Validation (issue #221, 2026-10-04)

Debug x64 on the 3840×2160 300% host, console locked (UIA patterns only). Fixture: `a11y_matrix.py --scan --tabs 20` with `a11y-star-rating.json`. Live: the public service without `--base-url`.

| Configuration | Result |
|---|---|
| Compact / medium / wide, maximized, snap-left (fixture) | Axe 0 everywhere. Tab stops: leaderboard 7 (compact, snap-left) / 9, profile 17–19; StarRow never a stop. Correct counts, colours and rings; compact hides the leaderboard stars column (page design) and keeps them in the row name |
| Live public service, anonymous (Believer Bass at wide: rank 1 `white-2` "2 stars" above `gold-6` "5 gold stars" rows; Butter Lead at medium: `white-5` above gold; SFentonX profile Lead Avg Stars `gold-6` "Avg Stars: 5 gold stars" via Quick Links) | Same rendering, IDs and names as the fixture |
| High contrast Desert, Night sky, Aquatic (compact, wide) | Axe 0. Gold ring follows WindowText; white-star outlines stay legible on Desert's light background |
| Light / dark system theme | Axe 0; the app stays dark (deliberate) |
| Text 200% (compact, medium, wide) | Axe 0; rows keep the stars column at wide; stars stay image-sized |
| Display 100% / 150% (compact, wide) | Axe 0 after the profile fix below (before: 4 `SiblingUniqueAndFocusable` errors at wide); crisp images |
| Keyboard | Stars are never focusable; rows read the stars at the end of their name |

Fixed:
- Six-star scores were read as "6 stars" (leaderboards, band leaderboards, Score History) or "gold stars" (Suggestions); they now read "5 gold stars", like the control.
- Seven or more stars drew white; now gold, like the web.
- `StarRow` had no automation peer, so Suggestions and the profile tile exposed nothing for it; it is now one named `Image` with a state ID and status.
- The gold ring kept its old brush after a contrast-theme switch until you navigated away.
- Profile (found by this pass): instrument tiles were unnamed siblings of the Overview tiles with the same names; each instrument section is now a named group ([player-profile/windows.md](../../pages/player-profile/windows.md#ids)).

The console was locked, so Narrator itself wasn't run. Reading order was checked from the UIA tree: Button "Rank #1, Fixture Player 1, 99,900 points, 98% accuracy, 5 gold stars" > (Raw) StarRow; Group "Lead" > Button "Avg Stars: 5 gold stars" > Image "5 gold stars" (`fst.star-rating.gold-6`).
