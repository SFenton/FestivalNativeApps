# Song Detail — Android notes

> **What:** Android implementation state and decisions for Song Detail and the full song leaderboard. **Read when:** changing Song Detail on Android (`ui/songdetail/`). Behavior: [spec.md](spec.md).

## Implemented

- `SongDetailRouteScreen` wires the view model with shared Shop, selected-profile and Settings state; the shell calls it for both the pushed route and the two-pane detail.
- Song resolved by ID (debug: or exact title) against the current catalogue; header art + title + `artist · year · duration` (+ album); the shared backdrop shows the song's static cover.
- Header actions: **Paths** (only when a visible, charted, non-Karaoke chart exists) and, for a same-publication Shop offer, the **Item Shop** official-link pill (validated host only), which breathes in the status colour (green / gold New / red Leaving, web `shopBreathe*`, 3 s; static under reduced motion). No separate New/Leaving chip (operator rule); the status is in the pill's spoken label. A failed Shop read shows `fst.song-detail.shop-error`; a hidden Shop shows neither.
- Intensity card: every **charted** instrument (even hidden ones).
- Band Leaderboards chips (Duos/Trios/Quads → `SongBandLeaderboardRoute`).
- One lazily-started ten-row preview per **visible** charted instrument; with Filter Invalid Scores on the read adds `leeway=` (`data/songs/FestivalApiSongs.leaderboardPage`) and previews are keyed by leeway so a change re-reads.
- Each card's instrument header (icon, name, "N total entries") sits above the card. With a selected player each card shows a gold **Your score** line (`SongDetailSummary`: score · accuracy · FC · Top N% · #rank, or loading/syncing/paused/failed/no-score text; under Filter Invalid Scores the effective score, marked "next valid score"), highlights the player's row, adds the player as **row eleven** when outside the top ten (`fst.song-detail.your-rank.<chart>`, opens the page containing it), then a full-width purple tonal **View full leaderboard** and **View {chart} Score History** (`PlayerHistoryRoute`). Content fades in as it loads (`festivalFadeIn`).
- The full board (`SongLeaderboardRouteScreen`) reads with `leeway=` while Filter Invalid Scores is on and pins the player's next valid score.
- Preview rows open the player (`RankingNavigation.playerRoute`); rows with no account read **Unknown User** and are not interactive.
- Paths sheet: see [chopt-paths/android.md](../../controls/chopt-paths/android.md).

- PWA gap fixes (2026-09-28): a compact header (56 dp art, marquee title and "artist · year · length", no album line) is pinned as a sticky header; **View Paths** is a dock action (floating toolbar on phones, top bar elsewhere; the button stays in the header actions inside the two-pane detail); intensity is a two-column icon grid below 600 dp (label in each cell's TalkBack text); order is intensity → instrument leaderboards → band leaderboards; score rows show the score, then the accuracy badge (gold for FC, "Full combo" spoken); an empty chart reads "No scores recorded yet". The full board's header is an instrument switcher (menu of visible charted instruments).

## Open

Selected-player history chart on the page, promoted band previews, scrolling to an initial instrument, Quick Links (Song Detail is not a lazy list of sections yet).
