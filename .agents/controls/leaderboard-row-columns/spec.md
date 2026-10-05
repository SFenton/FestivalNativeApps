# Leaderboard row columns — spec

> **What:** the web's per-section rules for which leaderboard row columns fit and how wide the shared columns are, so rows line up vertically. **Read when:** drawing any leaderboard/rankings section (Song Detail cards, song leaderboards, Leaderboards cards, Full/Band Rankings, Compete) on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md) · [macos.md](macos.md) · [android.md](android.md).

Source: `FortniteFestivalWeb/src/pages/songinfo/components/topScoresLayout.ts` (`resolveTopScoresColumns`), `packages/theme/src/breakpoints.ts` (420 / 520 / 768), `FortniteFestivalWeb/src/pages/leaderboards/helpers/rankingHelpers.ts` (`computeRankWidth`), `FortniteFestivalWeb/src/pages/leaderboard/global/LeaderboardPage.tsx` (`rankWidth`, `scoreWidth` = `${maxLen}ch`), `FortniteFestivalWeb/src/pages/leaderboards/components/RankingCard.tsx`, `.../components/RankingEntry.tsx` (`colRating` min width). Issue #37 (split from #7).

## Web rules

| Section | Width measured | Columns by width |
|---|---|---|
| Song leaderboard (full chart) | viewport | accuracy ≥ 420; season + difficulty ≥ 520; stars ≥ 768 |
| Song Detail top-score card | the card | card < 520 is compact (no accuracy, no season); stars from 768 but `InstrumentCard` never renders them |
| Rankings (cards, full, bands, Compete) | — | rank · name · songs · rating; no score metadata |

- **Rank width** is computed once per section from the longest `#rank` label, including the pinned/spotlight row: `ceil(len("#" + rank.toLocaleString()) × 8.5) + 12` px, 48 px for an empty section. Every row in the section (and on desktop the pinned player row) uses it.
- **Score width** is `${longest score label}ch` across the page (plus the pinned row on desktop).
- **Rating** has a minimum width: `"1,000,000,000"` for total score, otherwise `5ch`.

## Native rule (all platforms)

- One shared helper per platform decides, per section: the visible metadata columns from the measured width (above), and the widest label per shared column (rank incl. pinned/spotlight rows, score, rating). One shared row component sizes those columns from it; rows never measure themselves alone.
- Pinned and spotlight rows share their section's columns on **every** size (operator batch 7.3), not only desktop.
- Accuracy pills stay on score rows at every width (operator batch 7.8) — the 420/520 accuracy gate is not ported.
- The rating column uses the section's widest label instead of reserving `1,000,000,000`, so phone names keep room.
- **Songs played/total (#38):** rankings sections share one songs width (the widest label), like rank and rating. The web always shows songs; on a portrait phone that crowds usernames, so Compete's previews decide once per section whether the songs column fits beside the section's longest name (in its drawn weight, incl. the bold selected row) without truncation, and otherwise hide it on every row. VoiceOver still reads the songs as the row's value. Other rankings sections (overview cards, Full/Band Rankings) always show songs, like the web, except that at accessibility text sizes Windows moves them under the name when the name would otherwise get less than its minimum width (issues #208/#209).
- Widths follow the platform's text scale; at accessibility text sizes rows may stack instead of keeping columns.
- **Row height (#90):** every single-line leaderboard row (score and rankings rows, their loading skeletons, the selected player's row and the pinned/spotlight footer, incl. its loading row) has the web's `Layout.entryRowHeight` (48, `packages/theme/src/spacing.ts`) as a **minimum** height, so rows match across pages and grow with text size instead of clipping. Band score cards (Song Detail band previews and the full band song leaderboard) are one shared card, like the web's `PlayerBandCard` on both pages.
- Difficulty and the stars column are decided but not yet drawn on any native score row (open gap).

## Test matrix

| Case | Expect |
|---|---|
| Phone width (≤ 430) | no season/difficulty/stars; accuracy on |
| 520 ≤ width < 768 | season + difficulty on song boards and top-score cards |
| ≥ 768 | stars on song boards only |
| `#9`, `#10`, pinned `#1,234` | one rank width; names start on the same x |
| Mixed 5–7 digit scores | one score width; scores end on the same x |
| Empty section / invalid ranks | default reference rank width (48) |
| Compete card, longest name truncates with songs | songs hidden on every row of that card; spoken as the row's value |
| Compete card, all names fit with songs | songs shown, one shared songs width |
