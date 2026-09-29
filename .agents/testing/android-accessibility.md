# Android accessibility results

> **What:** the Android accessibility phase: tools, what was checked on which device, findings, fixes and open gaps. **Read when:** changing semantics, touch targets, colours or multi-column layouts on Android, or re-running the TalkBack/ATF passes. Tooling: [android.md](android.md#accessibility-tooling).

## Method

| Check | How | Devices |
|---|---|---|
| Accessibility Test Framework (touch targets ≥ 48 dp, labels, contrast, duplicate/redundant text) | 16 instrumented journeys in `androidTest/.../journeys/` (Songs, Sort/Filter, Song Detail, Paths, song board, Shop, Suggestions, Statistics, Leaderboards, Full Rankings, Rivals hub/detail/rivalry, Compete, Bands, Band Detail, song band board, Settings, Licenses, drawer, profile sheet, global search, notifications, first run, What's New); ATF on every interaction and screen | FST_Phone; FST_Book_Fold `--posture half` |
| TalkBack reading order and speech | `tools/android/talkback_walk.py`: real TalkBack, "next item" key chord, utterances from TalkBack's own log | FST_Phone (Songs, Song Detail, Settings, Statistics, Leaderboards, Full Rankings, Rivals, Compete, Suggestions, Item Shop); FST_Book_Fold half-open (Song Detail, Leaderboards, Settings) |

Status (2026-09-29, FST-and-next): all 16 journeys pass with **no ATF errors** on both devices. Walk reports (`<device>-<screen>.md`) are in the showcase folder `and-next/a11y/talkback/`, ATF logs in `and-next/a11y/`.

## Findings and fixes

| Finding | Where | Fix |
|---|---|---|
| Leaderboard rows 45 dp tall (ATF touch target) | Song Detail previews, full song board (`ScoreRow`) | Minimum height 48 dp |
| White on `#2D82E6` is 3.86:1 (ATF contrast) | Filled buttons (Settings "Show", first run Next/Done, What's New, Retry, Done, profile Select/View, Licenses Close) | `BrandTokens.accentBlueFill` `#1A6FD8` (4.9:1) via `festivalFilledButtonColors()`; `accentBlue` stays for blue text on dark surfaces (no single blue passes both) |
| Song board rows were two stops (unlabelled clickable + inner merged row) | Full song leaderboard, Song Detail previews | `ScoreRow` no longer merges; the clickable wrapper (or `mergeDescendants` for anonymous rows) is the one stop |
| Summary read, then every child text again | Score History rows, band rows, Item Shop rows/grid, See All buttons | `clearAndSetSemantics` (history rows), inner content hidden (band rows, shop grid), description removed where it only repeated the texts (shop list), See All text hidden behind its description |
| Decorative pieces read as stops | Chart legend, Rank History axis dates (profile and Leaderboards), profile avatar initials | Hidden from TalkBack (the chart description names them) |
| Title and explanation as two stops | Song Detail/band empty states, Compete empty cards, band empty states | One merged stop |
| CHOpt column-order items read as bare "Note"/"Beat" | Settings | One stop "Note, position 1 of 5" with Move up/Move down actions |
| Side-by-side cards read row by row across both cards | Two-column Song Detail, Leaderboards, Rivals, Compete, profile, Suggestions | `readingGroup()` (traversal group) on `GlassCard`, `CardGridRow` cells and grid items |
| On a half-open fold TalkBack skipped the off-screen rest of a tall leading card (it only visits on-screen items and moved to the trailing column) | Song Detail, Leaderboards (and any multi-column grid) | While TalkBack runs (`rememberScreenReaderOn`) these grids use one column; the hinge split is dropped for TalkBack users |
| Pager arrows had no role | Rank History pagers | `Role.Button` |
| Settings subsection titles not headings | "CHOpt Path Default View", "CHOpt Text Path Column Order" | `heading()` |

ATF warnings left as is: "Tap Vocals" is an instrument name, not an instruction; "Profile: Selected Player" is a fixture name; duplicate speakable text comes from fixture rows that are identical by construction and from repeated per-chart controls (pager arrows, "View All Rivals"), which TalkBack disambiguates by their section heading.

## Reading order (TalkBack, verified)

Top app bar (Back, title, page actions, Search, Notifications, profile) → page content in visual order, headings marked → navigation bar/rail tabs ("Songs, tab 1 of 5") → floating toolbar page actions (Paths, Quick Links). On a wide window the rail comes before the content. Quick Links announce the current section.

## Open

- The walker cannot continue past a focused text field (the field keeps the "next item" key chord), so the Songs walk stops at its search box. Songs was checked with ATF and the reading-order dump instead.
- The navigation rail's profile item reads "Profile: <name>, Profile" (description plus label).
- Not yet walked with TalkBack: Band Detail, Suggestions filter, Paths sheet, sheets and dialogs (ATF-checked only); passport, tri-fold and tablet form factors.
- Bottom sheets expose Material's unlabelled 84×127 px sheet area next to the drag handle (ATF accepts it; from `ModalBottomSheet`).
