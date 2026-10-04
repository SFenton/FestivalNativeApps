# Star rating — Android notes

> **What:** Compose implementation, validation and evidence. **Read when:** changing the star row or its hosts on Android. Spec: [spec.md](spec.md).

## Implementation

- `ui/design/StarRating.kt` `StarRating(stars, size, gold, style)` draws the bundled web images (`res/drawable-nodpi/star_white.png`, `star_gold.png`) from `core/format` `StarRatingSpec` (count, gold and spoken label are unit-tested): 1–5 white stars, **at least one** (web `MiniStars` `Math.max(1, …)`), or five gold stars for 6+ or `gold = true` (a perfect average of six). One TalkBack element: `contentDescription` "1 star" / "N stars" / "5 gold stars", `Role.Image` (ImageView class on device), not focusable or clickable.
- Two styles, matching the two web components:
  - `Inline` (web `GoldStars` and leaderboard rows): plain images 2 dp apart. Leaderboard, Song Detail, Player History, Suggestions and the profile Avg Stars tile use it at 20 dp.
  - `Mini` (web `MiniStars`, Song row metadata only): each star centred in a circle 1.2× its edge, 3 dp apart, with a 1.5 dp `BrandTokens.gold` ring when gold. Song rows size it from the pill height (`PILL_HEIGHT / 1.2`). Leaderboards keep `Inline`: their stars column is 116 dp (`LeaderboardColumnLayout.STARS_WIDTH`), and Mini needs 132 dp.
- Hosts that mean "no stars" (Song Detail, Player History and Suggestions rows with 0 or missing stars) don't compose the row, because 0 would draw the minimum-one star. Labels elsewhere (the Songs Stars pill, First Run demo data, Player History announcements, band score rows) come from `StarRatingSpec`, so speech always matches the row. The Songs filter's stars buckets keep their own "Gold stars" / "N stars" switch labels.

## Validation (issue #128, 2026-10-05, live public service)

Live board: "Oh Shhh..." Pro Drums (`Solo_PeripheralDrums`), whose six entries have 6, 5, 4, 3, 2 and 1 stars. Songs: profile `SFentonX` filtered to Lead (all gold).

| Configuration | Result |
|---|---|
| FST_Phone portrait, landscape; font 1.0 and 2.0 | Songs rows show the Mini circles with the gold ring. At 2.0 the stars keep icon size and wrap to their own line without clipping. The portrait leaderboard has no stars column (row < 700 dp, web breakpoint). Landscape Song Leaderboard shows no rows (header and pager fill the 411 dp height): a page issue tracked in #190, not the control |
| FST_Phone light theme | Identical: the app theme is dark-only by design |
| FST_Tablet landscape, portrait (+ font 2.0) | Landscape board: white 1–5 and gold 5 in order, TalkBack labels "5 gold stars", "5 stars" … "1 star". Portrait at font 2.0: rows narrower than 700 dp drop the stars column and reflow without clipping. Songs list-detail Mini stars |
| FST_Resizable phone / foldable / tablet / desktop (+ font 2.0) | Phone and foldable rows < 700 dp: no stars column. Tablet and desktop: all six rows' stars. Desktop at font 2.0: rows stack and keep the stars after the season |
| FST_Book_Fold folded / unfolded | Folded Songs: Mini gold stars on the row's second line. Unfolded board: all six rows' stars. Unfolded Songs list-detail: stars wrap under the pills |
| FST_Passport_Fold folded / unfolded (+ font 2.0) | Folded Songs: Mini row inline with the pills. Unfolded the board row is just under 700 dp, so no stars column (by design). Unfolded Songs at 2.0: Mini stars stay on one line |
| FST_TriFold folded / partial / unfolded | Unfolded board: all six rows' stars. Partial (≈ 600 dp pane): no stars column. Folded and unfolded Songs: Mini gold stars |
| `minimum-one`, `gold-average` | Not reachable with live leaderboard rows (the service sends 1–6; SFentonX doesn't average 6.0). Covered by tests only |

Accessibility: no animation (reduced motion n/a; device tests run at animator scale 0). The row isn't interactive, so it has no touch target (Accessibility Test Framework passes). The images are icons and don't scale with font size. The count is always in the spoken label, so colour isn't the only cue for gold.

## Fixed in #128

- Gold rows read "Gold stars" with no count. They now read "5 gold stars" (spec), including band score rows and the profile Avg Stars tile.
- 0 stars drew an empty row. It now draws the web's minimum one, and no-star hosts guard instead.
- Song row metadata lacked the web `MiniStars` circles and gold ring.
- First Run demo and Songs Stars pill labels could read "1 stars".

## Material 3 deviations (deliberate)

Reviewed against the `material-3` skill (Compose). The spec mandates the web's star images and brand gold (#FFD700) instead of Material icons and colour-scheme roles (the skill's "hardcode colors" anti-pattern doesn't apply to brand artwork). The row is a non-interactive image (`Role.Image`), not a `RatingBar`-style input, so it has no 48 dp target.

## Tests

- `StarRatingSpecTest` (JVM): counts, minimum one, gold for 6+ or forced gold, singular and plural labels.
- `StarRatingUiTest` (Robolectric): every reachable state (`white-1`, `white-5`, `gold-6`, `minimum-one`, `gold-average`) is one image element with its label. It also checks:
  - Each slot's centre pixel is white or gold artwork.
  - Inline geometry: N × 20 dp plus 2 dp gaps.
  - Mini geometry: 24 dp circles, 3 dp gaps, 132 dp; gold-ring pixels only when gold.
  - Font 2.0 keeps the geometry; the row isn't clickable; `starsDescription` matches.
- `StarRatingDeviceTest` (connected): Inline and Mini reading order and ImageView class with ATF, plus font scale 2 geometry, with whole-pixel tolerance at fractional densities. Passed on FST_Phone, FST_TriFold folded, FST_Resizable tablet and desktop, and FST_Book_Fold unfolded.
