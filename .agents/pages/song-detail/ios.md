# Song Detail — iPhone notes

> **What:** iPhone implementation state, native decisions, gotchas and open gaps for Song Detail. **Read when:** changing Song Detail on iPhone. Behavior: [spec.md](spec.md).

## Implemented (partial)

- `SongScorePreview` lazily loads up to **ten** typed scores per visible chart via `GET /api/leaderboard/{songId}/{instrument}?top=10&offset=0` (the batched `/all?top=10` returned 403; no speculative fallback, no nine eager requests). Separate URL/ETag from the 25-row Solo chart. States: loading, empty, error/Retry, rows, View Full.
- Hidden chart removes its card but keeps its charted Intensity; the invalid-score leeway changes each preview request.
- Shared score row with the [score accuracy](../../controls/score-accuracy/ios.md) badge (explicit FC vs graded).
- Top-toolbar Paths action when any non-Karaoke path chart is enabled ([chopt-paths/ios.md](../../controls/chopt-paths/ios.md)); official Shop action/badge when validated.
- Intensity card now shows the real `InstrumentIcon` per charted instrument instead of its text label (the icon carries `instrument.label` as its own accessibility label, so nothing is lost for VoiceOver), and both the Intensity card and each `SongScorePreview` card use `festivalGlass(.card)`. "Intensity" and each chart's own heading use the shared white Title Case `FestivalSectionHeader`, not raw `Text(...).font(.title2.bold())`. Lead/Pro Lead's icon (chips too) now uses the keys variant when `Song.usesKeyboardIcon` (`sig == "Keyboard"`).
- `SongScorePreview` adds a "View `<chart>` score history" action, shown only when a player is selected, pushing `AppRoute.playerHistory(song, instrument)`. Web's only route to `/history` is a "View all scores" action under the selected player's own score-history graph (`ScoreHistoryChart.tsx`, `SongDetailPage.tsx:675`), gated on that player having history for the song; that graph is not ported, so this per-chart action is the interim equivalent, gated only on player selection rather than on having history data. The web solo leaderboard page has no `/history` link of its own to mirror.

## Native decisions

| Web | iPhone | Why |
|---|---|---|
| View All after the ten rows | **One** View Full directly under the chart heading, before rows | An offscreen programmatic tap below enlarged rows stalled the main thread in SwiftUI layout; the top action is directly hittable above tab chrome |
| View All only when rows exist | View Full also when loading/empty/error (pre-existing) | Open parity decision |
| FAB Paths, bottom controls | Top toolbar Paths, top controls in the sheet | Safe areas and legibility |
| Four icon-based Intensity meters with header artwork | Icon + `DifficultyMeter` per charted instrument, no header artwork treatment yet | Incremental: icons landed this wave, the fuller header redesign has not |

## Open (iPhone)

- Full-page `.all` audit fails: score rows under the Liquid Glass tab (y≈792/849 vs tab y=791) and large-type Intensity labels; edge/inset/footer/geometry attempts did not fix it and were reverted ([accessibility](../../testing/apple/accessibility.md)). Fix before certifying. Re-check after the glass/icon change above, since neither the audit nor a screen reader pass has been re-run against it.
- Missing: selected-player/member spotlight, the score-history graph itself (only its entry point exists so far), band cards, per-row profile navigation, full Paths.
- Done: warm-offline preview/path banners no longer render (`OfflineDisclosure`/`isStale`) per the online-only decision; the unrelated "unverified live" notice is unchanged.
