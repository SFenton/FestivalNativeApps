# Song Detail — iPhone notes

> **What:** iPhone implementation state, native decisions, gotchas and open gaps for Song Detail. **Read when:** changing Song Detail on iPhone. Behavior: [spec.md](spec.md).

## Implemented (partial)

- `SongScorePreview` lazily loads up to **ten** typed scores per visible chart via `GET /api/leaderboard/{songId}/{instrument}?top=10&offset=0` (the batched `/all?top=10` returned 403; no speculative fallback, no nine eager requests). Separate URL/ETag from the 25-row Solo chart. States: loading, empty, error/Retry, rows, View Full.
- Hidden chart removes its card but keeps its charted Intensity; the invalid-score leeway changes each preview request.
- Shared score row with the [score accuracy](../../controls/score-accuracy/ios.md) badge (explicit FC vs graded).
- Top-toolbar Paths action when any non-Karaoke path chart is enabled ([chopt-paths/ios.md](../../controls/chopt-paths/ios.md)); official Shop action/badge when validated.

## Native decisions

| Web | iPhone | Why |
|---|---|---|
| View All after the ten rows | **One** View Full directly under the chart heading, before rows | An offscreen programmatic tap below enlarged rows stalled the main thread in SwiftUI layout; the top action is directly hittable above tab chrome |
| View All only when rows exist | View Full also when loading/empty/error (pre-existing) | Open parity decision |
| FAB Paths, bottom controls | Top toolbar Paths, top controls in the sheet | Safe areas and legibility |

## Open (iPhone)

- Full-page `.all` audit fails: score rows under the Liquid Glass tab (y≈792/849 vs tab y=791) and large-type Intensity labels; edge/inset/footer/geometry attempts did not fix it and were reverted ([accessibility](../../testing/apple/accessibility.md)). Fix before certifying.
- Missing: icon-based Intensity header, selected-player/member spotlight and history, band cards, per-row profile navigation, full Paths.
- Warm-offline preview banners predate online-only; remove with the Songs offline cleanup.
