# Song band leaderboard — Android notes

> **What:** what the Android per-song band leaderboard implements. **Read when:** changing `ui/bands/SongBandLeaderboardScreen.kt` or `SongBandLeaderboardViewModel`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implemented

- `SongBandLeaderboardRoute(songId, bandType)` (unknown type → Duos) → `GET /api/leaderboard/{songId}/bands/{bandType}?top=25&offset=` (pure read), validated against song, size and page size. Song Detail's band previews read the same route with `top=10` and, with a selected player, `accountId=` (adds `selectedPlayerEntry`; pure `SELECT`). Rows (`BandScoreRow`) stack the team score under the members below 400 dp and carry an in-card chevron. Debug: `FST_DEBUG_ROUTE=songBandLeaderboard:<songId>[:<bandType>]`.
- Top bar `<Size> Leaderboard`; header 72 dp art, song title as a link to Song Detail, `artist · year`, `<Size> · N entries`. The shared backdrop shows the song's static cover while visible.
- Band size switcher: Material 3 segmented buttons (Duos · Trios · Quads), switching in place and returning to page 1. A size or page change runs the shared load swap (issue #71; spinner `fst.song-band-leaderboard.loading`).
- Rows (glass cards, lazy): rank, each distinct member's instrument icons (keys variants for keyboard songs) + name + per-song member score, team score, gold `FC` outline badge, accuracy, `★ stars`. A row opens `BandRoute(bandId, membersLabel, bandType, teamKey)`.
- TalkBack: one merged `Button` per row with click label "Open band" and `bandScoreAnnouncement`: "Rank N, <member>, <instruments>, <score>, …, band score X, full combo, Y% accuracy, 5 gold stars | N stars" (gold reads as "5 gold stars", never "6 stars"; [star rating](../../controls/star-rating/android.md)). Order: title → search → profile → song link → artist/year → size/entries → size segments ("Selected. Duos. Radio button. 1 of 3") → rows → pinned band ("Open band") → pager.
- Large text (font scale ≥ 1.3, `isLargeText`): a member's score wraps under the name (`BandMemberScoreLine` FlowRow) instead of breaking the name mid-word, and the footer (`BandScoreFooter` FlowRow) wraps accuracy + stars under the team score instead of clipping the stars.
- Hinge: across a **separating** vertical hinge (half-open book/passport fold) `SongBandLeaderboardLayout` puts the song header and size segments on the leading side (`.controls-pane`, scrollable) and the rows and pager on the trailing side (`BandLayout.listSplit`), per the M3 foldables rule "Never place interactive content or critical information across the hinge area". Flat folds (book unfolded, tri-fold) keep one column. Unlike `rememberSingleColumn` pages, the split also applies under TalkBack/large text (band-page convention); verified at font 2.0.
- Shared pager, empty state (`No Band Scores Found` / `No <Size> scores have been recorded for this song yet.`), failure `ServiceStatusView` (fixed height inside the list). Content is centered at ≤840 dp on wide windows.
- Selected player's band (issue #306, web `SongBandLeaderboardPage` `FixedLeaderboardPlayerFooter`): with a selected player the page is read with `accountId=` (same pure read as Song Detail's previews; the view model follows `selectAccount` and re-reads in place, keeping size and page). `SongBandSpotlight` (core) applies the Solo board's rule: the band's row gets the purple selected treatment on its own page, and on every other page it is pinned above the pager (`.spotlight-footer`) as the Solo footer's `ScoreRow` in an `AnchoredRowCard` — rank, joined member names (`LeaderboardNameText` marquee, static under Reduce Motion), season, score, accuracy/FC, stars. It opens `BandRoute` ("Open band"). Nothing is pinned without a selected player, without a band score at that size, or for a response for another player/size. The footer and pager are the shared `AnchoredBoardList` (bottom-anchored, rows fade and leave touch/TalkBack beneath it); around a separating hinge they anchor in the rows pane.

## Validation (issue #103, live service)

Seven Nation Army (Duos 9,952 · Trios 9,970 · Quads 9,983) and Butter; captures in the issue.

| Configuration | Result |
|---|---|
| FST_Phone portrait / landscape, font 1.0 / 2.0 | OK after fixes (stars clipped and names broke mid-word at 2.0 before). Title ellipsizes at 2.0 (`Quads Leader…`): standard single-line M3 top app bar, accepted. Pager 1 → 2 returns to the top. |
| FST_Tablet landscape / portrait, font 2.0 | OK; navigation rail/drawer, ≤840 dp centered column. |
| FST_Resizable phone · foldable · tablet · desktop | OK (bottom bar → rail → drawer). Shell drawer wraps "Leaderboard/s" mid-word at tablet + font 2.0: shared shell chrome, outside this page. |
| FST_Book_Fold folded / half / unfolded | Half-open: rows and the selected segment straddled the hinge → fixed with the split. Folded font 2.0 and unfolded OK. |
| FST_Passport_Fold folded portrait / landscape, half, unfolded | OK (split in half-open; compact-height landscape scrolls under the header). |
| FST_TriFold folded / partial / unfolded, font 2.0 | OK (flat fold, single column; rail labels hide at 2.0 per shell). |
| Light theme | No effect: the app is dark-only by design ([design/android.md](../../design/android.md)), a deliberate deviation from M3 dynamic light/dark. |
| Reduced motion (animator 0) / animations on | Captures ran at animator 0: the size/page swap and backdrop snap (`LoadSwapPolicy`, unit-tested). With animations on, the size switch fades out, spins and staggers rows in. |
| Connected `BandsSettingsJourneyTest` | Passes on FST_Phone and FST_Book_Fold (half). |

## IDs

`fst.song-band-leaderboard.screen`, `.list`, `.bottom-bar`, `.spotlight-footer`, `.song`, `.subtitle`, `.band-type-menu`, `.band-type.<bandType>`, `.row.<bandId>:<rank>`, `.empty`, `.error`, `.pager`, `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- Entry point from Song Detail belongs to the Songs lane. No instrument-combo filter. The pinned band opens the band; web's newer "jump to your page" footer action (#307) is not adopted while Android's Solo footer keeps the open-profile rule.
