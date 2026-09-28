# Solo leaderboard — iPhone notes

> **What:** iPhone implementation state and decisions for the Solo chart. **Read when:** changing the Solo page on iPhone. Behavior: [spec.md](spec.md).

- Implemented: 25-row pages via the shared `RankingsPagerView` (also used by [full-rankings/ios.md](../full-rankings/ios.md) and band rankings) — first/previous/info/next/last with ≥44pt actions on an opaque two-row Fluent plate that stays readable over art; enabled/disabled boundaries tested. Same `fst.song-leaderboard.page-*` IDs as before this became a shared component. The web uses icon-only portal controls — intentional Fluent deviation, not pixel parity.
- Nav chrome (2026-09-28, operator: navigation "doesn't look good or native"): a `.principal` toolbar item replaces the concatenated `"Song - Instrument"` title with an `InstrumentIcon` beside a two-line song-title/instrument-label stack, plus inline title display mode. Rows are glass cards (`festivalGlass(.card)`, hidden separators) instead of a flat opaque table.
- Rows now navigate: tapping opens `AppRoute.player`, or `.statistics` for the currently selected player — closing the previously-open "rows cannot open player profiles" gap. `SongLeaderboardEntryRow`'s own initializer is unchanged, so Song Detail's preview keeps working.
- Accuracy/FC via the shared row ([score-accuracy/ios.md](../../controls/score-accuracy/ios.md)); the full List keeps separate row and `fst.score.accuracy.*` IDs.
- AccessibilityXXXL: the fixed song header left no usable List viewport and `99,900` wrapped into `99,90` + `0`. The header/disclosure now scroll above scores inside the same List, and rank/name, whole score and accuracy each get a full-width line; ordinary sizes keep compact columns.
- A live probe decoded one real 25-row Lead chart (2026-09-25); tapping into a live Solo page on device is not yet shown.
- Open: selected-profile footer; announced page change and stable VoiceOver focus (unchanged by the 2026-09-28 nav pass — `soloLeaderboardVisualStates` was re-run and still passes, which does not by itself certify either). Warm-offline "last seen scores" banners predate online-only — remove, don't extend.
